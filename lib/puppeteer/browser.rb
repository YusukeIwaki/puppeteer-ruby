require 'thread'
require 'timeout'

class Puppeteer::Browser
  include Puppeteer::DebugPrint
  include Puppeteer::EventCallbackable
  include Puppeteer::IfPresent
  using Puppeteer::DefineAsyncMethod

  # @param {!Puppeteer.Connection} connection
  # @param {!Array<string>} contextIds
  # @param {boolean} ignoreHTTPSErrors
  # @param {?Puppeteer.Viewport} defaultViewport
  # @param process [Puppeteer::BrowserRunner::BrowserProcess|NilClass]
  # @param {function()=} closeCallback
  def self.create(connection:, context_ids:, ignore_https_errors:, default_viewport:, process:, close_callback:)
    browser = Puppeteer::Browser.new(
      connection: connection,
      context_ids: context_ids,
      ignore_https_errors: ignore_https_errors,
      default_viewport: default_viewport,
      process: process,
      close_callback: close_callback,
    )
    connection.send_message('Target.setDiscoverTargets', discover: true)
    browser
  end

  # @param {!Puppeteer.Connection} connection
  # @param {!Array<string>} contextIds
  # @param {boolean} ignoreHTTPSErrors
  # @param {?Puppeteer.Viewport} defaultViewport
  # @param {?Puppeteer.ChildProcess} process
  # @param {(function():Promise)=} closeCallback
  def initialize(connection:, context_ids:, ignore_https_errors:, default_viewport:, process:, close_callback:)
    @ignore_https_errors = ignore_https_errors
    @default_viewport = default_viewport
    @process = process
    # @screenshot_task_queue = TaskQueue.new
    @connection = connection
    @close_callback = close_callback

    @default_context = Puppeteer::BrowserContext.new(@connection, self, nil)
    @contexts = {}
    context_ids.each do |context_id|
      @contexts[context_id] = Puppeteer::BrowserContext.new(@connection, self. context_id)
    end
    @targets = {}
    @connection.on_event 'Events.Connection.Disconnected' do
      emit_event 'Events.Browser.Disconnected'
    end
    @connection.on_event 'Target.targetCreated', &method(:handle_target_created)
    @connection.on_event 'Target.targetDestroyed', &method(:handle_target_destroyed)
    @connection.on_event 'Target.targetInfoChanged', &method(:handle_target_info_changed)
  end

  EVENT_MAPPINGS = {
    disconnected: 'Events.Browser.Disconnected',
    targetcreated: 'Events.Browser.TargetCreated',
    targetchanged: 'Events.Browser.TargetChanged',
    targetdestroyed: 'Events.Browser.TargetDestroyed',
  }

  # @param event_name [Symbol] either of :disconnected, :targetcreated, :targetchanged, :targetdestroyed
  def on(event_name, &block)
    unless EVENT_MAPPINGS.has_key?(event_name.to_sym)
      raise ArgumentError.new("Unknown event name: #{event_name}. Known events are #{EVENT_MAPPINGS.keys.join(", ")}")
    end

    add_event_listener(EVENT_MAPPINGS[event_name.to_sym], &block)
  end

  # @return [Puppeteer::BrowserRunner::BrowserProcess]
  def process
    @process
  end

  # @return [Puppeteer::BrowserContext]
  def create_incognito_browser_context
    result = @connection.send_message('Target.createBrowserContext')
    browser_context_id = result['browserContextId']
    @contexts[browser_context_id] = Puppeteer::BrowserContext.new(@connection, self, browser_context_id)
  end

  def browser_contexts
    [@default_context].concat(@contexts.values)
  end

  # @return [Puppeteer::BrowserContext]
  def default_browser_context
    @default_context
  end

  # @param context_id [String]
  def dispose_context(context_id)
    @connection.send_message('Target.disposeBrowserContext', browserContextId: context_id)
    @contexts.remove(context_id)
  end

  class TargetAlreadyExistError < StandardError
    def initialize
      super('Target should not exist before targetCreated')
    end
  end

  # @param {!Protocol.Target.targetCreatedPayload} event
  def handle_target_created(event)
    target_info = Puppeteer::Target::TargetInfo.new(event['targetInfo'])
    browser_context_id = target_info.browser_context_id
    context =
      if browser_context_id && @contexts.has_key?(browser_context_id)
        @contexts[browser_context_id]
      else
        @default_context
      end

    if @targets[target_info.target_id]
      raise TargetAlreadyExistError.new
    end
    target = Puppeteer::Target.new(
      target_info: target_info,
      browser_context: context,
      session_factory: -> { @connection.create_session(target_info) },
      ignore_https_errors: @ignore_https_errors,
      default_viewport: @default_viewport,
      screenshot_task_queue: @screenshot_task_queue,
    )
    #   assert(!this._targets.has(event.targetInfo.targetId), 'Target should not exist before targetCreated');
    @targets[target_info.target_id] = target
    if await target.initialized_promise
      emit_event 'Events.Browser.TargetCreated', target
      context.emit_event 'Events.BrowserContext.TargetCreated', target
    end
  end

  # @param {{targetId: string}} event
  def handle_target_destroyed(event)
    target_id = event['targetId']
    target = @targets[target_id]
    target.ignore_initialize_callback_promise
    @targets.delete(target_id)
    target.closed_callback
    if await target.initialized_promise
      emit_event 'Events.Browser.TargetDestroyed', target
      target.browser_context.emit_event 'Events.BrowserContext.TargetDestroyed', target
    end
  end

  class TargetNotExistError < StandardError
    def initialize
      super('target should exist before targetInfoChanged')
    end
  end

  # @param {!Protocol.Target.targetInfoChangedPayload} event
  def handle_target_info_changed(event)
    target_info = Puppeteer::Target::TargetInfo.new(event['targetInfo'])
    target = @targets[target_info.target_id] or raise TargetNotExistError.new
    previous_url = target.url
    was_initialized = target.initialized?
    target.handle_target_info_changed(target_info)
    if was_initialized && previous_url != target.url
      emit_event 'Events.Browser.TargetChanged', target
      target.browser_context.emit_event 'Events.BrowserContext.TargetChanged', target
    end
  end

  # @return [String]
  def websocket_endpoint
    @connection.url
  end

  def new_page
    @default_context.new_page
  end

  # @param {?string} contextId
  # @return {!Promise<!Puppeteer.Page>}
  def create_page_in_context(context_id)
    create_target_params = { url: 'about:blank' }
    if context_id
      create_target_params[:browserContextId] = context_id
    end
    result = @connection.send_message('Target.createTarget', **create_target_params)
    target_id = result['targetId']
    target = @targets[target_id]
    await target.initialized_promise
    await target.page
  end

  # @return {!Array<!Target>}
  def targets
    @targets.values.select { |target| target.initialized? }
  end


  # @return {!Target}
  def target
    targets.find { |target| target.type == 'browser' }
  end

  # used only in Target#opener
  private def find_target_by_id(target_id)
    @targets[target_id]
  end

  # @param {function(!Target):boolean} predicate
  # @param {{timeout?: number}=} options
  # @return {!Promise<!Target>}
  def wait_for_target(predicate:, timeout: nil)
    timeout_in_sec = (timeout || 30000).to_i / 1000.0
    existing_target = targets.first { |target| predicate.call(target) }
    return existing_target if existing_target

    event_listening_ids = []
    target_promise = resolvable_future
    event_listening_ids << add_event_listener('Events.Browser.TargetCreated') do |target|
      if predicate.call(target)
        target_promise.fulfill(target)
      end
    end
    event_listening_ids << add_event_listener('Events.Browser.TargetChanged') do |target|
      if predicate.call(target)
        target_promise.fulfill(target)
      end
    end

    begin
      if timeout_in_sec > 0
        Timeout.timeout(timeout_in_sec) do
          target_promise.value!
        end
      else
        target_promise.value!
      end
    ensure
      remove_event_listener(*event_listening_ids)
    end
  end

  # @return {!Promise<!Array<!Puppeteer.Page>>}
  def pages
    browser_contexts.flat_map(&:pages)
  end

  # @return [String]
  def version
    get_version.product
  end

  # @return [String]
  def user_agent
    get_version.user_agent
  end

  def close
    @close_callback.call
    disconnect
  end

  def disconnect
    @connection.dispose
  end

  def connected?
    !@connection.closed?
  end

  class Version
    def initialize(hash)
      @protocol_version = hash['protocolVersion']
      @product = hash['product']
      @revision = hash['revision']
      @user_agent = hash['userAgent']
      @js_version = hash['jsVersion']
    end

    attr_reader :protocol_version, :product, :revision, :user_agent, :js_version
  end

  private def get_version
    Version.new(@connection.send_message('Browser.getVersion'))
  end
end
