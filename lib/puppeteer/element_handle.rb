# rbs_inline: enabled

require_relative './element_handle/bounding_box'
require_relative './element_handle/box_model'
require_relative './element_handle/offset'
require_relative './element_handle/point'

class Puppeteer::ElementHandle < Puppeteer::JSHandle
  include Puppeteer::DebugPrint
  include Puppeteer::IfPresent
  using Puppeteer::DefineAsyncMethod

  # @rbs context: Puppeteer::ExecutionContext -- Execution context
  # @rbs client: Puppeteer::CDPSession -- CDP session
  # @rbs remote_object: Puppeteer::RemoteObject -- Remote object handle
  # @rbs frame: Puppeteer::Frame -- Owning frame
  def initialize(context:, client:, remote_object:, frame:)
    super(context: context, client: client, remote_object: remote_object)
    @frame = frame
    @page = frame.page
    @frame_manager = frame.frame_manager
    @disposed = false
  end

  attr_reader :page, :frame, :frame_manager

  # @rbs return: String -- Inspection string
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
  # {@link https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_Selectors | selector}
  # of an element to wait for
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
  # @rbs selector: String -- CSS selector
  # @rbs visible: bool? -- Wait for element to be visible
  # @rbs hidden: bool? -- Wait for element to be hidden
  # @rbs timeout: Numeric? -- Maximum wait time in milliseconds
  # @rbs return: Puppeteer::ElementHandle? -- Matched element handle
  def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil)
    query_handler_manager.detect_query_handler(selector).wait_for(self, visible: visible, hidden: hidden, timeout: timeout)
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
  # {@link https://developer.mozilla.org/en-US/docs/Web/XPath | xpath} of an
  # element to wait for
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
  # @rbs xpath: String -- XPath expression
  # @rbs visible: bool? -- Wait for element to be visible
  # @rbs hidden: bool? -- Wait for element to be hidden
  # @rbs timeout: Numeric? -- Maximum wait time in milliseconds
  # @rbs return: Puppeteer::ElementHandle? -- Matched element handle
  def wait_for_xpath(xpath, visible: nil, hidden: nil, timeout: nil)
    param_xpath =
      if xpath.start_with?('//')
        ".#{xpath}"
      else
        xpath
      end

    wait_for_selector("xpath/#{param_xpath}", visible: visible, hidden: hidden, timeout: timeout)
  end

  define_async_method :async_wait_for_xpath

  # @rbs tag_name: String -- Tag name to assert
  # @rbs return: Puppeteer::ElementHandle -- Element handle
  def to_element(tag_name)
    unless evaluate('(node, tagName) => node.nodeName === tagName.toUpperCase()', tag_name)
      raise ArgumentError.new("Element is not a(n) `#{tag_name}` element")
    end
    self
  end

  # @rbs return: Puppeteer::ElementHandle -- Element handle
  def as_element
    self
  end

  # @rbs return: bool -- Whether element is visible
  def visible?
    check_visibility(true)
  end

  # @rbs return: bool -- Whether element is hidden
  def hidden?
    check_visibility(false)
  end

  # @rbs visible: bool -- Expected visibility state
  # @rbs return: bool -- Whether visibility matches
  private def check_visibility(visible)
    js = <<~JAVASCRIPT
      (node, visible) => {
        if (!node) return visible === false;
        const element =
          node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
        if (!element) return visible === false;
        const style = window.getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        const isVisible =
          style &&
          style.visibility !== 'hidden' &&
          style.visibility !== 'collapse' &&
          rect.width !== 0 &&
          rect.height !== 0;
        return visible === isVisible;
      }
    JAVASCRIPT
    evaluate(js, visible)
  end

  # @rbs return: Puppeteer::Frame? -- Frame that owns this element
  def content_frame
    node_info = @remote_object.node_info(@client)
    frame_id = node_info['node']['frameId']
    if frame_id.is_a?(String)
      @frame_manager.frame(frame_id)
    else
      nil
    end
  end

  class ScrollIntoViewError < Puppeteer::Error; end

  # @rbs return: void -- No return value
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
    error = evaluate(js) # returns String or false
    if error
      raise ScrollIntoViewError.new(error)
    end
    begin
      @remote_object.scroll_into_view_if_needed(@client)
    rescue
      # Fallback to Element.scrollIntoView if DOM.scrollIntoViewIfNeeded is not supported
      js = <<~JAVASCRIPT
        async (element, pageJavascriptEnabled) => {
          const visibleRatio = async () => {
            return await new Promise(resolve => {
              const observer = new IntersectionObserver(entries => {
                resolve(entries[0].intersectionRatio);
                observer.disconnect();
              });
              observer.observe(element);
            });
          };
          if (!pageJavascriptEnabled || (await visibleRatio()) !== 1.0) {
            element.scrollIntoView({
              block: 'center',
              inline: 'center',
              // @ts-expect-error Chrome still supports behavior: instant but
              // it's not in the spec so TS shouts We don't want to make this
              // breaking change in Puppeteer yet so we'll ignore the line.
              behavior: 'instant',
            });
          }
        }
      JAVASCRIPT
      evaluate(js, page.javascript_enabled?)
    end

    # clickpoint is often calculated before scrolling is completed.
    # So, just sleep about 10 frames
    sleep 0.16
  end

  class ElementNotVisibleError < Puppeteer::Error
    def initialize
      super("Node is either not visible or not an HTMLElement")
    end
  end

  class ElementNotClickableError < Puppeteer::Error
    def initialize
      super("Node is either not clickable or not an HTMLElement")
    end
  end

  # @rbs quad: Array[Point] -- Quad points
  # @rbs offset: Point -- Offset to apply
  # @rbs return: Array[Point] -- Offset quad points
  private def apply_offsets_to_quad(quad, offset)
    quad.map { |part| part + offset }
  end

  # @rbs frame: Puppeteer::Frame -- Frame to calculate offsets for
  # @rbs return: Point -- Calculated offset
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

  # @rbs offset: Puppeteer::ElementHandle::Offset | Hash[Symbol, Numeric] | nil -- Click offset
  # @rbs return: Puppeteer::ElementHandle::Point -- Clickable point
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
    # Prefer cssLayoutViewport when available.
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

  # @rbs quad: Array[Numeric] -- Protocol quad coordinates
  # @rbs return: Array[Point] -- Point array
  private def from_protocol_quad(quad)
    quad.each_slice(2).map do |x, y|
      Point.new(x: x, y: y)
    end
  end

  private def intersect_quad_with_viewport(quad, width, height)
    quad.map do |point|
      Point.new(
        x: [[point.x, 0].max, width].min,
        y: [[point.y, 0].max, height].min,
      )
    end
  end

  # @rbs return: void -- No return value
  def hover
    scroll_into_view_if_needed
    point = clickable_point
    @page.mouse.move(point.x, point.y)
  end

  # @rbs delay: Numeric? -- Delay between down and up (ms)
  # @rbs button: String? -- Mouse button
  # @rbs click_count: Integer? -- Click count to report
  # @rbs offset: Puppeteer::ElementHandle::Offset | Hash[Symbol, Numeric] | nil -- Click offset
  # @rbs return: void -- No return value
  def click(delay: nil, button: nil, click_count: nil, offset: nil)
    scroll_into_view_if_needed
    point = clickable_point(offset)
    @page.mouse.click(point.x, point.y, delay: delay, button: button, click_count: click_count)
  end

  define_async_method :async_click

  # @rbs return: Puppeteer::TouchHandle -- Touch handle
  def touch_start
    scroll_into_view_if_needed
    point = clickable_point
    @page.touchscreen.touch_start(point.x, point.y)
  end

  define_async_method :async_touch_start

  # @rbs touch: Puppeteer::TouchHandle? -- Optional touch handle
  # @rbs return: void -- No return value
  def touch_move(touch = nil)
    scroll_into_view_if_needed
    point = clickable_point
    if touch
      touch.move(point.x, point.y)
    else
      @page.touchscreen.touch_move(point.x, point.y)
    end
  end

  define_async_method :async_touch_move

  # @rbs return: void -- No return value
  def touch_end
    scroll_into_view_if_needed
    @page.touchscreen.touch_end
  end

  define_async_method :async_touch_end

  class DragInterceptionNotEnabledError < Puppeteer::Error
    def initialize
      super('Drag Interception is not enabled!')
    end
  end

  # @rbs x: Numeric -- Drag end X coordinate
  # @rbs y: Numeric -- Drag end Y coordinate
  # @rbs return: void -- No return value
  def drag(x:, y:)
    unless @page.drag_interception_enabled?
      raise DragInterceptionNotEnabledError.new
    end
    scroll_into_view_if_needed
    start = clickable_point
    @page.mouse.drag(start, Point.new(x: x, y: y))
  end

  # @rbs data: Hash[String, untyped] -- Drag data payload
  # @rbs return: void -- No return value
  def drag_enter(data)
    scroll_into_view_if_needed
    target = clickable_point
    @page.mouse.drag_enter(target, data)
  end

  # @rbs data: Hash[String, untyped] -- Drag data payload
  # @rbs return: void -- No return value
  def drag_over(data)
    scroll_into_view_if_needed
    target = clickable_point
    @page.mouse.drag_over(target, data)
  end

  # @rbs data: Hash[String, untyped] -- Drag data payload
  # @rbs return: void -- No return value
  def drop(data)
    scroll_into_view_if_needed
    target = clickable_point
    @page.mouse.drop(target, data)
  end

  # @rbs target: Puppeteer::ElementHandle -- Drop target element
  # @rbs delay: Numeric? -- Delay before dropping (ms)
  # @rbs return: void -- No return value
  def drag_and_drop(target, delay: nil)
    scroll_into_view_if_needed
    start_point = clickable_point
    target_point = target.clickable_point
    @page.mouse.drag_and_drop(start_point, target_point, delay: delay)
  end

  # @rbs values: Array[String] -- Option values to select
  # @rbs return: Array[String] -- Selected values
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

  # @rbs file_paths: Array[String] -- Files to upload
  # @rbs return: void -- No return value
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
      evaluate(fn)
    else
      @remote_object.set_file_input_files(@client, file_paths.map { |path| File.expand_path(path) }, backend_node_id)
    end
  end

  # @rbs block: Proc? -- Optional block for Object#tap usage
  # @rbs return: Puppeteer::ElementHandle | nil -- Element handle or nil
  def tap(&block)
    return super(&block) if block

    scroll_into_view_if_needed
    point = clickable_point
    @page.touchscreen.tap(point.x, point.y)
  end

  define_async_method :async_tap

  # @rbs return: void -- No return value
  def focus
    evaluate('element => element.focus()')
  end

  define_async_method :async_focus

  # @rbs text: String -- Text to type
  # @rbs delay: Numeric? -- Delay between key presses (ms)
  # @rbs return: void -- No return value
  def type_text(text, delay: nil)
    focus
    @page.keyboard.type_text(text, delay: delay)
  end

  define_async_method :async_type_text

  # @rbs key: String -- Key name
  # @rbs delay: Numeric? -- Delay between key events (ms)
  # @rbs text: String? -- Text to input
  # @rbs return: void -- No return value
  def press(key, delay: nil, text: nil)
    focus
    @page.keyboard.press(key, delay: delay)
  end

  define_async_method :async_press

  # @rbs return: Puppeteer::ElementHandle::BoundingBox? -- Bounding box or nil
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

  # @rbs return: Puppeteer::ElementHandle::BoxModel? -- Box model or nil
  def box_model
    if_present(@remote_object.box_model(@client)) do |result|
      BoxModel.new(result['model'], offset: oopif_offsets(@frame))
    end
  end

  # @rbs type: String? -- Image format
  # @rbs path: String? -- File path to save
  # @rbs full_page: bool? -- Capture full page
  # @rbs clip: Hash[Symbol, Numeric]? -- Clip rectangle
  # @rbs quality: Integer? -- JPEG quality
  # @rbs omit_background: bool? -- Omit background for PNG
  # @rbs encoding: String? -- Encoding (base64 or binary)
  # @rbs capture_beyond_viewport: bool? -- Capture beyond viewport
  # @rbs from_surface: bool? -- Capture from surface
  # @rbs return: String -- Screenshot data
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
    if needs_viewport_reset && viewport
      @page.viewport = viewport
    end
  end

  private def query_handler_manager
    Puppeteer::QueryHandlerManager.instance
  end

  # `$()` in JavaScript.
  # @rbs selector: String -- CSS selector
  # @rbs return: Puppeteer::ElementHandle? -- Matching element or nil
  def query_selector(selector)
    query_handler_manager.detect_query_handler(selector).query_one(self)
  end
  alias_method :S, :query_selector

  # `$$()` in JavaScript.
  # @rbs selector: String -- CSS selector
  # @rbs return: Array[Puppeteer::ElementHandle] -- Matching elements
  def query_selector_all(selector)
    query_handler_manager.detect_query_handler(selector).query_all(self)
  end
  alias_method :SS, :query_selector_all

  class ElementNotFoundError < Puppeteer::Error
    # @rbs selector: String -- CSS selector
    def initialize(selector)
      super("failed to find element matching selector \"#{selector}\"")
    end
  end

  # `$eval()` in JavaScript.
  # @rbs selector: String -- CSS selector
  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs return: untyped -- Evaluation result
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
  # @rbs selector: String -- CSS selector
  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs return: untyped -- Evaluation result
  def eval_on_selector_all(selector, page_function, *args)
    handles = query_handler_manager.detect_query_handler(selector).query_all_array(self)
    result = handles.evaluate(page_function, *args)
    handles.dispose

    result
  end
  alias_method :SSeval, :eval_on_selector_all

  define_async_method :async_eval_on_selector_all

  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @rbs expression: String -- XPath expression
  # @rbs return: Array[Puppeteer::ElementHandle] -- Matching elements
  def Sx(expression)
    param_xpath =
      if expression.start_with?('//')
        ".#{expression}"
      else
        expression
      end

    query_selector_all("xpath/#{param_xpath}")
  end

  define_async_method :async_Sx

  # in JS, #isIntersectingViewport.
  # @rbs threshold: Numeric? -- Visibility threshold
  # @rbs return: bool -- Whether element intersects viewport
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

  private def compute_quad_area(quad)
    # Compute sum of all directed areas of adjacent triangles
    # https://en.wikipedia.org/wiki/Polygon#Simple_polygons
    quad.zip(quad.rotate).map { |p1, p2| (p1.x * p2.y - p2.x * p1.y) / 2 }.reduce(:+).abs
  end

  # used in AriaQueryHandler
  # @rbs accessible_name: String? -- Accessible name filter
  # @rbs role: String? -- Accessible role filter
  # @rbs return: Hash[String, untyped] -- Accessibility tree result
  def query_ax_tree(accessible_name: nil, role: nil)
    @remote_object.query_ax_tree(@client,
      accessible_name: accessible_name, role: role)
  end
end
