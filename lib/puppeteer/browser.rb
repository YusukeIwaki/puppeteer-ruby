class Puppeteer::Browser
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
      close_callback: close_callback
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
    @connection.on_connection_disconnected do
      @on_browser_disconnected&.call
    end
    @connection.on_message do |message|
      puts "Browser#on_message #{message}"
      case message['method']
      when 'Target.targetCreated'
        handle_target_created(message['params'])
      when 'Target.targetDestroyed'
        handle_target_destroyed(message['params'])
      when 'Target.targetInfoChanged'
        handle_target_info_changed(message['params'])
      end
    end
  end

  # @return [Puppeteer::BrowserRunner::BrowserProcess]
  def process
    @process
  end

  # @return [Puppeteer::BrowserContext]
  def create_incognito_browser_context
    browser_context_id = @connection.send_message('Target.createBrowserContext')
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
    @connection.send_message('Target.disposeBrowserContext', browser_context_id: context_id)
    @contexts.remove(context_id)
  end

  # @param {!Protocol.Target.targetCreatedPayload} event
  def handle_target_created(event)
    target_info = event['targetInfo']
    browser_context_id = target_info['browserContextId']
    context =
      if browser_context_id && @contexts.has_key?(browser_context_id)
        @contexts[browser_context_id]
      else
        @default_context
      end
    #   const target = new Target(targetInfo, context, () => this._connection.createSession(targetInfo), this._ignoreHTTPSErrors, this._defaultViewport, this._screenshotTaskQueue);
    #   assert(!this._targets.has(event.targetInfo.targetId), 'Target should not exist before targetCreated');
    #   this._targets.set(event.targetInfo.targetId, target);

    if target.initialized_promise
      @on_browser_target_created&.call(target)
      context.emit_browser_context_target_created(target)
    end
  end


  # @param {{targetId: string}} event
  def handle_target_destroyed(event)
    target_id = event['targetId']
    target = @targets[target_id]
    target.initialized_callback(false)
    @targets.delete(target_id)
    target.closed_callback
    if target.initialized_promise
      @on_browser_target_destroyed&.call(target)
      target.browser_context.emit_browser_context_target_destroyed(target)
    end
  end

  # @param {!Protocol.Target.targetInfoChangedPayload} event
  def handle_target_info_changed(event)
    target_id = event['targetInfo']['targetId']
    target = @targets[target_id]
    if !target
      throw StandardError.new('target should exist before targetInfoChanged')
    end
    previous_url = target.url
    was_initialized = target.intialized?
    target.call_target_info_changed(event['targetInfo'])
    if was_initialized && previous_url != target.url
      @browser_target_changed&.call(target)
      @browser_context.emit_browser_context_target_changed(target)
    end
  end

  # @return [String]
  def websocket_endpoint
    @connection.url
  end

  def new_page
    @default_context.new_page
  end

  # /**
  #  * @param {?string} contextId
  #  * @return {!Promise<!Puppeteer.Page>}
  #  */
  # async _createPageInContext(contextId) {
  #   const {targetId} = await this._connection.send('Target.createTarget', {url: 'about:blank', browserContextId: contextId || undefined});
  #   const target = await this._targets.get(targetId);
  #   assert(await target._initializedPromise, 'Failed to create target for page');
  #   const page = await target.page();
  #   return page;
  # }

  # /**
  #  * @return {!Array<!Target>}
  #  */
  # targets() {
  #   return Array.from(this._targets.values()).filter(target => target._isInitialized);
  # }

  # /**
  #  * @return {!Target}
  #  */
  # target() {
  #   return this.targets().find(target => target.type() === 'browser');
  # }

  # /**
  #  * @param {function(!Target):boolean} predicate
  #  * @param {{timeout?: number}=} options
  #  * @return {!Promise<!Target>}
  #  */
  # async waitForTarget(predicate, options = {}) {
  #   const {
  #     timeout = 30000
  #   } = options;
  #   const existingTarget = this.targets().find(predicate);
  #   if (existingTarget)
  #     return existingTarget;
  #   let resolve;
  #   const targetPromise = new Promise(x => resolve = x);
  #   this.on(Events.Browser.TargetCreated, check);
  #   this.on(Events.Browser.TargetChanged, check);
  #   try {
  #     if (!timeout)
  #       return await targetPromise;
  #     return await helper.waitWithTimeout(targetPromise, 'target', timeout);
  #   } finally {
  #     this.removeListener(Events.Browser.TargetCreated, check);
  #     this.removeListener(Events.Browser.TargetChanged, check);
  #   }

  #   /**
  #    * @param {!Target} target
  #    */
  #   function check(target) {
  #     if (predicate(target))
  #       resolve(target);
  #   }
  # }

  # /**
  #  * @return {!Promise<!Array<!Puppeteer.Page>>}
  #  */
  # async pages() {
  #   const contextPages = await Promise.all(this.browserContexts().map(context => context.pages()));
  #   // Flatten array.
  #   return contextPages.reduce((acc, x) => acc.concat(x), []);
  # }

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

  private def get_version
    @connection.send_message('Browser.getVersion')
  end
end
