require_relative './element_handle/bounding_box'
require_relative './element_handle/box_model'
require_relative './element_handle/offset'
require_relative './element_handle/point'

class Puppeteer::ElementHandle < Puppeteer::JSHandle
  include Puppeteer::DebugPrint
  include Puppeteer::IfPresent
  using Puppeteer::DefineAsyncMethod

  # @param context [Puppeteer::ExecutionContext]
  # @param client [Puppeteer::CDPSession]
  # @param remote_object [Puppeteer::RemoteObject]
  # @param frame [Puppeteer::Frame]
  # @param page [Puppeteer::Page]
  # @param frame_manager [Puppeteer::FrameManager]
  def initialize(context:, client:, remote_object:, frame:, page:, frame_manager:)
    super(context: context, client: client, remote_object: remote_object)
    @frame = frame
    @page = page
    @frame_manager = frame_manager
    @disposed = false
  end

  def inspect
    values = %i[context remote_object page disposed].map do |sym|
      value = instance_variable_get(:"@#{sym}")
      "@#{sym}=#{value}"
    end
    "#<Puppeteer::ElementHandle #{values.join(' ')}>"
  end

  #
  # Wait for the `selector` to appear within the element. If at the moment of calling the
  # method the `selector` already exists, the method will return immediately. If
  # the `selector` doesn't appear after the `timeout` milliseconds of waiting, the
  # function will throw.
  #
  # This method does not work across navigations or if the element is detached from DOM.
  #
  # @param selector - A
  # {@link https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_Selectors | selector}
  # of an element to wait for
  # @param options - Optional waiting parameters
  # @returns Promise which resolves when element specified by selector string
  # is added to DOM. Resolves to `null` if waiting for hidden: `true` and
  # selector is not found in DOM.
  # @remarks
  # The optional parameters in `options` are:
  #
  # - `visible`: wait for the selected element to be present in DOM and to be
  # visible, i.e. to not have `display: none` or `visibility: hidden` CSS
  # properties. Defaults to `false`.
  #
  # - `hidden`: wait for the selected element to not be found in the DOM or to be hidden,
  # i.e. have `display: none` or `visibility: hidden` CSS properties. Defaults to
  # `false`.
  #
  # - `timeout`: maximum time to wait in milliseconds. Defaults to `30000`
  # (30 seconds). Pass `0` to disable timeout. The default value can be changed
  # by using the {@link Page.setDefaultTimeout} method.
  def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil)
    frame = @context.frame

    secondary_world = frame.secondary_world
    adopted_root = secondary_world.execution_context.adopt_element_handle(self)
    handle = secondary_world.wait_for_selector(selector, visible: visible, hidden: hidden, timeout: timeout, root: adopted_root)
    adopted_root.dispose
    return nil unless handle

    main_world = frame.main_world
    result = main_world.execution_context.adopt_element_handle(handle)
    handle.dispose
    result
  end

  define_async_method :async_wait_for_selector

  # Wait for the `xpath` within the element. If at the moment of calling the
  # method the `xpath` already exists, the method will return immediately. If
  # the `xpath` doesn't appear after the `timeout` milliseconds of waiting, the
  # function will throw.
  #
  # If `xpath` starts with `//` instead of `.//`, the dot will be appended automatically.
  #
  # This method works across navigation
  # ```js
  # const puppeteer = require('puppeteer');
  # (async () => {
  # const browser = await puppeteer.launch();
  # const page = await browser.newPage();
  # let currentURL;
  # page
  # .waitForXPath('//img')
  # .then(() => console.log('First URL with image: ' + currentURL));
  # for (currentURL of [
  # 'https://example.com',
  # 'https://google.com',
  # 'https://bbc.com',
  # ]) {
  # await page.goto(currentURL);
  # }
  # await browser.close();
  # })();
  # ```
  # @param xpath - A
  # {@link https://developer.mozilla.org/en-US/docs/Web/XPath | xpath} of an
  # element to wait for
  # @param options - Optional waiting parameters
  # @returns Promise which resolves when element specified by xpath string is
  # added to DOM. Resolves to `null` if waiting for `hidden: true` and xpath is
  # not found in DOM.
  # @remarks
  # The optional Argument `options` have properties:
  #
  # - `visible`: A boolean to wait for element to be present in DOM and to be
  # visible, i.e. to not have `display: none` or `visibility: hidden` CSS
  # properties. Defaults to `false`.
  #
  # - `hidden`: A boolean wait for element to not be found in the DOM or to be
  # hidden, i.e. have `display: none` or `visibility: hidden` CSS properties.
  # Defaults to `false`.
  #
  # - `timeout`: A number which is maximum time to wait for in milliseconds.
  # Defaults to `30000` (30 seconds). Pass `0` to disable timeout. The default
  # value can be changed by using the {@link Page.setDefaultTimeout} method.
  def wait_for_xpath(xpath, visible: nil, hidden: nil, timeout: nil)
    frame = @context.frame

    secondary_world = frame.secondary_world
    adopted_root = secondary_world.execution_context.adopt_element_handle(self)
    param_xpath =
      if xpath.start_with?('//')
        ".#{xpath}"
      else
        xpath
      end
    unless param_xpath.start_with?('.//')
      adopted_root.dispose
      raise ArgumentError.new("Unsupported xpath expression: #{xpath}")
    end
    handle = secondary_world.wait_for_xpath(param_xpath, visible: visible, hidden: hidden, timeout: timeout, root: adopted_root)
    adopted_root.dispose
    return nil unless handle

    main_world = frame.main_world
    result = main_world.execution_context.adopt_element_handle(handle)
    handle.dispose
    result
  end

  define_async_method :async_wait_for_xpath

  def as_element
    self
  end

  def content_frame
    node_info = @remote_object.node_info(@client)
    frame_id = node_info['node']['frameId']
    if frame_id.is_a?(String)
      @frame_manager.frame(frame_id)
    else
      nil
    end
  end

  class ScrollIntoViewError < StandardError; end

  def scroll_into_view_if_needed
    js = <<~JAVASCRIPT
      async(element) => {
        if (!element.isConnected)
          return 'Node is detached from document';
        if (element.nodeType !== Node.ELEMENT_NODE)
          return 'Node is not of type HTMLElement';
        return false;
      }
    JAVASCRIPT
    error = evaluate(js, @page.javascript_enabled) # returns String or false
    if error
      raise ScrollIntoViewError.new(error)
    end
    begin
      @remote_object.scroll_into_view_if_needed(@client)
    rescue => err
      # Just ignore 'Node does not have a layout object' for backward-compatibility.
      raise unless err.message =~ /Node does not have a layout object/
    end

    # clickpoint is often calculated before scrolling is completed.
    # So, just sleep about 10 frames
    sleep 0.16
  end

  class ElementNotVisibleError < StandardError
    def initialize
      super("Node is either not visible or not an HTMLElement")
    end
  end

  class ElementNotClickableError < StandardError
    def initialize
      super("Node is either not clickable or not an HTMLElement")
    end
  end

  # @param quad [Array<Array<Point>>]]
  # @param offset [Point]
  private def apply_offsets_to_quad(quad, offset)
    quad.map { |part| part + offset }
  end

  # @param frame [Puppeteer::Frame]
  # @return [Point]
  private def oopif_offsets(frame)
    offset = Point.new(x: 0, y: 0)
    while frame.parent_frame
      parent = frame.parent_frame
      unless frame.oop_frame?
        frame = parent
        next
      end
      backend_node_id = parent._client.send_message('DOM.getFrameOwner', frameId: frame.id)['backendNodeId']
      result = parent._client.send_message('DOM.getBoxModel', backendNodeId: backend_node_id)
      break unless result
      offset = BoxModel.new(result['model'], offset: offset).content.first
      frame = parent
    end
    offset
  end

  def clickable_point(offset = nil)
    offset_param = Offset.from(offset)

    result =
      begin
        @remote_object.content_quads(@client)
      rescue => err
        debug_puts(err)
        nil
      end

    if !result || result["quads"].empty?
      raise ElementNotVisibleError.new
    end

    # Filter out quads that have too small area to click into.
    layout_metrics = @page.client.send_message('Page.getLayoutMetrics')

    if result.empty? || result["quads"].empty?
      raise ElementNotClickableError.new
    end

    # Filter out quads that have too small area to click into.
    # Fallback to `layoutViewport` in case of using Firefox.
    layout_viewport = layout_metrics["cssLayoutViewport"] || layout_metrics["layoutViewport"]
    client_width = layout_viewport["clientWidth"]
    client_height = layout_viewport["clientHeight"]

    oopif_offset = oopif_offsets(@frame)
    quads = result["quads"].
              map { |quad| from_protocol_quad(quad) }.
              map { |quad| apply_offsets_to_quad(quad, oopif_offset) }.
              map { |quad| intersect_quad_with_viewport(quad, client_width, client_height) }.
              select { |quad| compute_quad_area(quad) > 1 }
    if quads.empty?
      raise ElementNotVisibleError.new
    end

    if offset_param
      # Return the point of the first quad identified by offset.
      quad = quads.first
      min_x = quad.map(&:x).min
      min_y = quad.map(&:y).min
      if min_x && min_y
        return Point.new(
          x: min_x + offset_param.x,
          y: min_y + offset_param.y,
        )
      end
    end

    # Return the middle point of the first quad.
    quads.first.reduce(:+) / 4
  end

  # @param quad [Array<number>]
  # @return [Array<Point>]
  private def from_protocol_quad(quad)
    quad.each_slice(2).map do |x, y|
      Point.new(x: x, y: y)
    end
  end

  # @param quad [Array<Point>]
  # @param width [number]
  # @param height [number]
  # @return [Array<Point>]
  private def intersect_quad_with_viewport(quad, width, height)
    quad.map do |point|
      Point.new(
        x: [[point.x, 0].max, width].min,
        y: [[point.y, 0].max, height].min,
      )
    end
  end

  def hover
    scroll_into_view_if_needed
    point = clickable_point
    @page.mouse.move(point.x, point.y)
  end

  # @param delay [Number]
  # @param button [String] "left"|"right"|"middle"
  # @param click_count [Number]
  # @param offset [Hash]
  def click(delay: nil, button: nil, click_count: nil, offset: nil)
    scroll_into_view_if_needed
    point = clickable_point(offset)
    @page.mouse.click(point.x, point.y, delay: delay, button: button, click_count: click_count)
  end

  define_async_method :async_click

  class DragInterceptionNotEnabledError < StandardError
    def initialize
      super('Drag Interception is not enabled!')
    end
  end

  def drag(x:, y:)
    unless @page.drag_interception_enabled?
      raise DragInterceptionNotEnabledError.new
    end
    scroll_into_view_if_needed
    start = clickable_point
    @page.mouse.drag(start, Point.new(x: x, y: y))
  end

  def drag_enter(data)
    scroll_into_view_if_needed
    target = clickable_point
    @page.mouse.drag_enter(target, data)
  end

  def drag_over(data)
    scroll_into_view_if_needed
    target = clickable_point
    @page.mouse.drag_over(target, data)
  end

  def drop(data)
    scroll_into_view_if_needed
    target = clickable_point
    @page.mouse.drop(target, data)
  end

  # @param target [ElementHandle]
  def drag_and_drop(target, delay: nil)
    scroll_into_view_if_needed
    start_point = clickable_point
    target_point = target.clickable_point
    @page.mouse.drag_and_drop(start_point, target_point, delay: delay)
  end

  # @return [Array<String>]
  def select(*values)
    if nonstring = values.find { |value| !value.is_a?(String) }
      raise ArgumentError.new("Values must be strings. Found value \"#{nonstring}\" of type \"#{nonstring.class}\"")
    end

    fn = <<~JAVASCRIPT
    (element, vals) => {
      const values = new Set(vals);
      if (element.nodeName.toLowerCase() !== 'select') {
        throw new Error('Element is not a <select> element.');
      }

      const selectedValues = new Set();
      if (!element.multiple) {
        for (const option of element.options) {
          option.selected = false;
        }
        for (const option of element.options) {
          if (values.has(option.value)) {
            option.selected = true;
            selectedValues.add(option.value);
            break;
          }
        }
      } else {
        for (const option of element.options) {
          option.selected = values.has(option.value);
          if (option.selected) {
            selectedValues.add(option.value);
          }
        }
      }
      element.dispatchEvent(new Event('input', { bubbles: true }));
      element.dispatchEvent(new Event('change', { bubbles: true }));
      return [...selectedValues.values()];
    }
    JAVASCRIPT
    evaluate(fn, values)
  end

  # @param file_paths [Array<String>]
  def upload_file(*file_paths)
    is_multiple = evaluate("el => el.multiple")
    if !is_multiple && file_paths.length >= 2
      raise ArgumentError.new('Multiple file uploads only work with <input type=file multiple>')
    end

    backend_node_id = @remote_object.node_info(@client)["node"]["backendNodeId"]

    # The zero-length array is a special case, it seems that DOM.setFileInputFiles does
    # not actually update the files in that case, so the solution is to eval the element
    # value to a new FileList directly.
    if file_paths.empty?
      fn = <<~JAVASCRIPT
      (element) => {
        element.files = new DataTransfer().files;

        // Dispatch events for this case because it should behave akin to a user action.
        element.dispatchEvent(new Event('input', { bubbles: true }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
      }
      JAVASCRIPT
      await evaluate(fn)
    else
      @remote_object.set_file_input_files(@client, file_paths.map { |path| File.expand_path(path) }, backend_node_id)
    end
  end

  def tap(&block)
    return super(&block) if block

    scroll_into_view_if_needed
    point = clickable_point
    @page.touchscreen.tap(point.x, point.y)
  end

  define_async_method :async_tap

  def focus
    evaluate('element => element.focus()')
  end

  define_async_method :async_focus

  # @param text [String]
  # @param delay [number|nil]
  def type_text(text, delay: nil)
    focus
    @page.keyboard.type_text(text, delay: delay)
  end

  define_async_method :async_type_text

  # @param key [String]
  # @param text [String]
  # @param delay [number|nil]
  def press(key, delay: nil, text: nil)
    focus
    @page.keyboard.press(key, delay: delay, text: text)
  end

  define_async_method :async_press

  # @return [BoundingBox|nil]
  def bounding_box
    if_present(box_model) do |result_model|
      offset = oopif_offsets(@frame)
      quads = result_model.border

      x = quads.map(&:x).min
      y = quads.map(&:y).min
      BoundingBox.new(
        x: x + offset.x,
        y: y + offset.y,
        width: quads.map(&:x).max - x,
        height: quads.map(&:y).max - y,
      )
    end
  end

  # @return [BoxModel|nil]
  def box_model
    if_present(@remote_object.box_model(@client)) do |result|
      BoxModel.new(result['model'], offset: oopif_offsets(@frame))
    end
  end

  def screenshot(type: nil,
                 path: nil,
                 full_page: nil,
                 clip: nil,
                 quality: nil,
                 omit_background: nil,
                 encoding: nil,
                 capture_beyond_viewport: nil,
                 from_surface: nil)
    needs_viewport_reset = false

    box = bounding_box
    unless box
      raise ElementNotVisibleError.new
    end

    viewport = @page.viewport
    if viewport && (box.width > viewport.width || box.height > viewport.height)
      new_viewport = viewport.merge(
        width: [viewport.width, box.width.to_i].min,
        height: [viewport.height, box.height.to_i].min,
      )
      @page.viewport = new_viewport

      needs_viewport_reset = true
    end
    scroll_into_view_if_needed

    box = bounding_box
    unless box
      raise ElementNotVisibleError.new
    end
    if box.width == 0
      raise 'Node has 0 width.'
    end
    if box.height == 0
      raise 'Node has 0 height.'
    end

    layout_metrics = @client.send_message('Page.getLayoutMetrics')
    page_x = layout_metrics["layoutViewport"]["pageX"]
    page_y = layout_metrics["layoutViewport"]["pageY"]

    if clip.nil?
      clip = {
        x: page_x + box.x,
        y: page_y + box.y,
        width: box.width,
        height: box.height,
      }
    end

    @page.screenshot(
      type: type,
      path: path,
      full_page:
      full_page,
      clip: clip,
      quality: quality,
      omit_background: omit_background,
      encoding: encoding,
      capture_beyond_viewport: capture_beyond_viewport,
      from_surface: from_surface)
  ensure
    if needs_viewport_reset
      @page.viewport = viewport
    end
  end

  private def query_handler_manager
    Puppeteer::QueryHandlerManager.instance
  end

  # `$()` in JavaScript.
  # @param selector [String]
  def query_selector(selector)
    query_handler_manager.detect_query_handler(selector).query_one(self)
  end
  alias_method :S, :query_selector

  # `$$()` in JavaScript.
  # @param selector [String]
  def query_selector_all(selector)
    query_handler_manager.detect_query_handler(selector).query_all(self)
  end
  alias_method :SS, :query_selector_all

  class ElementNotFoundError < StandardError
    def initialize(selector)
      super("failed to find element matching selector \"#{selector}\"")
    end
  end

  # `$eval()` in JavaScript.
  # @param selector [String]
  # @param page_function [String]
  # @return [Object]
  def eval_on_selector(selector, page_function, *args)
    element_handle = query_selector(selector)
    unless element_handle
      raise ElementNotFoundError.new(selector)
    end
    result = element_handle.evaluate(page_function, *args)
    element_handle.dispose

    result
  end
  alias_method :Seval, :eval_on_selector

  define_async_method :async_eval_on_selector

  # `$$eval()` in JavaScript.
  # @param selector [String]
  # @param page_function [String]
  # @return [Object]
  def eval_on_selector_all(selector, page_function, *args)
    handles = query_handler_manager.detect_query_handler(selector).query_all_array(self)
    result = handles.evaluate(page_function, *args)
    handles.dispose

    result
  end
  alias_method :SSeval, :eval_on_selector_all

  define_async_method :async_eval_on_selector_all

  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param expression [String]
  # @return [Array<ElementHandle>]
  def Sx(expression)
    fn = <<~JAVASCRIPT
    (element, expression) => {
      const document = element.ownerDocument || element;
      const iterator = document.evaluate(expression, element, null, XPathResult.ORDERED_NODE_ITERATOR_TYPE);
      const array = [];
      let item;
      while ((item = iterator.iterateNext()))
        array.push(item);
      return array;
    }
    JAVASCRIPT
    handles = evaluate_handle(fn, expression)
    properties = handles.properties
    handles.dispose
    properties.values.map(&:as_element).compact
  end

  define_async_method :async_Sx

  # in JS, #isIntersectingViewport.
  # @param threshold [Float|nil]
  # @return [Boolean]
  def intersecting_viewport?(threshold: nil)
    option_threshold = threshold || 0
    js = <<~JAVASCRIPT
    async (element, threshold) => {
      const visibleRatio = await new Promise(resolve => {
        const observer = new IntersectionObserver(entries => {
          resolve(entries[0].intersectionRatio);
          observer.disconnect();
        });
        observer.observe(element);
      });
      if (threshold === 1) return visibleRatio === 1;
      else return visibleRatio > threshold;
    }
    JAVASCRIPT

    evaluate(js, option_threshold)
  end

  # @param quad [Array<Point>]
  private def compute_quad_area(quad)
    # Compute sum of all directed areas of adjacent triangles
    # https://en.wikipedia.org/wiki/Polygon#Simple_polygons
    quad.zip(quad.rotate).map { |p1, p2| (p1.x * p2.y - p2.x * p1.y) / 2 }.reduce(:+).abs
  end

  # used in AriaQueryHandler
  def query_ax_tree(accessible_name: nil, role: nil)
    @remote_object.query_ax_tree(@client,
    accessible_name: accessible_name, role: role)
  end
end
