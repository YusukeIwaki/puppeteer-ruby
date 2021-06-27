require 'base64'
require 'json'
require "stringio"

require_relative './page/pdf_options'
require_relative './page/screenshot_options'
require_relative './page/screenshot_task_queue'

class Puppeteer::Page
  include Puppeteer::EventCallbackable
  include Puppeteer::IfPresent
  using Puppeteer::DefineAsyncMethod

  # @param {!Puppeteer.CDPSession} client
  # @param {!Puppeteer.Target} target
  # @param {boolean} ignoreHTTPSErrors
  # @param {?Puppeteer.Viewport} defaultViewport
  # @return {!Promise<!Page>}
  def self.create(client, target, ignore_https_errors, default_viewport)
    page = Puppeteer::Page.new(client, target, ignore_https_errors)
    page.init
    if default_viewport
      page.viewport = default_viewport
    end
    page
  end

  # @param {!Puppeteer.CDPSession} client
  # @param {!Puppeteer.Target} target
  # @param {boolean} ignoreHTTPSErrors
  def initialize(client, target, ignore_https_errors)
    @closed = false
    @client = client
    @target = target
    @keyboard = Puppeteer::Keyboard.new(client)
    @mouse = Puppeteer::Mouse.new(client, @keyboard)
    @timeout_settings = Puppeteer::TimeoutSettings.new
    @touchscreen = Puppeteer::TouchScreen.new(client, @keyboard)
    # @accessibility = Accessibility.new(client)
    @frame_manager = Puppeteer::FrameManager.new(client, self, ignore_https_errors, @timeout_settings)
    @emulation_manager = Puppeteer::EmulationManager.new(client)
    @tracing = Puppeteer::Tracing.new(client)
    @page_bindings = {}
    @coverage = Puppeteer::Coverage.new(client)
    @javascript_enabled = true
    @screenshot_task_queue = ScreenshotTaskQueue.new

    @workers = {}
    @client.on_event('Target.attachedToTarget') do |event|
      if event['targetInfo']['type'] != 'worker'
        # If we don't detach from service workers, they will never die.
        @client.async_send_message('Target.detachFromTarget', sessionId: event['sessionId'])
        next
      end

      session = Puppeteer::Connection.from_session(@client).session(event['sessionId']) # rubocop:disable Lint/UselessAssignment
      #   const worker = new Worker(session, event.targetInfo.url, this._addConsoleMessage.bind(this), this._handleException.bind(this));
      #   this._workers.set(event.sessionId, worker);
      #   this.emit(PageEmittedEvents::WorkerCreated, worker);
    end
    @client.on_event('Target.detachedFromTarget') do |event|
      session_id = event['sessionId']
      worker = @workers[session_id]
      next unless worker

      emit_event(PageEmittedEvents::WorkerDestroyed, worker)
      @workers.delete(session_id)
    end

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
      emit_event(PageEmittedEvents::Request, event)
    end
    network_manager.on_event(NetworkManagerEmittedEvents::Response) do |event|
      emit_event(PageEmittedEvents::Response, event)
    end
    network_manager.on_event(NetworkManagerEmittedEvents::RequestFailed) do |event|
      emit_event(PageEmittedEvents::RequestFailed, event)
    end
    network_manager.on_event(NetworkManagerEmittedEvents::RequestFinished) do |event|
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
    @client.on('Runtime.consoleAPICalled') do |event|
      handle_console_api(event)
    end
    # client.on('Runtime.bindingCalled', event => this._onBindingCalled(event));
    @client.on_event('Page.javascriptDialogOpening') do |event|
      handle_dialog_opening(event)
    end
    @client.on_event('Runtime.exceptionThrown') do |exception|
      handle_exception(exception['exceptionDetails'])
    end
    @client.on_event('Inspector.targetCrashed') do |event|
      handle_target_crashed
    end
    # client.on('Performance.metrics', event => this._emitMetrics(event));
    @client.on_event('Log.entryAdded') do |event|
      handle_log_entry_added(event)
    end
    @client.on_event('Page.fileChooserOpened') do |event|
      handle_file_chooser(event)
    end
    @target.is_closed_promise.then do
      emit_event(PageEmittedEvents::Close)
      @closed = true
    end
  end

  def init
    await_all(
      @frame_manager.async_init,
      @client.async_send_message('Target.setAutoAttach', autoAttach: true, waitForDebuggerOnStart: false, flatten: true),
      @client.async_send_message('Performance.enable'),
      @client.async_send_message('Log.enable'),
    )
  end

  # @param event_name [Symbol]
  def on(event_name, &block)
    unless PageEmittedEvents.values.include?(event_name.to_s)
      raise ArgumentError.new("Unknown event name: #{event_name}. Known events are #{PageEmittedEvents.values.to_a.join(", ")}")
    end

    super(event_name.to_s, &block)
  end

  # @param event_name [Symbol]
  def once(event_name, &block)
    unless PageEmittedEvents.values.include?(event_name.to_s)
      raise ArgumentError.new("Unknown event name: #{event_name}. Known events are #{PageEmittedEvents.values.to_a.join(", ")}")
    end

    super(event_name.to_s, &block)
  end

  def handle_file_chooser(event)
    return if @file_chooser_interceptors.empty?

    frame = @frame_manager.frame(event['frameId'])
    context = frame.execution_context
    element = context.adopt_backend_node_id(event['backendNodeId'])
    interceptors = @file_chooser_interceptors.to_a
    @file_chooser_interceptors.clear
    file_chooser = Puppeteer::FileChooser.new(element, event)
    interceptors.each do |promise|
      promise.fulfill(file_chooser)
    end
  end

  class FileChooserTimeoutError < StandardError
    def initialize(timeout:)
      super("waiting for filechooser failed: timeout #{timeout}ms exceeded")
    end
  end

  # @param timeout [Integer]
  # @return [Puppeteer::FileChooser]
  def wait_for_file_chooser(timeout: nil)
    if @file_chooser_interceptors.empty?
      @client.send_message('Page.setInterceptFileChooserDialog', enabled: true)
    end

    option_timeout = timeout || @timeout_settings.timeout
    promise = resolvable_future
    @file_chooser_interceptors << promise

    begin
      Timeout.timeout(option_timeout / 1000.0) do
        promise.value!
      end
    rescue Timeout::Error
      raise FileChooserTimeoutError.new(timeout: option_timeout)
    ensure
      @file_chooser_interceptors.delete(promise)
    end
  end

  define_async_method :async_wait_for_file_chooser

  # @param [Puppeteer::Geolocation]
  def geolocation=(geolocation)
    @client.send_message('Emulation.setGeolocationOverride', geolocation.to_h)
  end

  attr_reader :javascript_enabled, :target
  alias_method :javascript_enabled?, :javascript_enabled

  def browser
    @target.browser
  end

  def browser_context
    @target.browser_context
  end

  class TargetCrashedError < StandardError; end

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

  def main_frame
    @frame_manager.main_frame
  end

  attr_reader :touch_screen, :coverage, :tracing, :accessibility

  def keyboard(&block)
    @keyboard.instance_eval(&block) unless block.nil?

    @keyboard
  end

  def frames
    @frame_manager.frames
  end

  def workers
    @workers.values
  end

  # @param value [Bool]
  def request_interception=(value)
    @frame_manager.network_manager.request_interception = value
  end

  def offline_mode=(enabled)
    @frame_manager.network_manager.offline_mode = enabled
  end

  # @param {number} timeout
  def default_navigation_timeout=(timeout)
    @timeout_settings.default_navigation_timeout = timeout
  end

  # @param {number} timeout
  def default_timeout=(timeout)
    @timeout_settings.default_timeout = timeout
  end

  # `$()` in JavaScript.
  # @param {string} selector
  # @return {!Promise<?Puppeteer.ElementHandle>}
  def query_selector(selector)
    main_frame.query_selector(selector)
  end
  alias_method :S, :query_selector

  define_async_method :async_query_selector

  # `$$()` in JavaScript.
  # @param {string} selector
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def query_selector_all(selector)
    main_frame.query_selector_all(selector)
  end
  alias_method :SS, :query_selector_all

  define_async_method :async_query_selector_all

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<!Puppeteer.JSHandle>}
  def evaluate_handle(page_function, *args)
    context = main_frame.execution_context
    context.evaluate_handle(page_function, *args)
  end

  define_async_method :async_evaluate_handle

  # @param {!Puppeteer.JSHandle} prototypeHandle
  # @return {!Promise<!Puppeteer.JSHandle>}
  def query_objects(prototype_handle)
    context = main_frame.execution_context
    context.query_objects(prototype_handle)
  end

  # `$eval()` in JavaScript.
  # @param selector [String]
  # @param page_function [String]
  # @return [Object]
  def eval_on_selector(selector, page_function, *args)
    main_frame.eval_on_selector(selector, page_function, *args)
  end
  alias_method :Seval, :eval_on_selector

  define_async_method :async_eval_on_selector

  # `$$eval()` in JavaScript.
  # @param selector [String]
  # @param page_function [String]
  # @return [Object]
  def eval_on_selector_all(selector, page_function, *args)
    main_frame.eval_on_selector_all(selector, page_function, *args)
  end
  alias_method :SSeval, :eval_on_selector_all

  define_async_method :async_eval_on_selector_all

  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} expression
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def Sx(expression)
    main_frame.Sx(expression)
  end

  define_async_method :async_Sx

  # @return [Array<Hash>]
  def cookies(*urls)
    @client.send_message('Network.getCookies', urls: (urls.empty? ? [url] : urls))['cookies']
  end

  def delete_cookie(*cookies)
    page_url = url
    starts_with_http = page_url.start_with?("http")
    cookies.each do |cookie|
      item = (starts_with_http ? { url: page_url } : {}).merge(cookie)
      @client.send_message("Network.deleteCookies", item)
    end
  end

  def set_cookie(*cookies)
    page_url = url
    starts_with_http = page_url.start_with?("http")
    items = cookies.map do |cookie|
      (starts_with_http ? { url: page_url } : {}).merge(cookie).tap do |item|
        raise ArgumentError.new("Blank page can not have cookie \"#{item[:name]}\"") if item[:url] == "about:blank"
        raise ArgumetnError.new("Data URL page can not have cookie \"#{item[:name]}\"") if item[:url]&.start_with?("data:")
      end
    end
    delete_cookie(*items)
    unless items.empty?
      @client.send_message("Network.setCookies", cookies: items)
    end
  end

  # @param url [String?]
  # @param path [String?]
  # @param content [String?]
  # @param type [String?]
  def add_script_tag(url: nil, path: nil, content: nil, type: nil)
    main_frame.add_script_tag(url: url, path: path, content: content, type: type)
  end

  # @param url [String?]
  # @param path [String?]
  # @param content [String?]
  def add_style_tag(url: nil, path: nil, content: nil)
    main_frame.add_style_tag(url: url, path: path, content: content)
  end

  # /**
  #  * @param {string} name
  #  * @param {Function} puppeteerFunction
  #  */
  # async exposeFunction(name, puppeteerFunction) {
  #   if (this._pageBindings.has(name))
  #     throw new Error(`Failed to add page binding with name ${name}: window['${name}'] already exists!`);
  #   this._pageBindings.set(name, puppeteerFunction);

  #   const expression = helper.evaluationString(addPageBinding, name);
  #   await this._client.send('Runtime.addBinding', {name: name});
  #   await this._client.send('Page.addScriptToEvaluateOnNewDocument', {source: expression});
  #   await Promise.all(this.frames().map(frame => frame.evaluate(expression).catch(debugError)));

  #   function addPageBinding(bindingName) {
  #     const binding = window[bindingName];
  #     window[bindingName] = (...args) => {
  #       const me = window[bindingName];
  #       let callbacks = me['callbacks'];
  #       if (!callbacks) {
  #         callbacks = new Map();
  #         me['callbacks'] = callbacks;
  #       }
  #       const seq = (me['lastSeq'] || 0) + 1;
  #       me['lastSeq'] = seq;
  #       const promise = new Promise((resolve, reject) => callbacks.set(seq, {resolve, reject}));
  #       binding(JSON.stringify({name: bindingName, seq, args}));
  #       return promise;
  #     };
  #   }
  # }

  # @param username [String?]
  # @param password [String?]
  def authenticate(username: nil, password: nil)
    @frame_manager.network_manager.authenticate(username: username, password: password)
  end

  # @param headers [Hash]
  def extra_http_headers=(headers)
    @frame_manager.network_manager.extra_http_headers = headers
  end

  # @param user_agent [String]
  def user_agent=(user_agent)
    @frame_manager.network_manager.user_agent = user_agent
  end

  # /**
  #  * @return {!Promise<!Metrics>}
  #  */
  # async metrics() {
  #   const response = await this._client.send('Performance.getMetrics');
  #   return this._buildMetricsObject(response.metrics);
  # }

  # /**
  #  * @param {!Protocol.Performance.metricsPayload} event
  #  */
  # _emitMetrics(event) {
  #   this.emit(PageEmittedEvents::Metrics, {
  #     title: event.title,
  #     metrics: this._buildMetricsObject(event.metrics)
  #   });
  # }

  # /**
  #  * @param {?Array<!Protocol.Performance.Metric>} metrics
  #  * @return {!Metrics}
  #  */
  # _buildMetricsObject(metrics) {
  #   const result = {};
  #   for (const metric of metrics || []) {
  #     if (supportedMetrics.has(metric.name))
  #       result[metric.name] = metric.value;
  #   }
  #   return result;
  # }

  class PageError < StandardError ; end

  private def handle_exception(exception_details)
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

    context = @frame_manager.execution_context_by_id(event['executionContextId'])
    values = event['args'].map do |arg|
      remote_object = Puppeteer::RemoteObject.new(arg)
      Puppeteer::JSHandle.create(context: context, remote_object: remote_object)
    end
    add_console_message(event['type'], values, event['stackTrace'])
  end

  # /**
  #  * @param {!Protocol.Runtime.bindingCalledPayload} event
  #  */
  # async _onBindingCalled(event) {
  #   const {name, seq, args} = JSON.parse(event.payload);
  #   let expression = null;
  #   try {
  #     const result = await this._pageBindings.get(name)(...args);
  #     expression = helper.evaluationString(deliverResult, name, seq, result);
  #   } catch (error) {
  #     if (error instanceof Error)
  #       expression = helper.evaluationString(deliverError, name, seq, error.message, error.stack);
  #     else
  #       expression = helper.evaluationString(deliverErrorValue, name, seq, error);
  #   }
  #   this._client.send('Runtime.evaluate', { expression, contextId: event.executionContextId }).catch(debugError);

  #   /**
  #    * @param {string} name
  #    * @param {number} seq
  #    * @param {*} result
  #    */
  #   function deliverResult(name, seq, result) {
  #     window[name]['callbacks'].get(seq).resolve(result);
  #     window[name]['callbacks'].delete(seq);
  #   }

  #   /**
  #    * @param {string} name
  #    * @param {number} seq
  #    * @param {string} message
  #    * @param {string} stack
  #    */
  #   function deliverError(name, seq, message, stack) {
  #     const error = new Error(message);
  #     error.stack = stack;
  #     window[name]['callbacks'].get(seq).reject(error);
  #     window[name]['callbacks'].delete(seq);
  #   }

  #   /**
  #    * @param {string} name
  #    * @param {number} seq
  #    * @param {*} value
  #    */
  #   function deliverErrorValue(name, seq, value) {
  #     window[name]['callbacks'].get(seq).reject(value);
  #     window[name]['callbacks'].delete(seq);
  #   }
  # }

  private def add_console_message(type, args, stack_trace)
    text_tokens = args.map { |arg| arg.remote_object.value }

    call_frame = stack_trace['callFrames']&.first
    location =
      if call_frame
        Puppeteer::ConsoleMessage::Location.new(
          url: call_frame['url'],
          line_number: call_frame['lineNumber'],
          column_number: call_frame['columnNumber'],
        )
      else
        nil
      end
    console_message = Puppeteer::ConsoleMessage.new(type, text_tokens.join(' '), args, location)
    emit_event(PageEmittedEvents::Console, console_message)
  end

  private def handle_dialog_opening(event)
    dialog_type = event['type']
    unless %w(alert confirm prompt beforeunload).include?(dialog_type)
      raise ArgumentError.new("Unknown javascript dialog type: #{dialog_type}")
    end
    dialog = Puppeteer::Dialog.new(@client,
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

  # @return [String]
  def url
    main_frame.url
  end

  # @return [String]
  def content
    main_frame.content
  end

  # @param html [String]
  # @param timeout [Integer]
  # @param wait_until [String|Array<String>]
  def set_content(html, timeout: nil, wait_until: nil)
    main_frame.set_content(html, timeout: timeout, wait_until: wait_until)
  end

  # @param html [String]
  def content=(html)
    main_frame.set_content(html)
  end

  # @param url [String]
  # @param rederer [String]
  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  def goto(url, referer: nil, timeout: nil, wait_until: nil)
    main_frame.goto(url, referer: referer, timeout: timeout, wait_until: wait_until)
  end

  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  # @return [Puppeteer::Response]
  def reload(timeout: nil, wait_until: nil)
    await_all(
      async_wait_for_navigation(timeout: timeout, wait_until: wait_until),
      @client.async_send_message('Page.reload'),
    ).first
  end

  def wait_for_navigation(timeout: nil, wait_until: nil)
    main_frame.send(:wait_for_navigation, timeout: timeout, wait_until: wait_until)
  end

  # @!method async_wait_for_navigation(timeout: nil, wait_until: nil)
  #
  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  define_async_method :async_wait_for_navigation

  private def wait_for_network_manager_event(event_name, predicate:, timeout:)
    option_timeout = timeout || @timeout_settings.timeout

    @wait_for_network_manager_event_listener_ids ||= {}
    if_present(@wait_for_network_manager_event_listener_ids[event_name]) do |listener_id|
      @frame_manager.network_manager.remove_event_listener(listener_id)
    end

    promise = resolvable_future

    @wait_for_network_manager_event_listener_ids[event_name] =
      @frame_manager.network_manager.add_event_listener(event_name) do |event_target|
        if predicate.call(event_target)
          promise.fulfill(nil)
        end
      end

    begin
      Timeout.timeout(option_timeout / 1000.0) do
        await_any(promise, session_close_promise)
      end
    rescue Timeout::Error
      raise Puppeteer::TimeoutError.new("waiting for #{event_name} failed: timeout #{timeout}ms exceeded")
    ensure
      @frame_manager.network_manager.remove_event_listener(@wait_for_network_manager_event_listener_ids[event_name])
    end
  end

  private def session_close_promise
    @disconnect_promise ||= resolvable_future do |future|
      @client.observe_first(CDPSessionEmittedEvents::Disconnected) do
        future.reject(Puppeteer::CDPSession::Error.new('Target Closed'))
      end
    end
  end

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
        -> (request) { predicate.call(request) }
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
  # @param url [String]
  # @param predicate [Proc(Puppeteer::Request -> Boolean)]
  define_async_method :async_wait_for_request

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
        -> (response) { predicate.call(response) }
      end

    wait_for_network_manager_event(NetworkManagerEmittedEvents::Response,
      predicate: response_predicate,
      timeout: timeout,
    )
  end

  # @!method async_wait_for_response(url: nil, predicate: nil, timeout: nil)
  #
  # @param url [String]
  # @param predicate [Proc(Puppeteer::Request -> Boolean)]
  define_async_method :async_wait_for_response

  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  def go_back(timeout: nil, wait_until: nil)
    go(-1, timeout: timeout, wait_until: wait_until)
  end

  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  def go_forward(timeout: nil, wait_until: nil)
    go(+1, timeout: timeout, wait_until: wait_until)
  end

  private def go(delta, timeout: nil, wait_until: nil)
    history = @client.send_message('Page.getNavigationHistory')
    entries = history['entries']
    index = history['currentIndex'] + delta
    if_present(entries[index]) do |entry|
      await_all(
        async_wait_for_navigation(timeout: timeout, wait_until: wait_until),
        @client.async_send_message('Page.navigateToHistoryEntry', entryId: entry['id']),
      )
    end
  end

  # Brings page to front (activates tab).
  def bring_to_front
    @client.send_message('Page.bringToFront')
  end

  # @param device [Device]
  def emulate(device)
    self.viewport = device.viewport
    self.user_agent = device.user_agent
  end

  # @param {boolean} enabled
  def javascript_enabled=(enabled)
    return if @javascript_enabled == enabled
    @javascript_enabled = enabled
    @client.send_message('Emulation.setScriptExecutionDisabled', value: !enabled)
  end

  # @param enabled [Boolean]
  def bypass_csp=(enabled)
    @client.send_message('Page.setBypassCSP', enabled: enabled)
  end

  # @param media_type [String|Symbol|nil] either of (media, print, nil)
  def emulate_media_type(media_type)
    media_type_str = media_type.to_s
    unless ['screen', 'print', ''].include?(media_type_str)
      raise ArgumentError.new("Unsupported media type: #{media_type}")
    end
    @client.send_message('Emulation.setEmulatedMedia', media: media_type_str)
  end

  # @param features [Array]
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

  # @param timezone_id [String?]
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

  def emulate_vision_deficiency(vision_deficiency_type)
    value = vision_deficiency_type || 'none'
    unless VISION_DEFICIENCY_TYPES.include?(value)
      raise ArgumentError.new("Unsupported vision deficiency: #{vision_deficiency_type}")
    end
    @client.send_message('Emulation.setEmulatedVisionDeficiency', type: value)
  end

  # @param is_user_active [Boolean]
  # @param is_screen_unlocked [Boolean]
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

  # @param viewport [Viewport]
  def viewport=(viewport)
    needs_reload = @emulation_manager.emulate_viewport(viewport)
    @viewport = viewport
    reload if needs_reload
  end

  attr_reader :viewport

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<*>}
  def evaluate(page_function, *args)
    main_frame.evaluate(page_function, *args)
  end

  define_async_method :async_evaluate

  class JavaScriptFunction
    def initialize(expression, args)
      @expression = expression
      @args = args
    end

    def source
      "(#{@expression})(#{arguments})"
    end

    private def arguments
      @args.map { |arg| arg.nil? ? nil : JSON.dump(arg) }.join(", ")
    end
  end

  class JavaScriptExpression
    def initialize(expression)
      @expression = expression
    end

    def source
      @expression
    end
  end

  def evaluate_on_new_document(page_function, *args)
    source =
      if ['=>', 'async', 'function'].any? { |keyword| page_function.include?(keyword) }
        JavaScriptFunction.new(page_function, args).source
      else
        JavaScriptExpression.new(page_function).source
      end

    @client.send_message('Page.addScriptToEvaluateOnNewDocument', source: source)
  end

  # @param {boolean} enabled
  def cache_enabled=(enabled)
    @frame_manager.network_manager.cache_enabled = enabled
  end

  # @return [String]
  def title
    main_frame.title
  end

  # @param type [String] "png"|"jpeg"
  # @param path [String]
  # @param full_page [Boolean]
  # @param clip [Hash]
  # @param quality [Integer]
  # @param omit_background [Boolean]
  # @param encoding [String]
  def screenshot(type: nil, path: nil, full_page: nil, clip: nil, quality: nil, omit_background: nil, encoding: nil)
    options = {
      type: type,
      path: path,
      full_page: full_page,
      clip: clip,
      quality:  quality,
      omit_background: omit_background,
      encoding: encoding,
    }.compact
    screenshot_options = ScreenshotOptions.new(options)

    @screenshot_task_queue.post_task do
      screenshot_task(screenshot_options.type, screenshot_options)
    end
  end

  # @param {"png"|"jpeg"} format
  # @param {!ScreenshotOptions=} options
  # @return {!Promise<!Buffer|!String>}
  private def screenshot_task(format, screenshot_options)
    @client.send_message('Target.activateTarget', targetId: @target.target_id)

    clip = if_present(screenshot_options.clip) do |rect|
      x = rect[:x].round
      y = rect[:y].round
      { x: x, y: y, width: rect[:width] + rect[:x] - x, height: rect[:height] + rect[:y] - y, scale: 1 }
    end

    if screenshot_options.full_page?
      metrics = @client.send_message('Page.getLayoutMetrics')
      width = metrics['contentSize']['width'].ceil
      height = metrics['contentSize']['height'].ceil

      # Overwrite clip for full page at all times.
      clip = { x: 0, y: 0, width: width, height: height, scale: 1 }

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

    should_set_default_background = screenshot_options.omit_background? && format == 'png'
    set_transparent_background_color if should_set_default_background
    screenshot_params = {
      format: format,
      quality: screenshot_options.quality,
      clip: clip,
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

  class PrintToPdfIsNotImplementedError < StandardError
    def initialize
      super('pdf() is only available in headless mode. See https://github.com/puppeteer/puppeteer/issues/1829')
    end
  end

  # @return [Enumerable<String>]
  def create_pdf_stream(options = {})
    pdf_options = PDFOptions.new(options)
    omit_background = options[:omit_background]
    set_transparent_background_color if omit_background
    result = @client.send_message('Page.printToPDF', pdf_options.page_print_args)
    reset_default_background_color if omit_background

    Puppeteer::ProtocolStreamReader.new(
      client: @client,
      handle: result['stream'],
    ).read_as_chunks
  end

  # @return [String]
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

  # @param run_before_unload [Boolean]
  def close(run_before_unload: false)
    unless @client.connection
      raise 'Protocol error: Connection closed. Most likely the page has been closed.'
    end

    if run_before_unload
      @client.send_message('Page.close')
    else
      @client.connection.send_message('Target.closeTarget', targetId: @target.target_id)
      await @target.is_closed_promise

      # @closed sometimes remains false, so wait for @closed = true with 100ms timeout.
      25.times do
        break if @closed
        sleep 0.004
      end
    end
  end

  # @return [boolean]
  def closed?
    @closed
  end

  attr_reader :mouse

  # @param selector [String]
  # @param delay [Number]
  # @param button [String] "left"|"right"|"middle"
  # @param click_count [Number]
  def click(selector, delay: nil, button: nil, click_count: nil)
    main_frame.click(selector, delay: delay, button: button, click_count: click_count)
  end

  define_async_method :async_click

  # @param {string} selector
  def focus(selector)
    main_frame.focus(selector)
  end

  define_async_method :async_focus

  # @param {string} selector
  def hover(selector)
    main_frame.hover(selector)
  end

  # @param {string} selector
  # @param {!Array<string>} values
  # @return {!Promise<!Array<string>>}
  def select(selector, *values)
    main_frame.select(selector, *values)
  end

  define_async_method :async_select

  # @param selector [String]
  def tap(selector: nil, &block)
    # resolves double meaning of tap.
    if selector.nil? && block
      # Original usage of Object#tap.
      #
      # browser.new_page.tap do |page|
      #   ...
      # end
      super(&block)
    else
      # Puppeteer's Page#tap.
      main_frame.tap(selector)
    end
  end

  define_async_method :async_tap

  # @param selector [String]
  # @param text [String]
  # @param delay [Number]
  def type_text(selector, text, delay: nil)
    main_frame.type_text(selector, text, delay: delay)
  end

  define_async_method :async_type_text

  # @param selector [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil)
    main_frame.wait_for_selector(selector, visible: visible, hidden: hidden, timeout: timeout)
  end

  define_async_method :async_wait_for_selector

  # @param milliseconds [Integer] the number of milliseconds to wait.
  def wait_for_timeout(milliseconds)
    main_frame.wait_for_timeout(milliseconds)
  end

  # @param xpath [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  def wait_for_xpath(xpath, visible: nil, hidden: nil, timeout: nil)
    main_frame.wait_for_xpath(xpath, visible: visible, hidden: hidden, timeout: timeout)
  end

  define_async_method :async_wait_for_xpath

  # @param page_function [String]
  # @param args [Integer|Array]
  # @param polling [String]
  # @param timeout [Integer]
  # @return [Puppeteer::JSHandle]
  def wait_for_function(page_function, args: [], polling: nil, timeout: nil)
    main_frame.wait_for_function(page_function, args: args, polling: polling, timeout: timeout)
  end

  define_async_method :async_wait_for_function
end
