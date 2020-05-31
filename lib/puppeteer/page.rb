require 'base64'

require_relative './page/screenshot_options'

class Puppeteer::Page
  include Puppeteer::EventCallbackable
  include Puppeteer::IfPresent
  using Puppeteer::AsyncAwaitBehavior

  # @param {!Puppeteer.CDPSession} client
  # @param {!Puppeteer.Target} target
  # @param {boolean} ignoreHTTPSErrors
  # @param {?Puppeteer.Viewport} defaultViewport
  # @param {!Puppeteer.TaskQueue} screenshotTaskQueue
  # @return {!Promise<!Page>}
  def self.create(client, target, ignore_https_errors, default_viewport, screenshot_task_queue)
    page = Puppeteer::Page.new(client, target, ignore_https_errors, screenshot_task_queue)
    page.init
    if default_viewport
      page.viewport = default_viewport
    end
    page
  end

  # @param {!Puppeteer.CDPSession} client
  # @param {!Puppeteer.Target} target
  # @param {boolean} ignoreHTTPSErrors
  # @param {!Puppeteer.TaskQueue} screenshotTaskQueue
  def initialize(client, target, ignore_https_errors, screenshot_task_queue)
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
    # @tracing = Tracing.new(client)
    @page_bindings = {}
    # @coverage = Coverage.new(client)
    @javascript_enabled = true
    @screenshot_task_queue = screenshot_task_queue

    @workers = {}
    @client.on_event 'Target.attachedToTarget' do |event|
      if event['targetInfo']['type'] != 'worker'
        # If we don't detach from service workers, they will never die.
        await @client.send_message('Target.detachFromTarget', sessionId: event['sessionId'])
        next
      end

      session = Puppeteer::Connection.from_session(@client).session(event['sessionId']) # rubocop:disable Lint/UselessAssignment
      #   const worker = new Worker(session, event.targetInfo.url, this._addConsoleMessage.bind(this), this._handleException.bind(this));
      #   this._workers.set(event.sessionId, worker);
      #   this.emit(Events.Page.WorkerCreated, worker);
    end
    @client.on_event 'Target.detachedFromTarget' do |event|
      session_id = event['sessionId']
      worker = @workers[session_id]
      next unless worker

      emit_event('Events.Page.WorkerDestroyed', worker)
      @workers.delete(session_id)
    end

    @frame_manager.on_event 'Events.FrameManager.FrameAttached' do |event|
      emit_event 'Events.Page.FrameAttached', event
    end
    @frame_manager.on_event 'Events.FrameManager.FrameDetached' do |event|
      emit_event 'Events.Page.FrameDetached', event
    end
    @frame_manager.on_event 'Events.FrameManager.FrameNavigated' do |event|
      emit_event 'Events.Page.FrameNavigated', event
    end

    network_manager = @frame_manager.network_manager
    network_manager.on_event 'Events.NetworkManager.Request' do |event|
      emit_event 'Events.Page.Request', event
    end
    network_manager.on_event 'Events.NetworkManager.Response' do |event|
      emit_event 'Events.Page.Response', event
    end
    network_manager.on_event 'Events.NetworkManager.RequestFailed' do |event|
      emit_event 'Events.Page.RequestFailed', event
    end
    network_manager.on_event 'Events.NetworkManager.RequestFinished' do |event|
      emit_event 'Events.Page.RequestFinished', event
    end
    @file_chooser_interception_is_disabled = false
    @file_chooser_interceptors = Set.new

    @client.on_event 'Page.domContentEventFired' do |event|
      emit_event 'Events.Page.DOMContentLoaded'
    end
    @client.on_event 'Page.loadEventFired' do |event|
      emit_event 'Events.Page.Load'
    end
    # client.on('Runtime.consoleAPICalled', event => this._onConsoleAPI(event));
    # client.on('Runtime.bindingCalled', event => this._onBindingCalled(event));
    # client.on('Page.javascriptDialogOpening', event => this._onDialog(event));
    # client.on('Runtime.exceptionThrown', exception => this._handleException(exception.exceptionDetails));
    # client.on('Inspector.targetCrashed', event => this._onTargetCrashed());
    # client.on('Performance.metrics', event => this._emitMetrics(event));
    @client.on_event 'Log.entryAdded' do |event|
      handle_log_entry_added(event)
    end
    @client.on_event 'Page.fileChooserOpened' do |event|
      handle_file_chooser(event)
    end
    @target.on_close do
      emit_event 'Events.Page.Close'
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

  # @param timeout [Integer]
  # @return [Future<Puppeteer::FileChooser>]
  async def async_wait_for_file_chooser(timeout: nil)
    wait_for_file_chooser(timeout: timeout)
  end


  # /**
  #  * @param {!{longitude: number, latitude: number, accuracy: (number|undefined)}} options
  #  */
  # async setGeolocation(options) {
  #   const { longitude, latitude, accuracy = 0} = options;
  #   if (longitude < -180 || longitude > 180)
  #     throw new Error(`Invalid longitude "${longitude}": precondition -180 <= LONGITUDE <= 180 failed.`);
  #   if (latitude < -90 || latitude > 90)
  #     throw new Error(`Invalid latitude "${latitude}": precondition -90 <= LATITUDE <= 90 failed.`);
  #   if (accuracy < 0)
  #     throw new Error(`Invalid accuracy "${accuracy}": precondition 0 <= ACCURACY failed.`);
  #   await this._client.send('Emulation.setGeolocationOverride', {longitude, latitude, accuracy});
  # }

  attr_reader :javascript_enabled, :target

  def browser
    @target.browser
  end

  def browser_context
    @target.browser_context
  end

  class TargetCrashedError < StandardError; end

  private def handle_target_crashed
    emit_event 'error', TargetCrashedError.new('Page crashed!')
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
      emit_event('Events.Page.Console',
        Puppeteer::ConsoleMessage.new(level, text, [], console_message_location))
    end
  end

  def main_frame
    @frame_manager.main_frame
  end

  attr_reader :keyboard, :touch_screen, :coverage, :accessibility

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

  # `$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @return {!Promise<?Puppeteer.ElementHandle>}
  def S(selector)
    main_frame.S(selector)
  end

  # `$$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def SS(selector)
    main_frame.SS(selector)
  end

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<!Puppeteer.JSHandle>}
  def evaluate_handle(page_function, *args)
    context = main_frame.execution_context
    context.evaluate_handle(page_function, *args)
  end

  # @param {!Puppeteer.JSHandle} prototypeHandle
  # @return {!Promise<!Puppeteer.JSHandle>}
  def query_objects(prototype_handle)
    context = main_frame.execution_context
    context.query_objects(prototype_handle)
  end

  # `$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param selector [String]
  # @param page_function [String]
  # @return [Object]
  def Seval(selector, page_function, *args)
    main_frame.Seval(selector, page_function, *args)
  end

  # `$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param selector [String]
  # @param page_function [String]
  # @return [Future]
  async def async_Seval(selector, page_function, *args)
    Seval(selector, page_function, *args)
  end

  # `$$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param selector [String]
  # @param page_function [String]
  # @return [Object]
  def SSeval(selector, page_function, *args)
    main_frame.SSeval(selector, page_function, *args)
  end

  # `$$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param selector [String]
  # @param page_function [String]
  # @return [Future]
  async def async_SSeval(selector, page_function, *args)
    SSeval(selector, page_function, *args)
  end

  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} expression
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def Sx(expression)
    main_frame.Sx(expression)
  end

  # /**
  #  * @param {!Array<string>} urls
  #  * @return {!Promise<!Array<Network.Cookie>>}
  #  */
  # async cookies(...urls) {
  #   return (await this._client.send('Network.getCookies', {
  #     urls: urls.length ? urls : [this.url()]
  #   })).cookies;
  # }

  # /**
  #  * @param {Array<Protocol.Network.deleteCookiesParameters>} cookies
  #  */
  # async deleteCookie(...cookies) {
  #   const pageURL = this.url();
  #   for (const cookie of cookies) {
  #     const item = Object.assign({}, cookie);
  #     if (!cookie.url && pageURL.startsWith('http'))
  #       item.url = pageURL;
  #     await this._client.send('Network.deleteCookies', item);
  #   }
  # }

  # /**
  #  * @param {Array<Network.CookieParam>} cookies
  #  */
  # async setCookie(...cookies) {
  #   const pageURL = this.url();
  #   const startsWithHTTP = pageURL.startsWith('http');
  #   const items = cookies.map(cookie => {
  #     const item = Object.assign({}, cookie);
  #     if (!item.url && startsWithHTTP)
  #       item.url = pageURL;
  #     assert(item.url !== 'about:blank', `Blank page can not have cookie "${item.name}"`);
  #     assert(!String.prototype.startsWith.call(item.url || '', 'data:'), `Data URL page can not have cookie "${item.name}"`);
  #     return item;
  #   });
  #   await this.deleteCookie(...items);
  #   if (items.length)
  #     await this._client.send('Network.setCookies', { cookies: items });
  # }

  class ScriptTag
    # @param {!{content?: string, path?: string, type?: string, url?: string}} options
    def initialize(content: nil, path: nil, type: nil, url: nil)
      @content = content
      @path = path
      @type = type
      @url = url
    end
    attr_reader :content, :path, :type, :url
  end

  # @param style_tag [Puppeteer::Page::ScriptTag]
  # @return {!Promise<!ElementHandle>}
  def add_script_tag(script_tag)
    main_frame.add_script_tag(script_tag)
  end

  class StyleTag
    # @param {!{content?: string, path?: string, url?: string}} options
    def initialize(content: nil, path: nil, url: nil)
      @content = content
      @path = path
      @url = url
    end
    attr_reader :content, :path, :url
  end

  # @param style_tag [Puppeteer::Page::StyleTag]
  # @return {!Promise<!ElementHandle>}
  def add_style_tag(style_tag)
    main_frame.add_style_tag(style_tag)
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
  #   this.emit(Events.Page.Metrics, {
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

  # /**
  #  * @param {!Protocol.Runtime.ExceptionDetails} exceptionDetails
  #  */
  # _handleException(exceptionDetails) {
  #   const message = helper.getExceptionMessage(exceptionDetails);
  #   const err = new Error(message);
  #   err.stack = ''; // Don't report clientside error with a node stack attached
  #   this.emit(Events.Page.PageError, err);
  # }

  # /**
  #  * @param {!Protocol.Runtime.consoleAPICalledPayload} event
  #  */
  # async _onConsoleAPI(event) {
  #   if (event.executionContextId === 0) {
  #     // DevTools protocol stores the last 1000 console messages. These
  #     // messages are always reported even for removed execution contexts. In
  #     // this case, they are marked with executionContextId = 0 and are
  #     // reported upon enabling Runtime agent.
  #     //
  #     // Ignore these messages since:
  #     // - there's no execution context we can use to operate with message
  #     //   arguments
  #     // - these messages are reported before Puppeteer clients can subscribe
  #     //   to the 'console'
  #     //   page event.
  #     //
  #     // @see https://github.com/puppeteer/puppeteer/issues/3865
  #     return;
  #   }
  #   const context = this._frameManager.executionContextById(event.executionContextId);
  #   const values = event.args.map(arg => createJSHandle(context, arg));
  #   this._addConsoleMessage(event.type, values, event.stackTrace);
  # }

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

  # /**
  #  * @param {string} type
  #  * @param {!Array<!Puppeteer.JSHandle>} args
  #  * @param {Protocol.Runtime.StackTrace=} stackTrace
  #  */
  # _addConsoleMessage(type, args, stackTrace) {
  #   if (!this.listenerCount(Events.Page.Console)) {
  #     args.forEach(arg => arg.dispose());
  #     return;
  #   }
  #   const textTokens = [];
  #   for (const arg of args) {
  #     const remoteObject = arg._remoteObject;
  #     if (remoteObject.objectId)
  #       textTokens.push(arg.toString());
  #     else
  #       textTokens.push(helper.valueFromRemoteObject(remoteObject));
  #   }
  #   const location = stackTrace && stackTrace.callFrames.length ? {
  #     url: stackTrace.callFrames[0].url,
  #     lineNumber: stackTrace.callFrames[0].lineNumber,
  #     columnNumber: stackTrace.callFrames[0].columnNumber,
  #   } : {};
  #   const message = new ConsoleMessage(type, textTokens.join(' '), args, location);
  #   this.emit(Events.Page.Console, message);
  # }

  # _onDialog(event) {
  #   let dialogType = null;
  #   if (event.type === 'alert')
  #     dialogType = Dialog.Type.Alert;
  #   else if (event.type === 'confirm')
  #     dialogType = Dialog.Type.Confirm;
  #   else if (event.type === 'prompt')
  #     dialogType = Dialog.Type.Prompt;
  #   else if (event.type === 'beforeunload')
  #     dialogType = Dialog.Type.BeforeUnload;
  #   assert(dialogType, 'Unknown javascript dialog type: ' + event.type);
  #   const dialog = new Dialog(this._client, dialogType, event.message, event.defaultPrompt);
  #   this.emit(Events.Page.Dialog, dialog);
  # }

  # @return [String]
  def url
    main_frame.url
  end

  # @return [String]
  def content
    main_frame.content
  end

  # @param {string} html
  # @param {!{timeout?: number, waitUntil?: string|!Array<string>}=} options
  def set_content(html, timeout: nil, wait_until: nil)
    main_frame.set_content(html, timeout: timeout, wait_until: wait_until)
  end

  # @param {string} html
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

  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  private def wait_for_navigation(timeout: nil, wait_until: nil)
    main_frame.wait_for_navigation(timeout: timeout, wait_until: wait_until)
  end

  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  # @return [Future]
  async def async_wait_for_navigation(timeout: nil, wait_until: nil)
    wait_for_navigation(timeout: timeout, wait_until: wait_until)
  end

  # /**
  #  * @param {(string|Function)} urlOrPredicate
  #  * @param {!{timeout?: number}=} options
  #  * @return {!Promise<!Puppeteer.Request>}
  #  */
  # async waitForRequest(urlOrPredicate, options = {}) {
  #   const {
  #     timeout = this._timeoutSettings.timeout(),
  #   } = options;
  #   return helper.waitForEvent(this._frameManager.networkManager(), Events.NetworkManager.Request, request => {
  #     if (helper.isString(urlOrPredicate))
  #       return (urlOrPredicate === request.url());
  #     if (typeof urlOrPredicate === 'function')
  #       return !!(urlOrPredicate(request));
  #     return false;
  #   }, timeout, this._sessionClosePromise());
  # }

  # /**
  #  * @param {(string|Function)} urlOrPredicate
  #  * @param {!{timeout?: number}=} options
  #  * @return {!Promise<!Puppeteer.Response>}
  #  */
  # async waitForResponse(urlOrPredicate, options = {}) {
  #   const {
  #     timeout = this._timeoutSettings.timeout(),
  #   } = options;
  #   return helper.waitForEvent(this._frameManager.networkManager(), Events.NetworkManager.Response, response => {
  #     if (helper.isString(urlOrPredicate))
  #       return (urlOrPredicate === response.url());
  #     if (typeof urlOrPredicate === 'function')
  #       return !!(urlOrPredicate(response));
  #     return false;
  #   }, timeout, this._sessionClosePromise());
  # }

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

  # /**
  #  * @param {boolean} enabled
  #  */
  # async setBypassCSP(enabled) {
  #   await this._client.send('Page.setBypassCSP', { enabled });
  # }

  # /**
  #  * @param {?string} type
  #  */
  # async emulateMediaType(type) {
  #   assert(type === 'screen' || type === 'print' || type === null, 'Unsupported media type: ' + type);
  #   await this._client.send('Emulation.setEmulatedMedia', {media: type || ''});
  # }

  # /**
  #  * @param {?Array<MediaFeature>} features
  #  */
  # async emulateMediaFeatures(features) {
  #   if (features === null)
  #     await this._client.send('Emulation.setEmulatedMedia', {features: null});
  #   if (Array.isArray(features)) {
  #     features.every(mediaFeature => {
  #       const name = mediaFeature.name;
  #       assert(/^prefers-(?:color-scheme|reduced-motion)$/.test(name), 'Unsupported media feature: ' + name);
  #       return true;
  #     });
  #     await this._client.send('Emulation.setEmulatedMedia', {features: features});
  #   }
  # }

  # @param timezone_id [String?]
  def emulate_timezone(timezone_id)
    @client.send_message('Emulation.setTimezoneOverride', timezoneId: timezoneId || '')
  rescue => err
    if err.message.include?('Invalid timezone')
      raise ArgumentError.new("Invalid timezone ID: #{timezone_id}")
    else
      raise err
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

  # /**
  #  * @param {Function|string} pageFunction
  #  * @param {!Array<*>} args
  #  */
  # async evaluateOnNewDocument(pageFunction, ...args) {
  #   const source = helper.evaluationString(pageFunction, ...args);
  #   await this._client.send('Page.addScriptToEvaluateOnNewDocument', { source });
  # }

  # @param {boolean} enabled
  def cache_enabled=(enabled)
    @frame_manager.network_manager.cache_enabled = enabled
  end

  # @return {!Promise<string>}
  def title
    @title
  end

  # /**
  #  * @param {!ScreenshotOptions=} options
  #  * @return {!Promise<!Buffer|!String>}
  #  */
  def screenshot(options = {})
    screenshot_options = ScreenshotOptions.new(options)

    # @screenshot_task_queue.post_task(-> { screenshot_task(screenshot_options.type, screenshot_options) })
    screenshot_task(screenshot_options.type, screenshot_options)
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
        if @viewport.landscape?
          { angle: 90, type: 'landscapePrimary' }
        else
          { angle: 0, type: 'portraitPrimary' }
        end
      @client.send_message('Emulation.setDeviceMetricsOverride',
        mobile: @viewport.mobile?,
        width: width,
        height: height,
        deviceScaleFactor: @viewport.device_scale_factor,
        screenOrientation: screen_orientation)
    end

    should_set_default_background = screenshot_options.omit_background? && format == 'png'
    if should_set_default_background
      @client.send_message('Emulation.setDefaultBackgroundColorOverride', color: { r: 0, g: 0, b: 0, a: 0 })
    end
    screenshot_params = {
      format: format,
      quality: screenshot_options.quality,
      clip: clip,
    }.compact
    result = @client.send_message('Page.captureScreenshot', screenshot_params)
    if should_set_default_background
      @client.send_message('Emulation.setDefaultBackgroundColorOverride')
    end

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

  # /**
  #  * @param {!PDFOptions=} options
  #  * @return {!Promise<!Buffer>}
  #  */
  # async pdf(options = {}) {
  #   const {
  #     scale = 1,
  #     displayHeaderFooter = false,
  #     headerTemplate = '',
  #     footerTemplate = '',
  #     printBackground = false,
  #     landscape = false,
  #     pageRanges = '',
  #     preferCSSPageSize = false,
  #     margin = {},
  #     path = null
  #   } = options;

  #   let paperWidth = 8.5;
  #   let paperHeight = 11;
  #   if (options.format) {
  #     const format = Page.PaperFormats[options.format.toLowerCase()];
  #     assert(format, 'Unknown paper format: ' + options.format);
  #     paperWidth = format.width;
  #     paperHeight = format.height;
  #   } else {
  #     paperWidth = convertPrintParameterToInches(options.width) || paperWidth;
  #     paperHeight = convertPrintParameterToInches(options.height) || paperHeight;
  #   }

  #   const marginTop = convertPrintParameterToInches(margin.top) || 0;
  #   const marginLeft = convertPrintParameterToInches(margin.left) || 0;
  #   const marginBottom = convertPrintParameterToInches(margin.bottom) || 0;
  #   const marginRight = convertPrintParameterToInches(margin.right) || 0;

  #   const result = await this._client.send('Page.printToPDF', {
  #     transferMode: 'ReturnAsStream',
  #     landscape,
  #     displayHeaderFooter,
  #     headerTemplate,
  #     footerTemplate,
  #     printBackground,
  #     scale,
  #     paperWidth,
  #     paperHeight,
  #     marginTop,
  #     marginBottom,
  #     marginLeft,
  #     marginRight,
  #     pageRanges,
  #     preferCSSPageSize
  #   });
  #   return await helper.readProtocolStream(this._client, result.stream, path);
  # }

  # @param {!{runBeforeUnload: (boolean|undefined)}=} options
  def close
    # assert(!!this._client._connection, 'Protocol error: Connection closed. Most likely the page has been closed.');
    # const runBeforeUnload = !!options.runBeforeUnload;
    # if (runBeforeUnload) {
    #   await this._client.send('Page.close');
    # } else {
    #   await this._client._connection.send('Target.closeTarget', { targetId: this._target._targetId });
    #   await this._target._isClosedPromise;
    # }
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

  # @param selector [String]
  # @param delay [Number]
  # @param button [String] "left"|"right"|"middle"
  # @param click_count [Number]
  # @return [Future]
  async def async_click(selector, delay: nil, button: nil, click_count: nil)
    click(selector, delay: delay, button: button, click_count: click_count)
  end

  # @param {string} selector
  def focus(selector)
    main_frame.focus(selector)
  end

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

  # @param selector [String]
  def tap(selector)
    main_frame.tap(selector)
  end

  # @param selector [String]
  async def async_tap(selector)
    tap(selector)
  end

  # @param selector [String]
  # @param text [String]
  # @param delay [Number]
  def type_text(selector, text, delay: nil)
    main_frame.type_text(selector, text, delay: delay)
  end

  # /**
  #  * @param {(string|number|Function)} selectorOrFunctionOrTimeout
  #  * @param {!{visible?: boolean, hidden?: boolean, timeout?: number, polling?: string|number}=} options
  #  * @param {!Array<*>} args
  #  * @return {!Promise<!Puppeteer.JSHandle>}
  #  */
  # waitFor(selectorOrFunctionOrTimeout, options = {}, ...args) {
  #   return this.mainFrame().waitFor(selectorOrFunctionOrTimeout, options, ...args);
  # }

  # @param selector [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil)
    main_frame.wait_for_selector(selector, visible: visible, hidden: hidden, timeout: timeout)
  end

  # @param selector [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  async def async_wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil)
    wait_for_selector(selector, visible: visible, hidden: hidden, timeout: timeout)
  end

  # @param xpath [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  def wait_for_xpath(xpath, visible: nil, hidden: nil, timeout: nil)
    main_frame.wait_for_xpath(xpath, visible: visible, hidden: hidden, timeout: timeout)
  end

  # @param xpath [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  async def async_wait_for_xpath(xpath, visible: nil, hidden: nil, timeout: nil)
    wait_for_xpath(xpath, visible: visible, hidden: hidden, timeout: timeout)
  end

  # @param {Function|string} pageFunction
  # @param {!{polling?: string|number, timeout?: number}=} options
  # @param {!Array<*>} args
  # @return {!Promise<!Puppeteer.JSHandle>}
  def wait_for_function(page_function, options = {}, *args)
    main_frame.wait_for_function(page_function, options, *args)
  end
end
