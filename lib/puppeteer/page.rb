class Puppeteer::Page
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
    @accessibility = Accessibility.new(client)
    @frame_manager = FrameManager.new(client, self, ignore_https_errors, @timeout_settings)
    @emulation_manager = EmulationManager.new(client)
    @tracing = Tracing.new(client)
    @page_bindings = {}
    @coverage = Coverage.new(client)
    @javascript_enabled = true
    @viewport = nil
    @screenshot_task_queue = screenshot_task_queue
    @workers = {}

  end

  def init
    @frame_manager.init
    @client.send_message('Target.setAutoAttach', autoAttach: true, waitForDebuggerOnStart: false, flatten: true)
    @client.send_message('Performance.enable')
    @client.send_message('Log.enable')
    begin
      @client.send_message('Page.setInterceptFileChooserDialog', enabled: true)
    rescue => err
      @file_chooser_interception_is_disabled = true
    end
  end

  def target
    @target
  end

  def browser
    @target.browser
  end

  def browser_context
    @target.browser_context
  end

  def main_frame
    @frame_manager.main_frame
  end

  def keyboard
    @keyboard
  end

  def touchscreen
    @touchscreen
  end

  def coverage
    @coverage
  end

  def accessibility
    @accessibility
  end

  def frames
    @frame_manager.frames
  end

  def workers
    @workers.values
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
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def Seval(selector, page_function, *args)
    main_frame.Seval(selector, page_function, *args)
  end

  # `$$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def SSeval(selector, page_function, *args)
    main_frame.SSeval(selector, page_function, *args)
  end

  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} expression
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def Sx(expression)
    main_frame.Sx(expression)
  end

  def evaluate(page_function, *args)
    @frame_manager.main_frame.evaluate(page_function, *args)
  end

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

  # @param style_tag [ScriptTag]
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

  # @param style_tag [StyleTag]
  # @return {!Promise<!ElementHandle>}
  def add_style_tag(style_tag)
    main_frame.add_style_tag(style_tag)
  end

  class AuthCredential
    # @param {?{username: string, password: string}} credentials
    def initialize(username: nil, password: nil)
      @username = username
      @password = password
    end
    attr_reader :username, :password
  end

  # @param credential [AuthCredential]
  def authenticate(credential)
    @frame_manager.network_manager.authenticate(credential)
  end

  # @param headers [Hash]
  def extra_http_headers=(headers)
    @frame_manager.network_manager.extra_http_headers = headers
  end

  # @param user_agent [String]
  def user_agent=(user_agent)
    @frame_manager.network_manager.user_agent = user_agent
  end

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
    set_content(html)
  end

  # @param {string} url
  # @param {!{referer?: string, timeout?: number, waitUntil?: string|!Array<string>}=} options
  # @return {!Promise<?Puppeteer.Response>}
  def goto(url, referer: nil, timeout: nil, wait_until: nil)
    main_frame.goto(url, referer: referer, timeout: timeout, wait_until: wait_until)
  end

  # @param {!{timeout?: number, waitUntil?: string|!Array<string>}=} options
  # @return {!Promise<?Puppeteer.Response>}
  def reload(timeout: nil, wait_until: nil)
    # const [response] = await Promise.all([
    #   this.waitForNavigation(options),
    #   this._client.send('Page.reload')
    # ]);
    # return response;
  end

  # @param {!{timeout?: number, waitUntil?: string|!Array<string>}=} options
  # @return {!Promise<?Puppeteer.Response>}
  def wait_for_navigation(timeout: nil, wait_until: nil)
    main_frame.wait_for_navigation(timeout: timeout, wait_until: wait_until)
  end

  # @param {!{timeout?: number, waitUntil?: string|!Array<string>}=} options
  # @return {!Promise<?Puppeteer.Response>}
  def go_back(timeout: nil, wait_until: nil)
    go(-1, timeout: timeout, wait_until: wait_until)
  end

  # @param {!{timeout?: number, waitUntil?: string|!Array<string>}=} options
  # @return {!Promise<?Puppeteer.Response>}
  def go_forward(timeout: nil, wait_until: nil)
    go(+1, timeout: timeout, wait_until: wait_until)
  end

  private def go(delta, timeout: nil, wait_until: nil)
    # const history = await this._client.send('Page.getNavigationHistory');
    # const entry = history.entries[history.currentIndex + delta];
    # if (!entry)
    #   return null;
    # const [response] = await Promise.all([
    #   this.waitForNavigation(options),
    #   this._client.send('Page.navigateToHistoryEntry', {entryId: entry.id}),
    # ]);
    # return response;
  end

  # @param device [Device]
  def emulate(device)
    viewport = device.viewport
    user_agent = device.user_agent
  end

  # @param {boolean} enabled
  def javascript_enabled=(enabled)
    return if (@javascript_enabled == enabled)
    @javascript_enabled = enabled
    # await this._client.send('Emulation.setScriptExecutionDisabled', { value: !enabled });
  end

  # @param viewport [Viewport]
  def viewport=(viewport)
    needs_reload = @emulation_manager.emulate_viewport(viewport)
    @viewport = viewport
    reload if needs_reload
  end

  def viewport
    @viewport
  end

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<*>}
  def evaluate(page_function, *args)
    main_frame.evaluate(page_function, *args)
  end

  # @param {boolean} enabled
  def cache_enabled=(enabled)
    @frame_manager.network_manager.cache_enabled = enabled
  end

  # @return {!Promise<string>}
  def title
    @title
  end

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

  # @return [Mouse]
  def mouse
    @mouse
  end

  # @param {string} selector
  # @param {!{delay?: number, button?: "left"|"right"|"middle", clickCount?: number}=} options
  def click(selector, delay: nil, button: nil, click_count: nil)
    main_frame.click(selector, delay: delay, button: button, click_count: click_count)
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

  # @param {string} selector
  def tap(selector)
    main_frame.tap(selector)
  end

  # @param {string} selector
  # @param {string} text
  # @param {{delay: (number|undefined)}=} options
  def type(selector, text, delay: nil)
    main_frame.type(selector, text, delay: delay)
  end

  # @param {string} selector
  # @param {!{visible?: boolean, hidden?: boolean, timeout?: number}=} options
  # @return {!Promise<?Puppeteer.ElementHandle>}
  def wait_for_selector(selector, options = {}) # TODO: あとでキーワード引数にする
    main_frame.wait_for_selector(selector, options)
  end

  # @param {string} xpath
  # @param {!{visible?: boolean, hidden?: boolean, timeout?: number}=} options
  # @return {!Promise<?Puppeteer.ElementHandle>}
  def wait_for_xpath(xpath, options = {}) # TODO: あとでキーワード引数にする
    main_frame.wait_for_xpath(xpath, options)
  end

  # @param {Function} pageFunction
  # @param {!{polling?: string|number, timeout?: number}=} options
  # @param {!Array<*>} args
  # @return {!Promise<!Puppeteer.JSHandle>}
  # def waitForFunction(page_function, options = {}, ...args) {
  #   return this.mainFrame().waitForFunction(pageFunction, options, ...args);
  # }
end
