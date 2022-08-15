class Puppeteer::Frame
  using Puppeteer::DefineAsyncMethod

  # @param frame_manager [Puppeteer::FrameManager]
  # @param parent_frame [Puppeteer::Frame|nil]
  # @param frame_id [String]
  # @param client [Puppeteer::CDPSession]
  def initialize(frame_manager, parent_frame, frame_id, client)
    @frame_manager = frame_manager
    @parent_frame = parent_frame
    @id = frame_id
    @detached = false
    @has_started_loading = false

    @loader_id = ''
    @lifecycle_events = Set.new
    @child_frames = Set.new
    if parent_frame
      parent_frame._child_frames << self
    end

    update_client(client)
  end

  def inspect
    values = %i[id parent_frame detached loader_id lifecycle_events child_frames].map do |sym|
      value = instance_variable_get(:"@#{sym}")
      "@#{sym}=#{value}"
    end
    "#<Puppeteer::Frame #{values.join(' ')}>"
  end

  def _client
    @client
  end

  # @param client [Puppeteer::CDPSession]
  private def update_client(client)
    @client = client
    @main_world = Puppeteer::DOMWorld.new(@client, @frame_manager, self, @frame_manager.timeout_settings)
    @secondary_world = Puppeteer::DOMWorld.new(@client, @frame_manager, self, @frame_manager.timeout_settings)
  end

  def page
    @frame_manager.page
  end

  def oop_frame?
    @client != @frame_manager.client
  end

  attr_accessor :frame_manager, :id, :loader_id, :lifecycle_events, :main_world, :secondary_world

  def has_started_loading?
    @has_started_loading
  end

  # @param url [String]
  # @param rederer [String]
  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  # @return [Puppeteer::HTTPResponse]
  def goto(url, referer: nil, timeout: nil, wait_until: nil)
    @frame_manager.navigate_frame(self, url, referer: referer, timeout: timeout, wait_until: wait_until)
  end

  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  def wait_for_navigation(timeout: nil, wait_until: nil)
    @frame_manager.wait_for_frame_navigation(self, timeout: timeout, wait_until: wait_until)
  end

  define_async_method :async_wait_for_navigation

  def execution_context
    @main_world.execution_context
  end

  # @param {Function|string} pageFunction
  # @return {!Promise<!Puppeteer.JSHandle>}
  def evaluate_handle(page_function, *args)
    @main_world.evaluate_handle(page_function, *args)
  end

  define_async_method :async_evaluate_handle

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  def evaluate(page_function, *args)
    @main_world.evaluate(page_function, *args)
  end

  define_async_method :async_evaluate

  # `$()` in JavaScript.
  # @param {string} selector
  # @return {!Promise<?Puppeteer.ElementHandle>}
  def query_selector(selector)
    @main_world.query_selector(selector)
  end
  alias_method :S, :query_selector

  define_async_method :async_query_selector

  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} expression
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def Sx(expression)
    @main_world.Sx(expression)
  end

  define_async_method :async_Sx

  # `$eval()` in JavaScript.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def eval_on_selector(selector, page_function, *args)
    @main_world.eval_on_selector(selector, page_function, *args)
  end
  alias_method :Seval, :eval_on_selector

  define_async_method :async_eval_on_selector

  # `$$eval()` in JavaScript.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def eval_on_selector_all(selector, page_function, *args)
    @main_world.eval_on_selector_all(selector, page_function, *args)
  end
  alias_method :SSeval, :eval_on_selector_all

  define_async_method :async_eval_on_selector_all

  # `$$()` in JavaScript.
  # @param {string} selector
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def query_selector_all(selector)
    @main_world.query_selector_all(selector)
  end
  alias_method :SS, :query_selector_all

  define_async_method :async_query_selector_all

  # @return [String]
  def content
    @secondary_world.content
  end

  # @param html [String]
  # @param timeout [Integer]
  # @param wait_until [String|Array<String>]
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
    @child_frames.to_a
  end

  def detached?
    @detached
  end

  # @param url [String?]
  # @param path [String?]
  # @param content [String?]
  # @param type [String?]
  # @param id [String?]
  def add_script_tag(url: nil, path: nil, content: nil, type: nil, id: nil)
    @main_world.add_script_tag(url: url, path: path, content: content, type: type, id: id)
  end

  # @param url [String?]
  # @param path [String?]
  # @param content [String?]
  def add_style_tag(url: nil, path: nil, content: nil)
    @main_world.add_style_tag(url: url, path: path, content: content)
  end

  # @param selector [String]
  # @param delay [Number]
  # @param button [String] "left"|"right"|"middle"
  # @param click_count [Number]
  def click(selector, delay: nil, button: nil, click_count: nil)
    @secondary_world.click(selector, delay: delay, button: button, click_count: click_count)
  end

  define_async_method :async_click

  # @param {string} selector
  def focus(selector)
    @secondary_world.focus(selector)
  end

  define_async_method :async_focus

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

  define_async_method :async_select

  # @param {string} selector
  def tap(selector)
    @secondary_world.tap(selector)
  end

  define_async_method :async_tap

  # @param selector [String]
  # @param text [String]
  # @param delay [Number]
  def type_text(selector, text, delay: nil)
    @main_world.type_text(selector, text, delay: delay)
  end

  define_async_method :async_type_text

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

  define_async_method :async_wait_for_selector

  # @param milliseconds [Integer] the number of milliseconds to wait.
  def wait_for_timeout(milliseconds)
    sleep(milliseconds / 1000.0)
  end

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

  define_async_method :async_wait_for_xpath

  # @param page_function [String]
  # @param args [Integer|Array]
  # @param polling [String]
  # @param timeout [Integer]
  # @return [Puppeteer::JSHandle]
  def wait_for_function(page_function, args: [], polling: nil, timeout: nil)
    @main_world.wait_for_function(page_function, args: args, polling: polling, timeout: timeout)
  end

  define_async_method :async_wait_for_function

  # @return [String]
  def title
    @secondary_world.title
  end

  # @param frame_payload [Hash]
  def navigated(frame_payload)
    @name = frame_payload['name']
    @url = "#{frame_payload['url']}#{frame_payload['urlFragment']}"

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

  def handle_loading_started
    @has_started_loading = true
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
