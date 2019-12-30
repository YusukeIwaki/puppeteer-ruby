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
    @ignore_https_errors = ignore_https_errors
    @default_viewport = default_viewport
    @screenshot_task_queue = screenshot_task_queue


    #    /** @type {?Promise<!Puppeteer.Page>} */
    #    this._pagePromise = null;
    #    /** @type {?Promise<!Worker>} */
    #    this._workerPromise = null;
    #    this._initializedPromise = new Promise(fulfill => this._initializedCallback = fulfill).then(async success => {
    #      if (!success)
    #        return false;
    #      const opener = this.opener();
    #      if (!opener || !opener._pagePromise || this.type() !== 'page')
    #        return true;
    #      const openerPage = await opener._pagePromise;
    #      if (!openerPage.listenerCount(Events.Page.Popup))
    #        return true;
    #      const popupPage = await this.page();
    #      openerPage.emit(Events.Page.Popup, popupPage);
    #      return true;
    #    });
    #    this._isClosedPromise = new Promise(fulfill => this._closedCallback = fulfill);

    @is_initialized = @target_info.type != 'page' || !@target_info.url.empty?

    if @is_initialized
      @initial_callback.call(true)
    end
  end

  def initialized?
    @is_initialized
  end

  def create_cdp_session
    @session_factory.call
  end

  #  /**
  #   * @return {!Promise<?Page>}
  #   */
  #  async page() {
  #    if ((this._targetInfo.type === 'page' || this._targetInfo.type === 'background_page') && !this._pagePromise) {
  #      this._pagePromise = this._sessionFactory()
  #          .then(client => Page.create(client, this, this._ignoreHTTPSErrors, this._defaultViewport, this._screenshotTaskQueue));
  #    }
  #    return this._pagePromise;
  #  }

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
    opener_id = this.target_info.opener_id
    return nil if opener_id.nil?
    browser.targets[opener_id]
  end

  # @param {!Protocol.Target.TargetInfo} targetInfo
  private def handle_target_info_changed(target_info)
    @target_info = target_info

    #    if (!this._isInitialized && (this._targetInfo.type !== 'page' || this._targetInfo.url !== '')) {
    #      this._isInitialized = true;
    #      this._initializedCallback(true);
    #      return;
    #    }
  end
end
