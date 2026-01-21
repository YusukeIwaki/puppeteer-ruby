# https://github.com/puppeteer/puppeteer/blob/master/lib/Target.js
class Puppeteer::Target
  class TargetInfo
    def initialize(options)
      @target_id = options['targetId']
      @type = options['type']
      @title = options['title']
      @url = options['url']
      @attached = options['attached']
      @browser_context_id = options['browserContextId']
      @opener_id = options['openerId']
    end
    attr_reader :target_id, :type, :title, :url, :attached, :browser_context_id, :opener_id
  end

  # @param {!Protocol.Target.TargetInfo} targetInfo
  # @param {!Puppeteer.BrowserContext} browserContext
  # @param {!function():!Promise<!Puppeteer.CDPSession>} sessionFactory
  # @param {boolean} ignoreHTTPSErrors
  # @param {?Puppeteer.Viewport} defaultViewport
  # @param {boolean} networkEnabled
  def initialize(target_info:,
                 session:,
                 browser_context:,
                 target_manager:,
                 session_factory:,
                 ignore_https_errors:,
                 default_viewport:,
                 network_enabled:,
                 is_page_target_callback:)
    @session = session
    @target_manager = target_manager
    @target_info = target_info
    @browser_context = browser_context
    @target_id = target_info.target_id
    @session_factory = session_factory
    @ignore_https_errors = ignore_https_errors
    @default_viewport = default_viewport
    @network_enabled = network_enabled
    @is_page_target_callback = is_page_target_callback
    @worker = nil

    #    /** @type {?Promise<!Puppeteer.Page>} */
    #    this._pagePromise = null;
    #    /** @type {?Promise<!Worker>} */
    #    this._workerPromise = null;
    @initialize_callback_promise = Async::Promise.new
    @initialized_promise = Async::Promise.new
    @is_closed_promise = Async::Promise.new

    Async do
      @initialized_promise.resolve(handle_initialized(@initialize_callback_promise.wait))
    rescue => err
      @initialized_promise.reject(err)
    end

    @is_initialized = !@is_page_target_callback.call(@target_info) || !@target_info.url.empty?

    if @is_initialized
      @initialize_callback_promise.resolve(true)
    end
  end

  attr_reader :target_id, :target_info, :initialized_promise, :is_closed_promise

  def ==(other)
    other = other.__getobj__ if other.is_a?(Puppeteer::ReactorRunner::Proxy)
    return true if equal?(other)
    return false unless other.is_a?(Puppeteer::Target)
    return false if target_id.nil? || other.target_id.nil?

    target_id == other.target_id
  end

  def eql?(other)
    self == other
  end

  def hash
    target_id ? target_id.hash : super
  end

  def closed_callback
    @is_closed_promise.resolve(true) unless @is_closed_promise.resolved?
  end

  class InitializeFailure < Puppeteer::Error; end

  def ignore_initialize_callback_promise
    unless @initialize_callback_promise.resolved?
      @initialize_callback_promise.resolve(false)
    end
  end

  private def handle_initialized(success)
    unless success
      raise InitializeFailure.new('Failed to create target for page')
    end
    opener_page = opener&.page
    if opener_page.nil? || type != 'page'
      return true
    end
    #      if (!openerPage.listenerCount(PageEmittedEvents::Popup))
    #        return true;
    popup_page = page
    opener_page.emit_event(PageEmittedEvents::Popup, popup_page)

    true
  end

  def initialized?
    @is_initialized
  end

  # @return [CDPSession|nil]
  def session
    @session
  end

  def create_cdp_session
    session = @session_factory.call(false)
    session.target = self if session.respond_to?(:target=)
    session
  end

  def target_manager
    @target_manager
  end

  def page
    if @is_page_target_callback.call(@target_info) && @page.nil?
      client = @session || @session_factory.call(true)
      client.wait_for_ready if client.respond_to?(:wait_for_ready)
      @page = Puppeteer::Page.create(
        client,
        self,
        @ignore_https_errors,
        @default_viewport,
        network_enabled: @network_enabled,
      )
    end
    @page
  end

  # @return [Puppeteer::CdpWebWorker|nil]
  def worker
    return nil unless ['service_worker', 'shared_worker'].include?(@target_info.type)
    return @worker if @worker

    if @target_info.type == 'service_worker'
      @target_manager&.wait_for_service_worker_detach(@target_id)
    end

    client =
      if @target_info.type == 'service_worker'
        @session_factory.call(false)
      else
        @session || @session_factory.call(false)
      end
    client.target = self if client.respond_to?(:target=)
    client.wait_for_ready if client.respond_to?(:wait_for_ready)
    @worker = Puppeteer::CdpWebWorker.new(
      client,
      @target_info.url,
      @target_id,
      @target_info.type,
      nil,
      nil,
    )
  end

  # @return {string}
  def url
    @target_info.url
  end

  # @return {"page"|"background_page"|"service_worker"|"shared_worker"|"webview"|"tab"|"other"|"browser"}
  def type
    type = @target_info.type
    if ['page', 'background_page', 'service_worker', 'shared_worker', 'webview', 'tab', 'browser'].include?(type)
      type
    else
      'other'
    end
  end

  # @internal
  def raw_type
    @target_info.type
  end

  # @return {!Puppeteer.Browser}
  def browser
    @browser_context.browser
  end

  # @return {!Puppeteer.BrowserContext}
  def browser_context
    @browser_context
  end

  # @return {?Puppeteer.Target}
  def opener
    opener_id = @target_info.opener_id
    return nil if opener_id.nil?
    browser.send(:find_target_by_id, opener_id)
  end

  # @param {!Protocol.Target.TargetInfo} targetInfo
  def handle_target_info_changed(target_info)
    @target_info = target_info

    if !@is_initialized && (!@is_page_target_callback.call(@target_info) || !@target_info.url.empty?)
      @is_initialized = true
      @initialize_callback_promise.resolve(true)
    end
  end
end
