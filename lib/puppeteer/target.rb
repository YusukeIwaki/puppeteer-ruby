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
  # @param {!Puppeteer.TaskQueue} screenshotTaskQueue
  def initialize(target_info:, browser_context:, session_factory:, ignore_https_errors:, default_viewport:, screenshot_task_queue:)
    @target_info = target_info
    @browser_context = browser_context
    @target_id = target_info.target_id
    @session_factory = session_factory
    @ignore_https_errors = ignore_https_errors
    @default_viewport = default_viewport
    @screenshot_task_queue = screenshot_task_queue


    #    /** @type {?Promise<!Puppeteer.Page>} */
    #    this._pagePromise = null;
    #    /** @type {?Promise<!Worker>} */
    #    this._workerPromise = null;
    #    this._initializedPromise = new Promise(fulfill => this._initializedCallback = fulfill).then(async success => {
    #    this._isClosedPromise = new Promise(fulfill => this._closedCallback = fulfill);

    @is_initialized = @target_info.type != 'page' || !@target_info.url.empty?

    if @is_initialized
      handle_initialized(true)
    end
  end

  def handle_initialized(success)
    @initialized_promise = success
    return unless success
    @on_initialize_succeeded&.call
    opener_page = opener&.page
    if opener_page.nil? || type != 'page'
      return
    end
    #      if (!openerPage.listenerCount(Events.Page.Popup))
    #        return true;
    popup_page = page
    opener_page.emit_event('Events.Page.Popup', popup_page)
  end

  def on_initialize_completed(&block)
    @on_initialize_succeeded = block
  end

  def handle_closed
    @closed = true
  end

  def initialized?
    @is_initialized
  end

  def create_cdp_session
    @session_factory.call
  end

  def page
    if ['page', 'background_page'].include?(@target_info.type) && @page.nil?
      client = @session_factory.call
      @page = Puppeteer::Page.create(client, self, @ignore_https_errors, @default_viewport, @screenshot_task_queue)
    end
    @page
  end

  #  /**
  #   * @return {!Promise<?Worker>}
  #   */
  #  async worker() {
  #    if (this._targetInfo.type !== 'service_worker' && this._targetInfo.type !== 'shared_worker')
  #      return null;
  #    if (!this._workerPromise) {
  #      // TODO(einbinder): Make workers send their console logs.
  #      this._workerPromise = this._sessionFactory()
  #          .then(client => new Worker(client, this._targetInfo.url, () => {} /* consoleAPICalled */, () => {} /* exceptionThrown */));
  #    }
  #    return this._workerPromise;
  #  }

  # @return {string}
  def url
    @target_info.url
  end

  # @return {"page"|"background_page"|"service_worker"|"shared_worker"|"other"|"browser"}
  def type
    type = @target_info.type
    if ['page', 'background_page', 'service_worker', 'shared_worker', 'browser'].include?(type)
      type
    else
      'other'
    end
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
    browser.targets[opener_id]
  end

  # @param {!Protocol.Target.TargetInfo} targetInfo
  def handle_target_info_changed(target_info)
    @target_info = target_info

    if !@is_initialized && (@target_info.type != 'page' || !target_info.url.empty?)
      @is_initialized = true
      handle_initialized(true)
    end
  end
end
