# rbs_inline: enabled

require 'thread'

class Puppeteer::Browser
  include Puppeteer::DebugPrint
  include Puppeteer::EventCallbackable
  include Puppeteer::IfPresent
  using Puppeteer::DefineAsyncMethod

  # @rbs product: String? -- Browser product (chrome only)
  # @rbs connection: Puppeteer::Connection -- CDP connection
  # @rbs context_ids: Array[String] -- Browser context IDs
  # @rbs ignore_https_errors: bool -- Ignore HTTPS errors
  # @rbs default_viewport: Puppeteer::Viewport? -- Default viewport
  # @rbs process: Puppeteer::BrowserRunner::BrowserProcess? -- Browser process handle
  # @rbs close_callback: untyped -- Close callback
  # @rbs target_filter_callback: untyped -- Target filter callback
  # @rbs is_page_target_callback: untyped -- Page target predicate
  # @rbs return: Puppeteer::Browser -- Browser instance
  def self.create(product:,
                  connection:,
                  context_ids:,
                  ignore_https_errors:,
                  default_viewport:,
                  process:,
                  close_callback:,
                  target_filter_callback:,
                  is_page_target_callback:)
    browser = Puppeteer::Browser.new(
      product: product,
      connection: connection,
      context_ids: context_ids,
      ignore_https_errors: ignore_https_errors,
      default_viewport: default_viewport,
      process: process,
      close_callback: close_callback,
      target_filter_callback: target_filter_callback,
      is_page_target_callback: is_page_target_callback,
    )
    browser.send(:attach)
    browser
  end

  # @rbs product: String? -- Browser product (chrome only)
  # @rbs connection: Puppeteer::Connection -- CDP connection
  # @rbs context_ids: Array[String] -- Browser context IDs
  # @rbs ignore_https_errors: bool -- Ignore HTTPS errors
  # @rbs default_viewport: Puppeteer::Viewport? -- Default viewport
  # @rbs process: Puppeteer::BrowserRunner::BrowserProcess? -- Browser process handle
  # @rbs close_callback: untyped -- Close callback
  # @rbs target_filter_callback: untyped -- Target filter callback
  # @rbs is_page_target_callback: untyped -- Page target predicate
  # @rbs return: void -- No return value
  def initialize(product:,
                 connection:,
                 context_ids:,
                 ignore_https_errors:,
                 default_viewport:,
                 process:,
                 close_callback:,
                 target_filter_callback:,
                 is_page_target_callback:)
    @product = product ? product.to_s : 'chrome'
    if @product != 'chrome'
      raise ArgumentError.new("Unsupported product: #{@product}. Only 'chrome' is supported.")
    end
    @ignore_https_errors = ignore_https_errors
    @default_viewport = default_viewport
    @process = process
    @connection = connection
    @close_callback = close_callback
    @target_filter_callback = target_filter_callback || method(:default_target_filter_callback)
    @is_page_target_callback = is_page_target_callback || method(:default_is_page_target_callback)
    @default_context = Puppeteer::BrowserContext.new(@connection, self, nil)
    @contexts = {}

    context_ids.each do |context_id|
      @contexts[context_id] = Puppeteer::BrowserContext.new(@connection, self, context_id)
    end

    @target_manager = Puppeteer::ChromeTargetManager.new(
      connection: connection,
      target_factory: method(:create_target),
      target_filter_callback: @target_filter_callback,
    )
  end

  private def default_target_filter_callback(target_info)
    true
  end

  private def default_is_page_target_callback(target_info)
    ['page', 'background_page', 'webview'].include?(target_info.type)
  end

  attr_reader :is_page_target_callback

  # @rbs event_name: untyped -- event_name parameter
  # @rbs block: untyped -- block parameter
  # @rbs return: untyped -- Result
  def on(event_name, &block)
    unless BrowserEmittedEvents.values.include?(event_name.to_s)
      raise ArgumentError.new("Unknown event name: #{event_name}. Known events are #{BrowserEmittedEvents.values.to_a.join(", ")}")
    end

    super(event_name.to_s, &block)
  end

  # @rbs event_name: untyped -- event_name parameter
  # @rbs block: untyped -- block parameter
  # @rbs return: untyped -- Result
  def once(event_name, &block)
    unless BrowserEmittedEvents.values.include?(event_name.to_s)
      raise ArgumentError.new("Unknown event name: #{event_name}. Known events are #{BrowserEmittedEvents.values.to_a.join(", ")}")
    end

    super(event_name.to_s, &block)
  end

  private def attach
    @connection_event_listeners ||= []
    @connection_event_listeners << @connection.add_event_listener(ConnectionEmittedEvents::Disconnected) do
      emit_event(BrowserEmittedEvents::Disconnected)
    end
    @target_manager_event_listeners ||= []
    @target_manager.add_event_listener(
      TargetManagerEmittedEvents::TargetAvailable,
      &method(:handle_attached_to_target)
    )
    @target_manager.add_event_listener(
      TargetManagerEmittedEvents::TargetGone,
      &method(:handle_detached_from_target)
    )
    @target_manager.add_event_listener(
      TargetManagerEmittedEvents::TargetChanged,
      &method(:handle_target_changed)
    )
    @target_manager.add_event_listener(
      TargetManagerEmittedEvents::TargetDiscovered,
      &method(:handle_target_discovered)
    )
    @target_manager.init
  end

  private def detach
    @connection.remove_event_listener(*@connection_event_listeners)
    @target_manager.remove_event_listener(*@target_manager_event_listeners)
  end

  # @rbs return: untyped -- Result
  def process
    @process
  end

  private def target_manager
    @target_manager
  end

  # @rbs return: untyped -- Result
  def create_incognito_browser_context
    result = @connection.send_message('Target.createBrowserContext')
    browser_context_id = result['browserContextId']
    @contexts[browser_context_id] = Puppeteer::BrowserContext.new(@connection, self, browser_context_id)
  end

  # @rbs return: untyped -- Result
  def browser_contexts
    [@default_context].concat(@contexts.values)
  end

  # @rbs return: untyped -- Result
  def default_browser_context
    @default_context
  end

  # @rbs context_id: untyped -- context_id parameter
  # @rbs return: untyped -- Result
  def dispose_context(context_id)
    return unless context_id
    @connection.send_message('Target.disposeBrowserContext', browserContextId: context_id)
    @contexts.delete(context_id)
  end

  class MissingBrowserContextError < Puppeteer::Error ; end

  # @rbs target_info: untyped -- target_info parameter
  # @rbs session: untyped -- session parameter
  # @rbs return: untyped -- Result
  def create_target(target_info, session)
    browser_context_id = target_info.browser_context_id
    context =
      if browser_context_id && @contexts.has_key?(browser_context_id)
        @contexts[browser_context_id]
      else
        @default_context
      end

    unless context
      raise MissingBrowserContextError.new('Missing browser context')
    end

    Puppeteer::Target.new(
      target_info: target_info,
      session: session,
      browser_context: context,
      target_manager: @target_manager,
      session_factory: -> (auto_attach_emulated) { @connection.create_session(target_info, auto_attach_emulated: auto_attach_emulated) },
      ignore_https_errors: @ignore_https_errors,
      default_viewport: @default_viewport,
      is_page_target_callback: @is_page_target_callback,
    )
  end

  private def handle_attached_to_target(target)
    if target.initialized_promise.wait
      emit_event(BrowserEmittedEvents::TargetCreated, target)
      target.browser_context.emit_event(BrowserContextEmittedEvents::TargetCreated, target)
    end
  end

  private def handle_detached_from_target(target)
    target.ignore_initialize_callback_promise
    target.closed_callback
    if target.initialized_promise.wait
      emit_event(BrowserEmittedEvents::TargetDestroyed, target)
      target.browser_context.emit_event(BrowserContextEmittedEvents::TargetDestroyed, target)
    end
  end

  private def handle_target_changed(target, target_info)
    previous_url = target.url
    was_initialized = target.initialized?
    target.handle_target_info_changed(target_info)
    if was_initialized && previous_url != target.url
      emit_event(BrowserEmittedEvents::TargetChanged, target)
      target.browser_context.emit_event(BrowserContextEmittedEvents::TargetChanged, target)
    end
  end

  private def handle_target_discovered(target_info)
    emit_event('targetdiscovered', target_info)
  end

  # @rbs return: untyped -- Result
  def ws_endpoint
    @connection.url
  end

  # @rbs return: untyped -- Result
  def new_page
    @default_context.new_page
  end

  class MissingTargetError < Puppeteer::Error ; end
  class CreatePageError < Puppeteer::Error ; end

  # @rbs context_id: untyped -- context_id parameter
  # @rbs return: untyped -- Result
  def create_page_in_context(context_id)
    create_target_params = {
      url: 'about:blank',
      browserContextId: context_id,
    }.compact
    result = @connection.send_message('Target.createTarget', **create_target_params)
    target_id = result['targetId']
    target = @target_manager.available_targets[target_id]
    unless target
      raise MissingTargetError.new("Missing target for page (id = #{target_id})")
    end
    unless target.initialized_promise.wait
      raise CreatePageError.new("Failed to create target for page (id = #{target_id})")
    end
    page = target.page
    unless page
      raise CreatePageError.new("Failed to create a page for context (id = #{context_id})")
    end
    page
  end

  # All active targets inside the Browser. In case of multiple browser contexts, returns
  # an array with all the targets in all browser contexts.
  # @rbs return: untyped -- Result
  def targets
    @target_manager.available_targets.values.select { |target| target.initialized? }
  end


  # The target associated with the browser.
  # @rbs return: untyped -- Result
  def target
    targets.find { |target| target.type == 'browser' } or raise 'Browser target is not found'
  end

  # used only in Target#opener
  private def find_target_by_id(target_id)
    @target_manager.available_targets[target_id]
  end

  # @rbs predicate: untyped -- predicate parameter
  # @rbs timeout: untyped -- timeout parameter
  # @rbs return: untyped -- Result
  def wait_for_target(predicate:, timeout: nil)
    timeout_helper = Puppeteer::TimeoutHelper.new('target', timeout_ms: timeout, default_timeout_ms: 30000)
    existing_target = targets.find { |target| predicate.call(target) }
    return existing_target if existing_target

    event_listening_ids = []
    target_promise = Async::Promise.new
    event_listening_ids << add_event_listener(BrowserEmittedEvents::TargetCreated) do |target|
      if predicate.call(target)
        target_promise.resolve(target)
      end
    end
    event_listening_ids << add_event_listener(BrowserEmittedEvents::TargetChanged) do |target|
      if predicate.call(target)
        target_promise.resolve(target)
      end
    end

    begin
      timeout_helper.with_timeout do
        target_promise.wait
      end
    ensure
      remove_event_listener(*event_listening_ids)
    end
  end

  # @!method async_wait_for_target(predicate:, timeout: nil)
  #
  define_async_method :async_wait_for_target

  # @rbs return: untyped -- Result
  def pages
    browser_contexts.flat_map(&:pages)
  end

  # @rbs return: untyped -- Result
  def version
    Version.fetch(@connection).product
  end

  # @rbs return: untyped -- Result
  def user_agent
    Version.fetch(@connection).user_agent
  end

  # @rbs return: untyped -- Result
  def close
    @close_callback.call
    disconnect
  end

  # @rbs return: untyped -- Result
  def disconnect
    @target_manager.dispose
    @connection.dispose
  end

  # @rbs return: untyped -- Result
  def connected?
    !@connection.closed?
  end

  class Version
    # @rbs connection: untyped -- connection parameter
    # @rbs return: untyped -- Result
    def self.fetch(connection)
      new(connection.send_message('Browser.getVersion'))
    end

    # @rbs hash: untyped -- hash parameter
    # @rbs return: void -- No return value
    def initialize(hash)
      @protocol_version = hash['protocolVersion']
      @product = hash['product']
      @revision = hash['revision']
      @user_agent = hash['userAgent']
      @js_version = hash['jsVersion']
    end

    attr_reader :protocol_version, :product, :revision, :user_agent, :js_version
  end
end
