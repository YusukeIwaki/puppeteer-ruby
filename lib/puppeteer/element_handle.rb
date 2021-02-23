require_relative './element_handle/bounding_box'
require_relative './element_handle/box_model'
require_relative './element_handle/point'

class Puppeteer::ElementHandle < Puppeteer::JSHandle
  include Puppeteer::DebugPrint
  include Puppeteer::IfPresent
  using Puppeteer::DefineAsyncMethod

  # @param context [Puppeteer::ExecutionContext]
  # @param client [Puppeteer::CDPSession]
  # @param remote_object [Puppeteer::RemoteObject]
  # @param page [Puppeteer::Page]
  # @param frame_manager [Puppeteer::FrameManager]
  def initialize(context:, client:, remote_object:, page:, frame_manager:)
    super(context: context, client: client, remote_object: remote_object)
    @page = page
    @frame_manager = frame_manager
    @disposed = false
  end

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
      async(element, pageJavascriptEnabled) => {
        if (!element.isConnected)
          return 'Node is detached from document';
        if (element.nodeType !== Node.ELEMENT_NODE)
          return 'Node is not of type HTMLElement';

        if (element.scrollIntoViewIfNeeded) {
          element.scrollIntoViewIfNeeded({block: 'center', inline: 'center', behavior: 'instant'});
        } else {
          // force-scroll if page's javascript is disabled.
          if (!pageJavascriptEnabled) {
            element.scrollIntoView({block: 'center', inline: 'center', behavior: 'instant'});
            return false;
          }
          const visibleRatio = await new Promise(resolve => {
            const observer = new IntersectionObserver(entries => {
              resolve(entries[0].intersectionRatio);
              observer.disconnect();
            });
            observer.observe(element);
          });
          if (visibleRatio !== 1.0)
            element.scrollIntoView({block: 'center', inline: 'center', behavior: 'instant'});
        }
        return false;
      }
    JAVASCRIPT
    error = evaluate(js, @page.javascript_enabled) # returns String or false
    if error
      raise ScrollIntoViewError.new(error)
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

  def clickable_point
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
    layout_metrics = @client.send_message('Page.getLayoutMetrics')
    client_width = layout_metrics["layoutViewport"]["clientWidth"]
    client_height = layout_metrics["layoutViewport"]["clientHeight"]

    quads = result["quads"].
              map { |quad| from_protocol_quad(quad) }.
              map { |quad| intersect_quad_with_viewport(quad, client_width, client_height) }.
              select { |quad| compute_quad_area(quad) > 1 }
    if quads.empty?
      raise ElementNotVisibleError.new
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
  def click(delay: nil, button: nil, click_count: nil)
    scroll_into_view_if_needed
    point = clickable_point
    @page.mouse.click(point.x, point.y, delay: delay, button: button, click_count: click_count)
  end

  define_async_method :async_click

  # @return [Array<String>]
  def select(*values)
    if nonstring = values.find { |value| !value.is_a?(String) }
      raise ArgumentError.new("Values must be strings. Found value \"#{nonstring}\" of type \"#{nonstring.class}\"")
    end

    fn = <<~JAVASCRIPT
    (element, values) => {
      if (element.nodeName.toLowerCase() !== 'select') {
        throw new Error('Element is not a <select> element.');
      }

      const options = Array.from(element.options);
      element.value = undefined;
      for (const option of options) {
        option.selected = values.includes(option.value);
        if (option.selected && !element.multiple) {
          break;
        }
      }
      element.dispatchEvent(new Event('input', { bubbles: true }));
      element.dispatchEvent(new Event('change', { bubbles: true }));
      return options.filter(option => option.selected).map(option => option.value);
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

    if error_path = file_paths.find { |file_path| !File.exist?(file_path) }
      raise ArgmentError.new("#{error_path} does not exist or is not readable")
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
      await this.evaluate(fn)
    else
      @remote_object.set_file_input_files(@client, file_paths, backend_node_id)
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
      quads = result_model.border

      x = quads.map(&:x).min
      y = quads.map(&:y).min
      BoundingBox.new(
        x: x,
        y: y,
        width: quads.map(&:x).max - x,
        height: quads.map(&:y).max - y,
      )
    end
  end

  # @return [BoxModel|nil]
  def box_model
    if_present(@remote_object.box_model(@client)) do |result|
      BoxModel.new(result['model'])
    end
  end

  def screenshot(options = {})
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

    clip = {
      x: page_x + box.x,
      y: page_y + box.y,
      width: box.width,
      height: box.height,
    }

    @page.screenshot({ clip: clip }.merge(options))
  ensure
    if needs_viewport_reset
      @page.viewport = viewport
    end
  end

  private def query_handler_manager
    Puppeteer::QueryHandlerManager.instance
  end

  # `$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param selector [String]
  def S(selector)
    query_handler_manager.detect_query_handler(selector).query_one(self)
  end

  # `$$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param selector [String]
  def SS(selector)
    query_handler_manager.detect_query_handler(selector).query_all(self)
  end

  class ElementNotFoundError < StandardError
    def initialize(selector)
      super("failed to find element matching selector \"#{selector}\"")
    end
  end

  # `$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param selector [String]
  # @param page_function [String]
  # @return [Object]
  def Seval(selector, page_function, *args)
    element_handle = S(selector)
    unless element_handle
      raise ElementNotFoundError.new(selector)
    end
    result = element_handle.evaluate(page_function, *args)
    element_handle.dispose

    result
  end

  define_async_method :async_Seval

  # `$$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param selector [String]
  # @param page_function [String]
  # @return [Object]
  def SSeval(selector, page_function, *args)
    handles = query_handler_manager.detect_query_handler(selector).query_all_array(self)
    result = handles.evaluate(page_function, *args)
    handles.dispose

    result
  end

  define_async_method :async_SSeval

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
  # @return [Boolean]
  def intersecting_viewport?
    js = <<~JAVASCRIPT
    async element => {
      const visibleRatio = await new Promise(resolve => {
        const observer = new IntersectionObserver(entries => {
          resolve(entries[0].intersectionRatio);
          observer.disconnect();
        });
        observer.observe(element);
      });
      return visibleRatio > 0;
    }
    JAVASCRIPT

    evaluate(js)
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
