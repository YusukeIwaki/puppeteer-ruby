# rbs_inline: enabled

require 'base64'
require 'json'
require 'objspace'
require "stringio"

require_relative './page/metrics'
require_relative './page/pdf_options'
require_relative './page/screenshot_options'
require_relative './page/screenshot_task_queue'

class Puppeteer::Page
  include Puppeteer::DebugPrint
  include Puppeteer::EventCallbackable
  include Puppeteer::IfPresent
  using Puppeteer::DefineAsyncMethod

  # @rbs client: Puppeteer::CDPSession -- CDP session for the page
  # @rbs target: Puppeteer::Target -- Target associated with the page
  # @rbs ignore_https_errors: bool -- Ignore HTTPS errors
  # @rbs default_viewport: Puppeteer::Viewport? -- Default viewport for new pages
  # @rbs network_enabled: bool -- Whether network events are enabled
  # @rbs return: Puppeteer::Page -- Created page instance
  def self.create(client, target, ignore_https_errors, default_viewport, network_enabled: true)
    page = Puppeteer::Page.new(client, target, ignore_https_errors, network_enabled: network_enabled)
    page.init
    if default_viewport
      page.viewport = default_viewport
    end
    page
  end

  # @rbs client: Puppeteer::CDPSession -- CDP session for the page
  # @rbs target: Puppeteer::Target -- Target associated with the page
  # @rbs ignore_https_errors: bool -- Ignore HTTPS errors
  # @rbs network_enabled: bool -- Whether network events are enabled
  # @rbs return: void -- No return value
  def initialize(client, target, ignore_https_errors, network_enabled: true)
    @closed = false
    @client = client
    @target = target
    @tab_id = nil
    @keyboard = Puppeteer::Keyboard.new(client)
    @mouse = Puppeteer::Mouse.new(client, @keyboard)
    @timeout_settings = Puppeteer::TimeoutSettings.new
    @touchscreen = Puppeteer::TouchScreen.new(client, @keyboard)
    # @accessibility = Accessibility.new(client)
    @frame_manager = Puppeteer::FrameManager.new(client, self, ignore_https_errors, @timeout_settings, network_enabled: network_enabled)
    @emulation_manager = Puppeteer::EmulationManager.new(client)
    @tracing = Puppeteer::Tracing.new(client)
    @page_bindings = {}
    @page_binding_ids = {}
    @coverage = Puppeteer::Coverage.new(client)
    @javascript_enabled = true
    @screenshot_task_queue = ScreenshotTaskQueue.new
    @inflight_requests = Set.new
    @request_intercepted_listener_map = ObjectSpace::WeakMap.new
    @attached_sessions = Set.new

    @workers = {}
    @user_drag_interception_enabled = false
    @service_worker_bypassed = false

    @attached_session_listener_id = @client.add_event_listener(CDPSessionEmittedEvents::Ready) do |session|
      handle_attached_to_session(session)
    end
    @target_gone_listener_id = @target.target_manager.add_event_listener(
      TargetManagerEmittedEvents::TargetGone,
      &method(:handle_detached_from_target)
    )

    @frame_manager.on_event(FrameManagerEmittedEvents::FrameAttached) do |event|
      emit_event(PageEmittedEvents::FrameAttached, event)
    end
    @frame_manager.on_event(FrameManagerEmittedEvents::FrameDetached) do |event|
      emit_event(PageEmittedEvents::FrameDetached, event)
    end
    @frame_manager.on_event(FrameManagerEmittedEvents::FrameNavigated) do |event|
      emit_event(PageEmittedEvents::FrameNavigated, event)
    end

    network_manager = @frame_manager.network_manager
    network_manager.on_event(NetworkManagerEmittedEvents::Request) do |event|
      @inflight_requests.add(event)
      emit_event(PageEmittedEvents::Request, event)
    end
    network_manager.on_event(NetworkManagerEmittedEvents::Response) do |event|
      emit_event(PageEmittedEvents::Response, event)
    end
    network_manager.on_event(NetworkManagerEmittedEvents::RequestServedFromCache) do |event|
      emit_event(PageEmittedEvents::RequestServedFromCache, event)
    end
    network_manager.on_event(NetworkManagerEmittedEvents::RequestFailed) do |event|
      @inflight_requests.delete(event)
      emit_event(PageEmittedEvents::RequestFailed, event)
    end
    network_manager.on_event(NetworkManagerEmittedEvents::RequestFinished) do |event|
      @inflight_requests.delete(event)
      emit_event(PageEmittedEvents::RequestFinished, event)
    end
    @file_chooser_interception_is_disabled = false
    @file_chooser_interceptors = Set.new

    @client.on_event('Page.domContentEventFired') do |event|
      emit_event(PageEmittedEvents::DOMContentLoaded)
    end
    @client.on_event('Page.loadEventFired') do |event|
      emit_event(PageEmittedEvents::Load)
    end
    @client.add_event_listener('Runtime.consoleAPICalled') do |event|
      handle_console_api(event)
    end
    @client.add_event_listener('Runtime.bindingCalled') do |event|
      handle_binding_called(event)
    end
    @client.on_event('Page.javascriptDialogOpening') do |event|
      handle_dialog_opening(event)
    end
    @client.on_event('Runtime.exceptionThrown') do |exception|
      handle_exception(exception['exceptionDetails'])
    end
    @client.on_event('Inspector.targetCrashed') do |event|
      handle_target_crashed
    end
    @client.on_event('Performance.metrics') do |event|
      emit_event(PageEmittedEvents::Metrics, MetricsEvent.new(event))
    end
    @client.on_event('Log.entryAdded') do |event|
      handle_log_entry_added(event)
    end
    @client.on_event('Page.fileChooserOpened') do |event|
      handle_file_chooser(event)
    end
    Async do
      @target.is_closed_promise.wait
      @client.remove_event_listener(@attached_session_listener_id)
      @target.target_manager.remove_event_listener(@target_gone_listener_id)

      emit_event(PageEmittedEvents::Close)
      @closed = true
    end
  end

  private def handle_detached_from_target(target)
    session_id = target.session&.id
    @frame_manager.handle_detached_from_target(target)
    return unless session_id
    worker = @workers.delete(session_id)
    return unless worker
    emit_event(PageEmittedEvents::WorkerDestroyed, worker)
  end

  private def handle_attached_to_session(session)
    return if @attached_sessions.include?(session)
    @attached_sessions << session
    session.on(CDPSessionEmittedEvents::Ready) do |child_session|
      handle_attached_to_session(child_session)
    end

    target = session.target
    return unless target
    handle_attached_to_target(target)
  end

  private def handle_attached_to_target(target)
    @frame_manager.handle_attached_to_target(target)
    session = target.session
    if session && target.raw_type != 'worker'
      @frame_manager.network_manager.add_client(session)
    end
    if target.raw_type == 'worker'
      return unless session

      console_api_called = lambda do |world, event|
        values = event['args'].map do |arg|
          remote_object = Puppeteer::RemoteObject.new(arg)
          Puppeteer::JSHandle.create(context: world.execution_context, remote_object: remote_object)
        end
        add_console_message(event['type'], values, event['stackTrace'])
      end
      exception_thrown = method(:handle_exception)

      worker = Puppeteer::CdpWebWorker.new(
        session,
        target.url,
        target.target_id,
        target.raw_type,
        console_api_called,
        exception_thrown,
        network_manager: @frame_manager.network_manager,
      )
      @workers[session.id] = worker
      emit_event(PageEmittedEvents::WorkerCreated, worker)
    end
  end

  # @rbs return: Array[untyped] -- Initialization results
  def init
    Puppeteer::AsyncUtils.await_promise_all(
      @frame_manager.async_init(@target.target_id),
      @client.async_send_message('Performance.enable'),
      @client.async_send_message('Log.enable'),
    )
  end

  # @rbs return: bool -- Whether drag interception is enabled
  def drag_interception_enabled?
    @user_drag_interception_enabled
  end
  alias_method :drag_interception_enabled, :drag_interception_enabled?

  # @rbs event_name: (String | Symbol) -- Page event name
  # @rbs &block: ^(untyped) -> void -- Event handler
  # @rbs return: String -- Listener ID
  def on(event_name, &block)
    unless PageEmittedEvents.values.include?(event_name.to_s)
      raise ArgumentError.new("Unknown event name: #{event_name}. Known events are #{PageEmittedEvents.values.to_a.join(", ")}")
    end

    if event_name.to_s == 'request'
      wrapped = ->(req) { req.enqueue_intercept_action(-> { block.call(req) }) }
      if (listeners = @request_intercepted_listener_map[block])
        listeners << wrapped
      else
        @request_intercepted_listener_map[block] = [wrapped]
      end
      super('request', &wrapped)
    else
      super(event_name.to_s, &block)
    end
  end

  # @rbs event_name: (String | Symbol) -- Page event name
  # @rbs &block: ^(untyped) -> void -- Event handler
  # @rbs return: String -- Listener ID
  def once(event_name, &block)
    unless PageEmittedEvents.values.include?(event_name.to_s)
      raise ArgumentError.new("Unknown event name: #{event_name}. Known events are #{PageEmittedEvents.values.to_a.join(", ")}")
    end

    if event_name.to_s == 'request'
      wrapped = ->(req) { req.enqueue_intercept_action(-> { block.call(req) }) }
      if (listeners = @request_intercepted_listener_map[block])
        listeners << wrapped
      else
        @request_intercepted_listener_map[block] = [wrapped]
      end
      super('request', &wrapped)
    else
      super(event_name.to_s, &block)
    end
  end

  # @rbs event_name_or_id: (String | Symbol) -- Page event name or listener ID
  # @rbs listener: Proc? -- Event handler to remove
  # @rbs return: void -- No return value
  def off(event_name_or_id, listener = nil, &block)
    listener ||= block
    if listener && PageEmittedEvents.values.include?(event_name_or_id.to_s)
      event_name = event_name_or_id.to_s
      if event_name == 'request'
        listeners = @request_intercepted_listener_map[listener]
        wrapped = listeners&.shift
        return unless wrapped
        if listeners.empty?
          if @request_intercepted_listener_map.respond_to?(:delete)
            @request_intercepted_listener_map.delete(listener)
          else
            @request_intercepted_listener_map[listener] = nil
          end
        end
        super(event_name, wrapped)
      else
        super(event_name, listener)
      end
    else
      super(event_name_or_id)
    end
  end

  # @rbs event: Hash[String, untyped] -- File chooser event payload
  # @rbs return: void -- No return value
  def handle_file_chooser(event)
    return if @file_chooser_interceptors.empty?

    frame = @frame_manager.frame(event['frameId'])
    element = frame.main_world.adopt_backend_node(event['backendNodeId'])
    interceptors = @file_chooser_interceptors.to_a
    @file_chooser_interceptors.clear
    file_chooser = Puppeteer::FileChooser.new(element, event)
    interceptors.each do |promise|
      promise.resolve(file_chooser)
    end
  end

  # @rbs timeout: Numeric? -- Timeout in milliseconds
  # @rbs return: Puppeteer::FileChooser -- File chooser handle
  def wait_for_file_chooser(timeout: nil)
    if @file_chooser_interceptors.empty?
      @client.send_message('Page.setInterceptFileChooserDialog', enabled: true)
    end

    option_timeout = timeout || @timeout_settings.timeout
    promise = Async::Promise.new
    @file_chooser_interceptors << promise

    begin
      if option_timeout == 0
        promise.wait
      else
        Puppeteer::AsyncUtils.async_timeout(option_timeout, promise).wait
      end
    rescue Async::TimeoutError
      raise Puppeteer::TimeoutError.new("Waiting for `FileChooser` failed: #{option_timeout}ms exceeded")
    ensure
      @file_chooser_interceptors.delete(promise)
    end
  end

  define_async_method :async_wait_for_file_chooser

  # @rbs geolocation: Puppeteer::Geolocation -- Geolocation override
  # @rbs return: void -- No return value
  def geolocation=(geolocation)
    @client.send_message('Emulation.setGeolocationOverride', geolocation.to_h)
  end

  attr_reader :javascript_enabled, :service_worker_bypassed, :target, :client

  # @rbs return: String -- Tab target id
  def _tab_id
    return @tab_id if @tab_id

    parent_session = @client.respond_to?(:parent_session) ? @client.parent_session : nil
    @tab_id = parent_session&.target&.target_id || @target.target_id
  end

  # @rbs other: Object -- Other object to compare
  # @rbs return: bool -- Equality result
  def ==(other)
    other = other.__getobj__ if other.is_a?(Puppeteer::ReactorRunner::Proxy)
    return true if equal?(other)
    return false unless other.is_a?(Puppeteer::Page)
    return false unless @target&.target_id && other.target&.target_id

    @target.target_id == other.target.target_id
  end
  alias_method :javascript_enabled?, :javascript_enabled
  alias_method :service_worker_bypassed?, :service_worker_bypassed

  # @rbs return: Puppeteer::Browser -- Owning browser
  def browser
    @target.browser
  end

  # @rbs return: Puppeteer::BrowserContext -- Owning browser context
  def browser_context
    @target.browser_context
  end

  class TargetCrashedError < Puppeteer::Error; end

  private def handle_target_crashed
    emit_event(PageEmittedEvents::Error, TargetCrashedError.new('Page crashed!'))
  end

  private def handle_log_entry_added(event)
    entry = event['entry']
    level = entry['level']
    text = entry['text']
    source = entry['source']
    url = entry['url']
    line_number = entry['lineNumber']

    if_present(entry['args']) do |args|
      args.map do |arg|
        Puppeteer::RemoteObject.new(arg).async_release(@client)
      end
    end
    if source != 'worker'
      console_message_location = Puppeteer::ConsoleMessage::Location.new(
        url: url,
        line_number: line_number,
      )
      emit_event(PageEmittedEvents::Console,
        Puppeteer::ConsoleMessage.new(level, text, [], console_message_location))
    end
  end

  # @rbs return: Puppeteer::Frame -- Main frame
  def main_frame
    @frame_manager.main_frame
  end

  attr_reader :touchscreen, :coverage, :tracing, :accessibility
  alias_method :touch_screen, :touchscreen

  # @rbs block: Proc? -- Optional block for instance_eval
  # @rbs return: Puppeteer::Keyboard -- Keyboard instance
  def keyboard(&block)
    @keyboard.instance_eval(&block) unless block.nil?

    @keyboard
  end

  # @rbs return: Array[Puppeteer::Frame] -- All frames
  def frames
    @frame_manager.frames
  end

  # @rbs return: Array[untyped] -- Active web workers
  def workers
    @workers.values
  end

  # @rbs value: bool -- Enable request interception
  # @rbs return: void -- No return value
  def request_interception=(value)
    @frame_manager.network_manager.request_interception = value
  end

  # @rbs enabled: bool -- Enable drag interception
  # @rbs return: void -- No return value
  def drag_interception_enabled=(enabled)
    @user_drag_interception_enabled = enabled
    @client.send_message('Input.setInterceptDrags', enabled: enabled)
  end

  # @rbs bypass: bool -- Bypass service workers
  # @rbs return: void -- No return value
  def service_worker_bypassed=(bypass)
    @service_worker_bypassed = bypass
    @client.send_message('Network.setBypassServiceWorker', bypass: bypass)
  end

  # @rbs enabled: bool -- Enable offline mode
  # @rbs return: void -- No return value
  def offline_mode=(enabled)
    @frame_manager.network_manager.offline_mode = enabled
  end

  # @rbs network_condition: Puppeteer::NetworkCondition? -- Network condition override
  # @rbs return: void -- No return value
  def emulate_network_conditions(network_condition)
    @frame_manager.network_manager.emulate_network_conditions(network_condition)
  end

  # @rbs timeout: Numeric? -- Default navigation timeout in milliseconds
  # @rbs return: void -- No return value
  def default_navigation_timeout=(timeout)
    @timeout_settings.default_navigation_timeout = timeout
  end

  # @rbs timeout: Numeric? -- Default timeout in milliseconds
  # @rbs return: void -- No return value
  def default_timeout=(timeout)
    @timeout_settings.default_timeout = timeout
  end

  # @rbs return: Numeric -- Default timeout in milliseconds
  def default_timeout
    @timeout_settings.timeout
  end

  # @rbs selector_or_function: String -- Selector or JS function
  # @rbs return: Puppeteer::Locator -- Locator for selector or function
  def locator(selector_or_function)
    if Puppeteer::Locator.function_string?(selector_or_function)
      Puppeteer::FunctionLocator.create(self, selector_or_function)
    else
      Puppeteer::NodeLocator.create(self, selector_or_function)
    end
  end

  # `$()` in JavaScript.
  # @rbs selector: String -- CSS selector
  # @rbs return: Puppeteer::ElementHandle? -- Matching element or nil
  def query_selector(selector)
    main_frame.query_selector(selector)
  end
  alias_method :S, :query_selector

  define_async_method :async_query_selector

  # `$$()` in JavaScript.
  # @rbs selector: String -- CSS selector
  # @rbs isolate: bool? -- Use isolated world for queries
  # @rbs return: Array[Puppeteer::ElementHandle] -- Matching elements
  def query_selector_all(selector, isolate: nil)
    main_frame.query_selector_all(selector, isolate: isolate)
  end
  alias_method :SS, :query_selector_all

  define_async_method :async_query_selector_all

  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs return: Puppeteer::JSHandle -- Handle to evaluation result
  def evaluate_handle(page_function, *args)
    context = main_frame.execution_context
    context.evaluate_handle(page_function, *args)
  end

  define_async_method :async_evaluate_handle

  # @rbs prototype_handle: Puppeteer::JSHandle -- Prototype handle
  # @rbs return: Puppeteer::JSHandle -- Handle to query result
  def query_objects(prototype_handle)
    context = main_frame.execution_context
    context.query_objects(prototype_handle)
  end

  # `$eval()` in JavaScript.
  # @rbs selector: String -- CSS selector
  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs return: untyped -- Evaluation result
  def eval_on_selector(selector, page_function, *args)
    main_frame.eval_on_selector(selector, page_function, *args)
  end
  alias_method :Seval, :eval_on_selector

  define_async_method :async_eval_on_selector

  # `$$eval()` in JavaScript.
  # @rbs selector: String -- CSS selector
  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs return: untyped -- Evaluation result
  def eval_on_selector_all(selector, page_function, *args)
    main_frame.eval_on_selector_all(selector, page_function, *args)
  end
  alias_method :SSeval, :eval_on_selector_all

  define_async_method :async_eval_on_selector_all

  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @rbs expression: String -- XPath expression
  # @rbs return: Array[Puppeteer::ElementHandle] -- Matching elements
  def Sx(expression)
    main_frame.Sx(expression)
  end

  define_async_method :async_Sx

  # @rbs urls: Array[String] -- URLs to fetch cookies for
  # @rbs return: Array[Hash[String, untyped]] -- Cookies list
  def cookies(*urls)
    @client.send_message('Network.getCookies', urls: (urls.empty? ? [url] : urls))['cookies']
  end

  # check if each cookie element has required fields ('name' and 'value')
  private def assert_cookie_params(cookies, requires:)
    return if cookies.all? do |cookie|
      requires.all? { |field_name| cookie[field_name] || cookie[field_name.to_s] }
    end

    raise ArgumentError.new("Each coookie must have #{requires.join(" and ")} attribute.")
  end

  private def convert_same_site_for_cdp(same_site)
    case same_site
    when 'Strict', 'Lax', 'None'
      same_site
    else
      nil
    end
  end

  # @rbs cookies: Array[Hash[Symbol | String, untyped]] -- cookies parameter
  # @rbs return: void -- No return value
  def delete_cookie(*cookies)
    assert_cookie_params(cookies, requires: %i(name))

    page_url = url
    starts_with_http = page_url.start_with?("http")
    cookies.each do |cookie|
      item = (starts_with_http ? { url: page_url } : {}).merge(cookie)
      @client.send_message("Network.deleteCookies", item)
    end
  end

  # @rbs cookies: Array[Hash[Symbol | String, untyped]] -- cookies parameter
  # @rbs return: void -- No return value
  def set_cookie(*cookies)
    assert_cookie_params(cookies, requires: %i(name value))

    page_url = url
    starts_with_http = page_url.start_with?("http")
    items = cookies.map do |cookie|
      (starts_with_http ? { url: page_url } : {}).merge(cookie).tap do |item|
        item_name = item[:name] || item['name']
        item_url = item[:url] || item['url']
        raise ArgumentError.new("Blank page can not have cookie \"#{item_name}\"") if item_url == "about:blank"
        raise ArgumentError.new("Data URL page can not have cookie \"#{item_name}\"") if item_url&.start_with?("data:")

        same_site =
          if item.key?(:sameSite)
            item[:sameSite]
          elsif item.key?('sameSite')
            item['sameSite']
          elsif item.key?(:same_site)
            item[:same_site]
          else
            item['same_site']
          end

        converted_same_site = convert_same_site_for_cdp(same_site)
        item.delete(:sameSite)
        item.delete('sameSite')
        item.delete(:same_site)
        item.delete('same_site')
        item[:sameSite] = converted_same_site if converted_same_site
      end
    end
    delete_cookie(*items)
    unless items.empty?
      @client.send_message("Network.setCookies", cookies: items)
    end
  end

  # @rbs url: String? -- Script URL
  # @rbs path: String? -- Path to script file
  # @rbs content: String? -- Script contents
  # @rbs type: String? -- Script type
  # @rbs id: String? -- Script element ID
  # @rbs return: Puppeteer::ElementHandle -- Script element handle
  def add_script_tag(url: nil, path: nil, content: nil, type: nil, id: nil)
    main_frame.add_script_tag(url: url, path: path, content: content, type: type, id: id)
  end

  # @rbs url: String? -- Stylesheet URL
  # @rbs path: String? -- Path to stylesheet file
  # @rbs content: String? -- Stylesheet contents
  # @rbs return: Puppeteer::ElementHandle -- Style element handle
  def add_style_tag(url: nil, path: nil, content: nil)
    main_frame.add_style_tag(url: url, path: path, content: content)
  end

  # @rbs name: String -- Binding name
  # @rbs puppeteer_function: Proc -- Ruby callback
  # @rbs return: void -- No return value
  def expose_function(name, puppeteer_function)
    if @page_bindings[name]
      raise ArgumentError.new("Failed to add page binding with name `#{name}` already exists!")
    end
    @page_bindings[name] = puppeteer_function

    add_page_binding = <<~JAVASCRIPT
    function (type, bindingName) {
      /* Cast window to any here as we're about to add properties to it
      * via win[bindingName] which TypeScript doesn't like.
      */
      const win = window;
      const binding = win[bindingName];

      win[bindingName] = (...args) => {
        const me = window[bindingName];
        let callbacks = me.callbacks;
        if (!callbacks) {
          callbacks = new Map();
          me.callbacks = callbacks;
        }
        const seq = (me.lastSeq || 0) + 1;
        me.lastSeq = seq;
        const promise = new Promise((resolve, reject) =>
          callbacks.set(seq, { resolve, reject })
        );
        binding(JSON.stringify({ type, name: bindingName, seq, args }));
        return promise;
      };
    }
    JAVASCRIPT

    source = JavaScriptFunction.new(add_page_binding, ['exposedFun', name]).source
    @client.send_message('Runtime.addBinding', name: name)
    script = @client.send_message('Page.addScriptToEvaluateOnNewDocument', source: source)
    @page_binding_ids[name] = script['identifier']

    promises = @frame_manager.frames.map do |frame|
      frame.async_evaluate("() => #{source}")
    end
    Puppeteer::AsyncUtils.await_promise_all(*promises)

    nil
  end

  # @rbs name: String -- Binding name
  # @rbs return: void -- No return value
  def remove_exposed_function(name)
    identifier = @page_binding_ids[name]
    unless identifier
      raise ArgumentError.new("Function with name \"#{name}\" does not exist")
    end

    @page_binding_ids.delete(name)
    @page_bindings.delete(name)

    @client.send_message('Runtime.removeBinding', name: name)
    @client.send_message('Page.removeScriptToEvaluateOnNewDocument', identifier: identifier)

    remove_script = '(name) => { delete window[name]; }'
    @frame_manager.frames.each do |frame|
      frame.evaluate(remove_script, name)
    rescue StandardError
      nil
    end
    nil
  end

  # @rbs username: String? -- HTTP basic auth username
  # @rbs password: String? -- HTTP basic auth password
  # @rbs return: void -- No return value
  def authenticate(username: nil, password: nil)
    @frame_manager.network_manager.authenticate(username: username, password: password)
  end

  # @rbs headers: Hash[String, String] -- Extra HTTP headers
  # @rbs return: void -- No return value
  def extra_http_headers=(headers)
    @frame_manager.network_manager.extra_http_headers = headers
  end

  # @rbs user_agent: String -- User agent string
  # @rbs user_agent_metadata: Hash[String, untyped]? -- User agent metadata
  # @rbs return: void -- No return value
  def set_user_agent(user_agent, user_agent_metadata = nil)
    @frame_manager.network_manager.set_user_agent(user_agent, user_agent_metadata)
  end
  alias_method :user_agent=, :set_user_agent

  # @rbs return: Puppeteer::Page::Metrics -- Page metrics
  def metrics
    response = @client.send_message('Performance.getMetrics')
    Metrics.new(response['metrics'])
  end

  # @rbs path: String -- Output path for the heap snapshot
  # @rbs return: void -- No return value
  def capture_heap_snapshot(path:)
    @client.send_message('HeapProfiler.enable')
    @client.send_message('HeapProfiler.collectGarbage')

    begin
      File.open(path, 'w') do |file|
        listener_id = @client.add_event_listener('HeapProfiler.addHeapSnapshotChunk') do |event|
          file.write(event['chunk'])
        end

        begin
          @client.send_message('HeapProfiler.takeHeapSnapshot', reportProgress: false)
        ensure
          @client.remove_event_listener(listener_id)
        end
      end
    ensure
      @client.send_message('HeapProfiler.disable')
    end
  end

  class PageError < Puppeteer::Error ; end

  private def handle_exception(exception_details)
    exception = exception_details['exception']
    if exception
      is_error_object = exception['type'] == 'object' && exception['subtype'] == 'error'
      if !is_error_object && !exception.key?('objectId')
        emit_event(PageEmittedEvents::PageError, Puppeteer::RemoteObject.new(exception).value)
        return
      end
    end

    message = Puppeteer::ExceptionDetails.new(exception_details).message
    err = PageError.new(message)
    #   err.stack = ''; // Don't report clientside error with a node stack attached
    emit_event(PageEmittedEvents::PageError, err)
  end

  private def handle_console_api(event)
    if event['executionContextId'] == 0
      # DevTools protocol stores the last 1000 console messages. These
      # messages are always reported even for removed execution contexts. In
      # this case, they are marked with executionContextId = 0 and are
      # reported upon enabling Runtime agent.
      #
      # Ignore these messages since:
      # - there's no execution context we can use to operate with message
      #   arguments
      # - these messages are reported before Puppeteer clients can subscribe
      #   to the 'console'
      #   page event.
      #
      # @see https://github.com/puppeteer/puppeteer/issues/3865
      return
    end

    context = @frame_manager.execution_context_by_id(event['executionContextId'], @client)
    values = event['args'].map do |arg|
      remote_object = Puppeteer::RemoteObject.new(arg)
      Puppeteer::JSHandle.create(context: context, remote_object: remote_object)
    end
    add_console_message(event['type'], values, event['stackTrace'])
  end

  # @rbs event: Hash[String, untyped] -- Binding called payload
  # @rbs return: void -- No return value
  def handle_binding_called(event)
    execution_context_id = event['executionContextId']
    payload =
      begin
        JSON.parse(event['payload'])
      rescue
        # The binding was either called by something in the page or it was
        # called before our wrapper was initialized.
        return
      end
    name = payload['name']
    seq = payload['seq']
    args = payload['args']

    if payload['type'] != 'exposedFun' || !@page_bindings[name]
      return
    end

    expression =
      begin
        result = @page_bindings[name].call(*args)

        deliver_result = <<~JAVASCRIPT
        function (name, seq, result) {
          window[name].callbacks.get(seq).resolve(result);
          window[name].callbacks.delete(seq);
        }
        JAVASCRIPT

        JavaScriptFunction.new(deliver_result, [name, seq, result]).source
      rescue => err
        deliver_error = <<~JAVASCRIPT
        function (name, seq, message) {
          const error = new Error(message);
          window[name].callbacks.get(seq).reject(error);
          window[name].callbacks.delete(seq);
        }
        JAVASCRIPT
        JavaScriptFunction.new(deliver_error, [name, seq, err.message]).source
      end

    Async do
      @client.async_send_message('Runtime.evaluate', expression: expression, contextId: execution_context_id).wait
    rescue => error
      debug_puts(error)
    end
  end

  private def add_console_message(type, args, stack_trace)
    text_tokens = args.map { |arg| console_value_from_js_handle(arg) }

    stack_trace_locations =
      if stack_trace && stack_trace['callFrames']
        stack_trace['callFrames'].map do |call_frame|
          Puppeteer::ConsoleMessage::Location.new(
            url: call_frame['url'],
            line_number: call_frame['lineNumber'],
            column_number: call_frame['columnNumber'],
          )
        end
      else
        []
      end
    console_message = Puppeteer::ConsoleMessage.new(type, text_tokens.join(' '), args, stack_trace_locations)
    emit_event(PageEmittedEvents::Console, console_message)
  end

  private def console_value_from_js_handle(handle)
    remote_object = handle.remote_object
    return remote_object.value unless remote_object.object_id?

    value_from_remote_object_reference(remote_object)
  end

  private def value_from_remote_object_reference(remote_object)
    description = remote_object.description.to_s
    if remote_object.sub_type == 'error' && !description.empty?
      newline_index = description.index("\n")
      return newline_index ? description[0...newline_index] : description
    end

    type = remote_object.sub_type || remote_object.type
    class_name = remote_object.class_name || remote_object.description || 'Object'
    "[#{type} #{class_name}]"
  end

  private def handle_dialog_opening(event)
    dialog_type = event['type']
    unless %w(alert confirm prompt beforeunload).include?(dialog_type)
      raise ArgumentError.new("Unknown javascript dialog type: #{dialog_type}")
    end
    dialog = Puppeteer::CdpDialog.new(@client,
              type: dialog_type,
              message: event['message'],
              default_value: event['defaultPrompt'])
    emit_event(PageEmittedEvents::Dialog, dialog)
  end

  private def set_transparent_background_color(&block)
    @client.send_message(
      'Emulation.setDefaultBackgroundColorOverride',
      color: { r: 0, g: 0, b: 0, a: 0 })
  end

  private def reset_default_background_color(&block)
    @client.send_message('Emulation.setDefaultBackgroundColorOverride')
  end

  # @rbs return: String? -- Page URL
  def url
    main_frame.url
  end

  # @rbs return: String -- Page HTML content
  def content
    main_frame.content
  end

  # @rbs html: String -- HTML content
  # @rbs timeout: Numeric? -- Navigation timeout in milliseconds
  # @rbs wait_until: String | Array[String] | nil -- Lifecycle events to wait for
  # @rbs return: void -- No return value
  def set_content(html, timeout: nil, wait_until: nil)
    main_frame.set_content(html, timeout: timeout, wait_until: wait_until)
  end

  # @rbs html: String -- HTML content
  # @rbs return: void -- No return value
  def content=(html)
    main_frame.set_content(html)
  end

  # @rbs url: String -- URL to navigate
  # @rbs referer: String? -- Referer header value
  # @rbs referer: String? -- Referer header value
  # @rbs referrer_policy: String? -- Referrer policy
  # @rbs timeout: Numeric? -- Navigation timeout in milliseconds
  # @rbs wait_until: String | Array[String] | nil -- Lifecycle events to wait for
  # @rbs return: Puppeteer::HTTPResponse? -- Navigation response
  def goto(url, referer: nil, referrer_policy: nil, timeout: nil, wait_until: nil)
    main_frame.goto(
      url,
      referer: referer,
      referrer_policy: referrer_policy,
      timeout: timeout,
      wait_until: wait_until,
    )
  end

  # @rbs timeout: Numeric? -- Navigation timeout in milliseconds
  # @rbs wait_until: String | Array[String] | nil -- Lifecycle events to wait for
  # @rbs ignore_cache: bool? -- Skip cache when reloading
  # @rbs return: Puppeteer::HTTPResponse? -- Navigation response
  def reload(timeout: nil, wait_until: nil, ignore_cache: nil)
    params = {}
    params[:ignoreCache] = ignore_cache unless ignore_cache.nil?

    wait_for_navigation(timeout: timeout, wait_until: wait_until, ignore_same_document_navigation: true) do
      if params.empty?
        @client.send_message('Page.reload')
      else
        @client.send_message('Page.reload', **params)
      end
    end
  end

  # @rbs timeout: Numeric? -- Navigation timeout in milliseconds
  # @rbs wait_until: String | Array[String] | nil -- Lifecycle events to wait for
  # @rbs ignore_same_document_navigation: bool -- Ignore same-document navigation
  # @rbs return: Puppeteer::HTTPResponse? -- Navigation response
  def wait_for_navigation(timeout: nil, wait_until: nil, ignore_same_document_navigation: false)
    main_frame.send(
      :wait_for_navigation,
      timeout: timeout,
      wait_until: wait_until,
      ignore_same_document_navigation: ignore_same_document_navigation,
    )
  end

  # @!method async_wait_for_navigation(timeout: nil, wait_until: nil)
  #
  define_async_method :async_wait_for_navigation

  private def wait_for_network_manager_event(event_name, predicate:, timeout:)
    option_timeout = timeout || @timeout_settings.timeout

    promise = Async::Promise.new

    listener_id = @frame_manager.network_manager.add_event_listener(event_name) do |event_target|
      if Puppeteer::AsyncUtils.await(predicate.call(event_target))
        promise.resolve(event_target)
      end
    end

    begin
      if option_timeout == 0
        Puppeteer::AsyncUtils.await_promise_race(promise, session_close_promise)
      else
        Puppeteer::AsyncUtils.async_timeout(option_timeout, -> {
          Puppeteer::AsyncUtils.await_promise_race(promise, session_close_promise)
        }).wait
      end
    rescue Async::TimeoutError
      raise Puppeteer::TimeoutError.new("waiting for #{event_name} failed: timeout #{option_timeout}ms exceeded")
    ensure
      @frame_manager.network_manager.remove_event_listener(listener_id)
    end
  end

  private def wait_for_frame_manager_event(*event_names, predicate:, timeout:)
    option_timeout = timeout || @timeout_settings.timeout

    promise = Async::Promise.new

    listener_ids = event_names.map do |event_name|
      @frame_manager.add_event_listener(event_name) do |event_target|
        if Puppeteer::AsyncUtils.await(predicate.call(event_target))
          promise.resolve(event_target) unless promise.resolved?
        end
      end
    end

    begin
      if option_timeout == 0
        Puppeteer::AsyncUtils.await_promise_race(promise, session_close_promise)
      else
        Puppeteer::AsyncUtils.async_timeout(option_timeout, -> {
          Puppeteer::AsyncUtils.await_promise_race(promise, session_close_promise)
        }).wait
      end
    rescue Async::TimeoutError
      raise Puppeteer::TimeoutError.new("waiting for #{event_names.join(" or ")} failed: timeout #{option_timeout}ms exceeded")
    ensure
      listener_ids.each do |listener_id|
        @frame_manager.remove_event_listener(listener_id)
      end
    end
  end

  private def session_close_promise
    @disconnect_promise ||= Async::Promise.new.tap do |future|
      @client.observe_first(CDPSessionEmittedEvents::Disconnected) do
        future.reject(Puppeteer::CDPSession::Error.new('Target Closed'))
      end
    end
  end

  # @rbs url: String? -- URL to match
  # @rbs predicate: Proc? -- Predicate to match
  # @rbs timeout: Numeric? -- Timeout in milliseconds
  # @rbs return: Puppeteer::HTTPRequest -- Matching request
  def wait_for_request(url: nil, predicate: nil, timeout: nil)
    if !url && !predicate
      raise ArgumentError.new('url or predicate must be specified')
    end
    if predicate && !predicate.is_a?(Proc)
      raise ArgumentError.new('predicate must be a proc.')
    end
    request_predicate =
      if url
        -> (request) { request.url == url }
      else
        predicate
      end

    wait_for_network_manager_event(NetworkManagerEmittedEvents::Request,
      predicate: request_predicate,
      timeout: timeout,
    )
  end

  # @!method async_wait_for_request(url: nil, predicate: nil, timeout: nil)
  #
  # Waits until request URL matches or request matches the given predicate.
  #
  # Waits until request URL matches
  #  wait_for_request(url: 'https://example.com/awesome')
  #
  # Waits until request matches the given predicate
  #  wait_for_request(predicate: -> (req){ req.url.start_with?('https://example.com/search') })
  #
  define_async_method :async_wait_for_request

  # @rbs url: String? -- URL to match
  # @rbs predicate: Proc? -- Predicate to match
  # @rbs timeout: Numeric? -- Timeout in milliseconds
  # @rbs return: Puppeteer::HTTPResponse -- Matching response
  def wait_for_response(url: nil, predicate: nil, timeout: nil)
    if !url && !predicate
      raise ArgumentError.new('url or predicate must be specified')
    end
    if predicate && !predicate.is_a?(Proc)
      raise ArgumentError.new('predicate must be a proc.')
    end
    response_predicate =
      if url
        -> (response) { response.url == url }
      else
        predicate
      end

    wait_for_network_manager_event(NetworkManagerEmittedEvents::Response,
      predicate: response_predicate,
      timeout: timeout,
    )
  end

  # @!method async_wait_for_response(url: nil, predicate: nil, timeout: nil)
  #
  define_async_method :async_wait_for_response

  # @rbs idle_time: Numeric -- Idle time to wait for in milliseconds
  # @rbs timeout: Numeric? -- Timeout in milliseconds
  # @rbs concurrency: Integer -- Allowed number of concurrent requests
  # @rbs return: void -- No return value
  def wait_for_network_idle(idle_time: 500, timeout: nil, concurrency: 0)
    option_timeout = timeout || @timeout_settings.timeout

    promise = Async::Promise.new
    idle_timer = nil

    schedule_idle = lambda do
      return if @inflight_requests.size > concurrency

      idle_timer&.stop
      idle_timer = Async do
        Puppeteer::AsyncUtils.sleep_seconds(idle_time / 1000.0)
        unless promise.resolved? || @inflight_requests.size > concurrency
          promise.resolve(nil)
        end
      end
    end

    # Use raw listener to avoid request interception queue delaying idle tracking.
    request_listener = add_event_listener('request') do
      idle_timer&.stop
      idle_timer = nil
    end
    request_finished_listener = on('requestfinished') do
      schedule_idle.call
    end
    request_failed_listener = on('requestfailed') do
      schedule_idle.call
    end

    schedule_idle.call

    begin
      if option_timeout == 0
        Puppeteer::AsyncUtils.await_promise_race(promise, session_close_promise)
      else
        Puppeteer::AsyncUtils.async_timeout(option_timeout, -> {
          Puppeteer::AsyncUtils.await_promise_race(promise, session_close_promise)
        }).wait
      end
    rescue Async::TimeoutError
      raise Puppeteer::TimeoutError.new("waiting for network idle failed: timeout #{option_timeout}ms exceeded")
    ensure
      off(request_listener)
      off(request_finished_listener)
      off(request_failed_listener)
      idle_timer&.stop
    end
  end

  define_async_method :async_wait_for_network_idle

  # @rbs url: String? -- URL to match
  # @rbs predicate: Proc? -- Predicate to match
  # @rbs timeout: Numeric? -- Timeout in milliseconds
  # @rbs return: Puppeteer::Frame -- Matching frame
  def wait_for_frame(url: nil, predicate: nil, timeout: nil)
    if !url && !predicate
      raise ArgumentError.new('url or predicate must be specified')
    end
    if predicate && !predicate.is_a?(Proc)
      raise ArgumentError.new('predicate must be a proc.')
    end
    frame_predicate =
      if url
        -> (frame) { frame.url == url }
      else
        predicate
      end

    frames.each do |frame|
      return frame if frame_predicate.call(frame)
    end

    wait_for_frame_manager_event(
      FrameManagerEmittedEvents::FrameAttached,
      FrameManagerEmittedEvents::FrameNavigated,
      predicate: frame_predicate,
      timeout: timeout,
    )
  end

  # @!method async_wait_for_frame(url: nil, predicate: nil, timeout: nil)
  #
  define_async_method :async_wait_for_frame

  # @rbs timeout: Numeric? -- Navigation timeout in milliseconds
  # @rbs wait_until: String | Array[String] | nil -- Lifecycle events to wait for
  # @rbs return: Puppeteer::HTTPResponse? -- Navigation response
  def go_back(timeout: nil, wait_until: nil)
    go(-1, timeout: timeout, wait_until: wait_until)
  end

  # @rbs timeout: Numeric? -- Navigation timeout in milliseconds
  # @rbs wait_until: String | Array[String] | nil -- Lifecycle events to wait for
  # @rbs return: Puppeteer::HTTPResponse? -- Navigation response
  def go_forward(timeout: nil, wait_until: nil)
    go(+1, timeout: timeout, wait_until: wait_until)
  end

  private def go(delta, timeout: nil, wait_until: nil)
    history = @client.send_message('Page.getNavigationHistory')
    entries = history['entries']
    index = history['currentIndex'] + delta
    if index < 0 || index >= entries.length
      raise Puppeteer::Error.new('History entry to navigate to not found.')
    end
    entry = entries[index]
    wait_for_navigation(timeout: timeout, wait_until: wait_until) do
      @client.send_message('Page.navigateToHistoryEntry', entryId: entry['id'])
    end
  end

  # Brings page to front (activates tab).
  # @rbs return: void -- No return value
  def bring_to_front
    @client.send_message('Page.bringToFront')
  end

  # @rbs device: Puppeteer::Device -- Device descriptor
  # @rbs return: void -- No return value
  def emulate(device)
    self.viewport = device.viewport
    self.user_agent = device.user_agent
  end

  # @rbs enabled: bool -- Enable JavaScript
  # @rbs return: void -- No return value
  def javascript_enabled=(enabled)
    return if @javascript_enabled == enabled
    @javascript_enabled = enabled
    @client.send_message('Emulation.setScriptExecutionDisabled', value: !enabled)
  end

  # @rbs enabled: bool -- Enable bypassing CSP
  # @rbs return: void -- No return value
  def bypass_csp=(enabled)
    @client.send_message('Page.setBypassCSP', enabled: enabled)
  end

  # @rbs media_type: (String | Symbol)? -- Media type override
  # @rbs return: void -- No return value
  def emulate_media_type(media_type)
    media_type_str = media_type.to_s
    unless ['screen', 'print', ''].include?(media_type_str)
      raise ArgumentError.new("Unsupported media type: #{media_type}")
    end
    @client.send_message('Emulation.setEmulatedMedia', media: media_type_str)
  end

  # @rbs factor: Numeric? -- CPU throttling rate
  # @rbs return: void -- No return value
  def emulate_cpu_throttling(factor)
    if factor.nil? || factor >= 1
      @client.send_message('Emulation.setCPUThrottlingRate', rate: factor || 1)
    else
      raise ArgumentError.new('Throttling rate should be greater or equal to 1')
    end
  end

  # @rbs features: Array[Hash[Symbol, untyped]]? -- Media feature overrides
  # @rbs return: void -- No return value
  def emulate_media_features(features)
    if features.nil?
      @client.send_message('Emulation.setEmulatedMedia', features: nil)
    elsif features.is_a?(Array)
      features.each do |media_feature|
        name = media_feature[:name]
        unless /^(?:prefers-(?:color-scheme|reduced-motion)|color-gamut)$/.match?(name)
          raise ArgumentError.new("Unsupported media feature: #{name}")
        end
      end
      @client.send_message('Emulation.setEmulatedMedia', features: features)
    end
  end

  # @rbs timezone_id: String? -- Timezone ID
  # @rbs return: void -- No return value
  def emulate_timezone(timezone_id)
    @client.send_message('Emulation.setTimezoneOverride', timezoneId: timezone_id || '')
  rescue => err
    if err.message.include?('Invalid timezone')
      raise ArgumentError.new("Invalid timezone ID: #{timezone_id}")
    else
      raise err
    end
  end

  VISION_DEFICIENCY_TYPES = %w[
    none
    achromatopsia
    blurredVision
    deuteranopia
    protanopia
    tritanopia
  ].freeze

  # @rbs vision_deficiency_type: String? -- Vision deficiency type
  # @rbs return: void -- No return value
  def emulate_vision_deficiency(vision_deficiency_type)
    value = vision_deficiency_type || 'none'
    unless VISION_DEFICIENCY_TYPES.include?(value)
      raise ArgumentError.new("Unsupported vision deficiency: #{vision_deficiency_type}")
    end
    @client.send_message('Emulation.setEmulatedVisionDeficiency', type: value)
  end

  # @rbs is_user_active: bool? -- User activity override
  # @rbs is_screen_unlocked: bool? -- Screen unlocked override
  # @rbs return: void -- No return value
  def emulate_idle_state(is_user_active: nil, is_screen_unlocked: nil)
    overrides = {
      isUserActive: is_user_active,
      isScreenUnlocked: is_screen_unlocked,
    }.compact

    if overrides.empty?
      @client.send_message('Emulation.clearIdleOverride')
    else
      @client.send_message('Emulation.setIdleOverride', overrides)
    end
  end

  # @rbs viewport: Puppeteer::Viewport? -- Viewport settings
  # @rbs return: void -- No return value
  def viewport=(viewport)
    needs_reload = @emulation_manager.emulate_viewport(viewport)
    @viewport = viewport
    reload if needs_reload
  end

  attr_reader :viewport

  # @rbs page_function: String -- page_function parameter
  # @rbs args: Array[untyped] -- args parameter
  # @rbs return: untyped -- Result
  def evaluate(page_function, *args)
    main_frame.evaluate(page_function, *args)
  end

  define_async_method :async_evaluate

  class JavaScriptFunction
    # @rbs expression: String -- Function expression
    # @rbs args: Array[untyped] -- Arguments for evaluation
    # @rbs return: void -- No return value
    def initialize(expression, args)
      @expression = expression
      @args = args
    end

    # @rbs return: String -- Generated source
    def source
      "(#{@expression})(#{arguments})"
    end

    private def arguments
      @args.map { |arg| arg.nil? ? nil : JSON.dump(arg) }.join(", ")
    end
  end

  class JavaScriptExpression
    # @rbs expression: String -- Expression to evaluate
    # @rbs return: void -- No return value
    def initialize(expression)
      @expression = expression
    end

    # @rbs return: String -- Generated source
    def source
      @expression
    end
  end

  # @rbs page_function: String -- page_function parameter
  # @rbs args: Array[untyped] -- args parameter
  # @rbs return: Hash[String, untyped] -- CDP response
  def evaluate_on_new_document(page_function, *args)
    source =
      if ['=>', 'async', 'function'].any? { |keyword| page_function.include?(keyword) }
        JavaScriptFunction.new(page_function, args).source
      else
        JavaScriptExpression.new(page_function).source
      end

    @client.send_message('Page.addScriptToEvaluateOnNewDocument', source: source)
  end

  # @rbs identifier: String -- Script identifier to remove
  # @rbs return: void
  def remove_script_to_evaluate_on_new_document(identifier)
    @client.send_message('Page.removeScriptToEvaluateOnNewDocument', identifier: identifier)
  end

  # @rbs enabled: bool -- Enable cache usage
  def cache_enabled=(enabled)
    @frame_manager.network_manager.cache_enabled = enabled
  end

  # @rbs return: String -- Page title
  def title
    main_frame.title
  end

  # @rbs type: String? -- Image format
  # @rbs path: String? -- File path to save
  # @rbs full_page: bool? -- Capture full page
  # @rbs clip: Hash[Symbol, Numeric]? -- Clip rectangle
  # @rbs quality: Integer? -- JPEG quality
  # @rbs omit_background: bool? -- Omit background for PNG
  # @rbs encoding: String? -- Encoding (base64 or binary)
  # @rbs capture_beyond_viewport: bool? -- Capture beyond viewport
  # @rbs from_surface: bool? -- Capture from surface
  # @rbs return: String -- Screenshot data
  def screenshot(type: nil,
                 path: nil,
                 full_page: nil,
                 clip: nil,
                 quality: nil,
                 omit_background: nil,
                 encoding: nil,
                 capture_beyond_viewport: nil,
                 from_surface: nil)
    options = {
      type: type,
      path: path,
      full_page: full_page,
      clip: clip,
      quality:  quality,
      omit_background: omit_background,
      encoding: encoding,
      capture_beyond_viewport: capture_beyond_viewport,
      from_surface: from_surface,
    }.compact
    screenshot_options = ScreenshotOptions.new(options)

    guard = browser_context.start_screenshot
    @screenshot_task_queue.post_task do
      screenshot_task(screenshot_options.type, screenshot_options)
    end
  ensure
    guard&.release
  end

  private def screenshot_task(format, screenshot_options)
    @client.send_message('Target.activateTarget', targetId: @target.target_id)

    clip = if_present(screenshot_options.clip) do |rect|
      x = rect[:x].round
      y = rect[:y].round
      scale = rect[:scale] || 1
      { x: x, y: y, width: rect[:width] + rect[:x] - x, height: rect[:height] + rect[:y] - y, scale: scale }
    end

    if screenshot_options.full_page?
      metrics = @client.send_message('Page.getLayoutMetrics')
      width = metrics['contentSize']['width'].ceil
      height = metrics['contentSize']['height'].ceil

      # Overwrite clip for full page at all times.
      clip = { x: 0, y: 0, width: width, height: height, scale: 1 }

      unless screenshot_options.capture_beyond_viewport?
        screen_orientation =
          if @viewport&.landscape?
            { angle: 90, type: 'landscapePrimary' }
          else
            { angle: 0, type: 'portraitPrimary' }
          end
        @client.send_message('Emulation.setDeviceMetricsOverride',
          mobile: @viewport&.mobile? || false,
          width: width,
          height: height,
          deviceScaleFactor: @viewport&.device_scale_factor || 1,
          screenOrientation: screen_orientation)
      end
    elsif !clip
      screenshot_options.unset_capture_beyond_viewport!
    end

    should_set_default_background = screenshot_options.omit_background? && format == 'png'
    set_transparent_background_color if should_set_default_background
    screenshot_params = {
      format: format,
      quality: screenshot_options.quality,
      clip: clip,
      captureBeyondViewport: screenshot_options.capture_beyond_viewport?,
      fromSurface: screenshot_options.from_surface,
    }.compact
    result = @client.send_message('Page.captureScreenshot', screenshot_params)
    reset_default_background_color if should_set_default_background

    if screenshot_options.full_page? && @viewport
      self.viewport = @viewport
    end

    buffer =
      if screenshot_options.encoding == 'base64'
        result['data']
      else
        Base64.decode64(result['data'])
      end

    if screenshot_options.path
      File.binwrite(screenshot_options.path, buffer)
    end

    buffer
  end

  class PrintToPdfIsNotImplementedError < Puppeteer::Error
    # @rbs return: void -- No return value
    def initialize
      super('pdf() is only available in headless mode. See https://github.com/puppeteer/puppeteer/issues/1829')
    end
  end

  # @rbs options: Hash[Symbol, untyped] -- PDF options
  # @rbs return: Enumerable[String] -- PDF data chunks
  def create_pdf_stream(options = {})
    timeout_helper = Puppeteer::TimeoutHelper.new('Page.printToPDF',
                      timeout_ms: options[:timeout],
                      default_timeout_ms: 30000)
    pdf_options = PDFOptions.new(options)
    omit_background = options[:omit_background]
    set_transparent_background_color if omit_background
    result =
      begin
        timeout_helper.with_timeout do
          @client.send_message('Page.printToPDF', pdf_options.page_print_args)
        end
      ensure
        reset_default_background_color if omit_background
      end

    Puppeteer::ProtocolStreamReader.new(
      client: @client,
      handle: result['stream'],
    ).read_as_chunks
  end

  # @rbs options: Hash[Symbol, untyped] -- PDF options
  # @rbs return: String -- PDF data
  def pdf(options = {})
    chunks = create_pdf_stream(options)

    StringIO.open do |stringio|
      if options[:path]
        File.open(options[:path], 'wb') do |f|
          chunks.each do |chunk|
            f.write(chunk)
            stringio.write(chunk)
          end
        end
      else
        chunks.each do |chunk|
          stringio.write(chunk)
        end
      end

      stringio.string
    end
  rescue => err
    if err.message.include?('PrintToPDF is not implemented')
      raise PrintToPdfIsNotImplementedError.new
    else
      raise
    end
  end

  # @rbs run_before_unload: bool -- Whether to run beforeunload handlers
  # @rbs return: void -- No return value
  def close(run_before_unload: false)
    guard = browser_context.wait_for_screenshot_operations
    begin
      unless @client.connection
        raise 'Protocol error: Connection closed. Most likely the page has been closed.'
      end

      if run_before_unload
        @client.send_message('Page.close')
      else
        @client.connection.send_message('Target.closeTarget', targetId: @target.target_id)
        @target.is_closed_promise.wait

        # @closed sometimes remains false, so wait for @closed = true with 100ms timeout.
        25.times do
          break if @closed
          Puppeteer::AsyncUtils.sleep_seconds(0.004)
        end
      end
    rescue Puppeteer::Connection::ProtocolError => err
      raise unless err.message.match?(/Target closed/i)
    ensure
      guard&.release
    end
  end

  # @rbs return: bool -- Whether the page is closed
  def closed?
    @closed
  end

  attr_reader :mouse

  # @rbs selector: String -- CSS selector
  # @rbs delay: Numeric? -- Delay between down and up (ms)
  # @rbs button: String? -- Mouse button
  # @rbs click_count: Integer? -- Deprecated: use count (click_count only sets clickCount)
  # @rbs count: Integer? -- Number of clicks to perform
  # @rbs return: void -- No return value
  def click(selector, delay: nil, button: nil, click_count: nil, count: nil)
    main_frame.click(selector, delay: delay, button: button, click_count: click_count, count: count)
  end

  define_async_method :async_click

  # @rbs selector: String -- CSS selector
  # @rbs return: void -- No return value
  def focus(selector)
    main_frame.focus(selector)
  end

  define_async_method :async_focus

  # @rbs selector: String -- CSS selector
  # @rbs return: void -- No return value
  def hover(selector)
    main_frame.hover(selector)
  end

  # @rbs selector: String -- CSS selector
  # @rbs values: Array[String] -- Option values to select
  # @rbs return: Array[String] -- Selected values
  def select(selector, *values)
    main_frame.select(selector, *values)
  end

  define_async_method :async_select

  # @rbs selector: String? -- CSS selector
  # @rbs block: Proc? -- Optional block for Object#tap usage
  # @rbs return: Puppeteer::Page | nil -- Page instance or nil
  def tap(selector: nil, &block)
    # resolves double meaning of tap.
    if selector.nil? && block
      # Original usage of Object#tap.
      #
      # browser.new_page.tap do |page|
      #   ...
      # end
      block.call(self)
      return self
    end

    # Puppeteer's Page#tap.
    main_frame.tap(selector)
    nil
  end

  define_async_method :async_tap

  # @rbs selector: String -- CSS selector
  # @rbs text: String -- Text to type
  # @rbs delay: Numeric? -- Delay between key presses (ms)
  # @rbs return: void -- No return value
  def type_text(selector, text, delay: nil)
    main_frame.type_text(selector, text, delay: delay)
  end

  define_async_method :async_type_text

  # @rbs selector: String -- CSS selector
  # @rbs visible: bool? -- Wait for element to be visible
  # @rbs hidden: bool? -- Wait for element to be hidden
  # @rbs timeout: Numeric? -- Maximum wait time in milliseconds
  # @rbs return: Puppeteer::ElementHandle? -- Matching element or nil
  def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil)
    main_frame.wait_for_selector(selector, visible: visible, hidden: hidden, timeout: timeout)
  end

  define_async_method :async_wait_for_selector

  # @rbs milliseconds: Numeric -- Time to wait in milliseconds
  # @rbs return: void -- No return value
  def wait_for_timeout(milliseconds)
    main_frame.wait_for_timeout(milliseconds)
  end

  # @rbs xpath: String -- XPath expression
  # @rbs visible: bool? -- Wait for element to be visible
  # @rbs hidden: bool? -- Wait for element to be hidden
  # @rbs timeout: Numeric? -- Maximum wait time in milliseconds
  # @rbs return: Puppeteer::ElementHandle? -- Matching element or nil
  def wait_for_xpath(xpath, visible: nil, hidden: nil, timeout: nil)
    main_frame.wait_for_xpath(xpath, visible: visible, hidden: hidden, timeout: timeout)
  end

  define_async_method :async_wait_for_xpath

  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs polling: String | Numeric | nil -- Polling strategy
  # @rbs timeout: Numeric? -- Maximum wait time in milliseconds
  # @rbs return: Puppeteer::JSHandle -- Handle to evaluation result
  def wait_for_function(page_function, args: [], polling: nil, timeout: nil)
    main_frame.wait_for_function(page_function, args: args, polling: polling, timeout: timeout)
  end

  define_async_method :async_wait_for_function
end
