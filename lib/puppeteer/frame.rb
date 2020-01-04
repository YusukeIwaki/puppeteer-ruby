class Puppeteer::Frame
  # @param {!FrameManager} frameManager
  # @param {!Puppeteer.CDPSession} client
  # @param {?Frame} parentFrame
  # @param {string} frameId
  def initialize(frame_manager, client, parent_frame, frame_id)
    @frame_manager = frame_manager
    @client = client
    @parent_frame = parent_frame
    @id = frame_id
    @detached = false

    @loader_id = ''
    @lifecycle_events = Set.new
    @main_world = Puppeteer::DOMWorld.new(frame_manager, self, frame_manager.timeout_settings)
    @secondary_world = Puppeteer::DOMWorld.new(frame_manager, self, frame_manager.timeout_settings)
    @child_frames = Set.new
    if parent_frame
      parent_frame._child_frames << self
    end
  end

  attr_accessor :id, :main_world, :secondary_world

  # @param url [String]
  # @param {!{referer?: string, timeout?: number, waitUntil?: string|!Array<string>}=} options
  # @return [Puppeteer::Response]
  def goto(url, referer: nil, timeout: nil, wait_until: nil)
    @frame_manager.navigate_frame(self, url, referer: referer, timeout: timeout, wait_until: wait_until)
  end

  # @param {!{timeout?: number, waitUntil?: string|!Array<string>}=} options
  # @return {!Promise<?Puppeteer.Response>}
  def wait_for_navigation(timeout: nil, wait_until: nil)
    @frame_manager.wait_for_navigation(self, timeout: timeout, wait_until: wait_until)
  end

  def execution_context
    @main_world.execution_context
  end

  # @param {Function|string} pageFunction
  # @return {!Promise<!Puppeteer.JSHandle>}
  def evaluate_handle(page_function, *args)
    @main_world.evaluate_handle(page_function, *args)
  end

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  def evaluate(page_function, *args)
    @main_world.evaluate(page_function, *args)
  end

  # `$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @return {!Promise<?Puppeteer.ElementHandle>}
  def S(selector)
    @main_world.S(selector)
  end


  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} expression
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def Sx(expression)
    @main_world.Sx(expression)
  end


  # `$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def Seval(selector, page_function, *args)
    @main_world.Seval(selector, page_function, *args)
  end

  # `$$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def SSeval(selector, page_function, *args)
    @main_world.SSeval(selector, page_function, *args)
  end

  # `$$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def SS(selector)
    @main_world.SS(selector)
  end

  def content
    @secondary_world.content
  end

  # @param {string} html
  # @param {!{timeout?: number, waitUntil?: string|!Array<string>}=} options
  def set_content(html, timeout: nil, wait_until: nil)
    @secondary_world.set_content(html, timeout: timeout, wait_until: wait_until)
  end

  # @return [String]
  def name
    @name || ''
  end

  # @return [String]
  def url
    @url
  end

  # @return [Frame?]
  def parent_frame
    @parent_frame
  end

  protected def _child_frames
    @child_frames
  end

  def child_frames
    @child_frames.dup
  end

  def detached?
    @detached
  end

  # @param style_tag [Puppeteer::Page::ScriptTag]
  # @return {!Promise<!ElementHandle>}
  def add_script_tag(script_tag)
    @main_world.add_script_tag(script_tag)
  end

  # @param style_tag [Puppeteer::Page::StyleTag]
  # @return {!Promise<!ElementHandle>}
  def add_style_tag(style_tag)
    @main_world.add_style_tag(style_tag)
  end

  # /**
  #  * @param {string} selector
  #  * @param {!{delay?: number, button?: "left"|"right"|"middle", clickCount?: number}=} options
  #  */
  # async click(selector, options) {
  #   return this._secondaryWorld.click(selector, options);
  # }

  # /**
  #  * @param {string} selector
  #  */
  # async focus(selector) {
  #   return this._secondaryWorld.focus(selector);
  # }

  # /**
  #  * @param {string} selector
  #  */
  # async hover(selector) {
  #   return this._secondaryWorld.hover(selector);
  # }

  # /**
  # * @param {string} selector
  # * @param {!Array<string>} values
  # * @return {!Promise<!Array<string>>}
  # */
  # select(selector, ...values){
  #   return this._secondaryWorld.select(selector, ...values);
  # }

  # /**
  #  * @param {string} selector
  #  */
  # async tap(selector) {
  #   return this._secondaryWorld.tap(selector);
  # }

  # /**
  #  * @param {string} selector
  #  * @param {string} text
  #  * @param {{delay: (number|undefined)}=} options
  #  */
  # async type(selector, text, options) {
  #   return this._mainWorld.type(selector, text, options);
  # }

  # /**
  #  * @param {(string|number|Function)} selectorOrFunctionOrTimeout
  #  * @param {!Object=} options
  #  * @param {!Array<*>} args
  #  * @return {!Promise<?Puppeteer.JSHandle>}
  #  */
  # waitFor(selectorOrFunctionOrTimeout, options = {}, ...args) {
  #   const xPathPattern = '//';

  #   if (helper.isString(selectorOrFunctionOrTimeout)) {
  #     const string = /** @type {string} */ (selectorOrFunctionOrTimeout);
  #     if (string.startsWith(xPathPattern))
  #       return this.waitForXPath(string, options);
  #     return this.waitForSelector(string, options);
  #   }
  #   if (helper.isNumber(selectorOrFunctionOrTimeout))
  #     return new Promise(fulfill => setTimeout(fulfill, /** @type {number} */ (selectorOrFunctionOrTimeout)));
  #   if (typeof selectorOrFunctionOrTimeout === 'function')
  #     return this.waitForFunction(selectorOrFunctionOrTimeout, options, ...args);
  #   return Promise.reject(new Error('Unsupported target type: ' + (typeof selectorOrFunctionOrTimeout)));
  # }

  # /**
  #  * @param {string} selector
  #  * @param {!{visible?: boolean, hidden?: boolean, timeout?: number}=} options
  #  * @return {!Promise<?Puppeteer.ElementHandle>}
  #  */
  # async waitForSelector(selector, options) {
  #   const handle = await this._secondaryWorld.waitForSelector(selector, options);
  #   if (!handle)
  #     return null;
  #   const mainExecutionContext = await this._mainWorld.executionContext();
  #   const result = await mainExecutionContext._adoptElementHandle(handle);
  #   await handle.dispose();
  #   return result;
  # }

  # /**
  #  * @param {string} xpath
  #  * @param {!{visible?: boolean, hidden?: boolean, timeout?: number}=} options
  #  * @return {!Promise<?Puppeteer.ElementHandle>}
  #  */
  # async waitForXPath(xpath, options) {
  #   const handle = await this._secondaryWorld.waitForXPath(xpath, options);
  #   if (!handle)
  #     return null;
  #   const mainExecutionContext = await this._mainWorld.executionContext();
  #   const result = await mainExecutionContext._adoptElementHandle(handle);
  #   await handle.dispose();
  #   return result;
  # }

  # /**
  #  * @param {Function|string} pageFunction
  #  * @param {!{polling?: string|number, timeout?: number}=} options
  #  * @return {!Promise<!Puppeteer.JSHandle>}
  #  */
  # waitForFunction(pageFunction, options = {}, ...args) {
  #   return this._mainWorld.waitForFunction(pageFunction, options, ...args);
  # }

  # /**
  #  * @return {!Promise<string>}
  #  */
  # async title() {
  #   return this._secondaryWorld.title();
  # }

  # @param frame_payload [Hash]
  def navigated(frame_payload)
    @name = frame_payload['name']
    # TODO(lushnikov): remove this once requestInterception has loaderId exposed.
    @navigation_url = frame_payload['url']
    @url = frame_payload['url']
  end

  # @param url [String]
  def navigated_within_document(url)
    @url = url
  end

  def handle_lifecycle_event(loader_id, name)
    if name == 'init'
      @loader_id = loader_id
      @lifecycle_events.clear
    end
    @lifecycle_events << name
  end

  def handle_loading_stopped
    @lifecycle_events << 'DOMContentLoaded'
    @lifecycle_events << 'load'
  end

  def detach
    @detached = true
    #   this._mainWorld._detach();
    #   this._secondaryWorld._detach();
    if @parent_frame
      @parent_frame._child_frames.delete(self)
    end
    @parent_frame = nil
  end
end
