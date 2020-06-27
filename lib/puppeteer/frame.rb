class Puppeteer::Frame
  using Puppeteer::DefineAsyncMethod

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

  attr_accessor :frame_manager, :id, :loader_id, :lifecycle_events, :main_world, :secondary_world

  # @param url [String]
  # @param rederer [String]
  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  # @return [Puppeteer::Response]
  def goto(url, referer: nil, timeout: nil, wait_until: nil)
    @frame_manager.navigate_frame(self, url, referer: referer, timeout: timeout, wait_until: wait_until)
  end

  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  private def wait_for_navigation(timeout: nil, wait_until: nil)
    @frame_manager.wait_for_frame_navigation(self, timeout: timeout, wait_until: wait_until)
  end

  define_async_method_for :wait_for_navigation

  def execution_context
    @main_world.execution_context
  end

  # @param {Function|string} pageFunction
  # @return {!Promise<!Puppeteer.JSHandle>}
  def evaluate_handle(page_function, *args)
    @main_world.evaluate_handle(page_function, *args)
  end

  define_async_method_for :evaluate_handle

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  def evaluate(page_function, *args)
    @main_world.evaluate(page_function, *args)
  end

  define_async_method_for :evaluate

  # `$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @return {!Promise<?Puppeteer.ElementHandle>}
  def S(selector)
    @main_world.S(selector)
  end

  define_async_method_for :S

  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} expression
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def Sx(expression)
    @main_world.Sx(expression)
  end

  define_async_method_for :Sx

  # `$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def Seval(selector, page_function, *args)
    @main_world.Seval(selector, page_function, *args)
  end

  define_async_method_for :Seval

  # `$$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def SSeval(selector, page_function, *args)
    @main_world.SSeval(selector, page_function, *args)
  end

  define_async_method_for :SSeval

  # `$$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def SS(selector)
    @main_world.SS(selector)
  end

  define_async_method_for :SS

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

  # @param selector [String]
  # @param delay [Number]
  # @param button [String] "left"|"right"|"middle"
  # @param click_count [Number]
  def click(selector, delay: nil, button: nil, click_count: nil)
    @secondary_world.click(selector, delay: delay, button: button, click_count: click_count)
  end

  define_async_method_for :click

  # @param {string} selector
  def focus(selector)
    @secondary_world.focus(selector)
  end

  define_async_method_for :focus

  # @param {string} selector
  def hover(selector)
    @secondary_world.hover(selector)
  end

  # @param {string} selector
  # @param {!Array<string>} values
  # @return {!Promise<!Array<string>>}
  def select(selector, *values)
    @secondary_world.select(selector, *values)
  end

  define_async_method_for :select

  # @param {string} selector
  def tap(selector)
    @secondary_world.tap(selector)
  end

  define_async_method_for :tap

  # @param selector [String]
  # @param text [String]
  # @param delay [Number]
  def type_text(selector, text, delay: nil)
    @main_world.type_text(selector, text, delay: delay)
  end

  define_async_method_for :type_text

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

  # @param selector [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil)
    handle = @secondary_world.wait_for_selector(selector, visible: visible, hidden: hidden, timeout: timeout)
    if !handle
      return nil
    end
    main_execution_context = @main_world.execution_context
    result = main_execution_context.adopt_element_handle(handle)
    handle.dispose
    result
  end

  define_async_method_for :wait_for_selector

  # @param xpath [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  def wait_for_xpath(xpath, visible: nil, hidden: nil, timeout: nil)
    handle = @secondary_world.wait_for_xpath(xpath, visible: visible, hidden: hidden, timeout: timeout)
    if !handle
      return nil
    end
    main_execution_context = @main_world.execution_context
    result = main_execution_context.adopt_element_handle(handle)
    handle.dispose
    result
  end

  define_async_method_for :wait_for_xpath

  # @param {Function|string} pageFunction
  # @param {!{polling?: string|number, timeout?: number}=} options
  # @param {!Array<*>} args
  # @return {!Promise<!Puppeteer.JSHandle>}
  def wait_for_function(page_function, options = {}, *args)
    @main_world.wait_for_function(page_function, options, *args)
  end

  define_async_method_for :wait_for_function

  # @return [String]
  def title
    @secondary_world.title
  end

  # @param frame_payload [Hash]
  def navigated(frame_payload)
    @name = frame_payload['name']
    # TODO(lushnikov): remove this once requestInterception has loaderId exposed.
    @navigation_url = frame_payload['url']
    @url = frame_payload['url']

    # Ensure loaderId updated.
    # The order of [Page.lifecycleEvent name="init"] and [Page.frameNavigated] is random... for some reason...
    @loader_id = frame_payload['loaderId']
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
    @main_world.detach
    @secondary_world.detach
    if @parent_frame
      @parent_frame._child_frames.delete(self)
    end
    @parent_frame = nil
  end
end
