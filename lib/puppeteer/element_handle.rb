class Puppeteer::ElementHandle < Puppeteer::JSHandle
  include Puppeteer::IfPresent
  using Puppeteer::AsyncAwaitBehavior

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
    node_info = @remote_object.node_info
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

        element.scrollIntoViewIfNeeded({block: 'center', inline: 'center', behavior: 'instant'});
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

  class Point
    def initialize(x:, y:)
      @x = x
      @y = y
    end

    def +(other)
      Point.new(
        x: @x + other.x,
        y: @y + other.y,
      )
    end

    def /(num)
      Point.new(
        x: @x / num,
        y: @y / num,
      )
    end

    attr_reader :x, :y
  end

  class ElementNotVisibleError < StandardError
    def initialize
      super("Node is either not visible or not an HTMLElement")
    end
  end

  def clickable_point
    result = @remote_object.content_quads(@client)
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

  #  /**
  #   * @return {!Promise<void|Protocol.DOM.getBoxModelReturnValue>}
  #   */
  #  _getBoxModel() {
  #    return this._client.send('DOM.getBoxModel', {
  #      objectId: this._remoteObject.objectId
  #    }).catch(error => debugError(error));
  #  }

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

  #  async hover() {
  #    await this._scrollIntoViewIfNeeded();
  #    const {x, y} = await this._clickablePoint();
  #    await this._page.mouse.move(x, y);
  #  }

  # @param delay [Number]
  # @param button [String] "left"|"right"|"middle"
  # @param click_count [Number]
  def click(delay: nil, button: nil, click_count: nil)
    scroll_into_view_if_needed
    point = clickable_point
    @page.mouse.click(point.x, point.y, delay: delay, button: button, click_count: click_count)
  end

  #  /**
  #   * @param {!Array<string>} values
  #   * @return {!Promise<!Array<string>>}
  #   */
  #  async select(...values) {
  #    for (const value of values)
  #      assert(helper.isString(value), 'Values must be strings. Found value "' + value + '" of type "' + (typeof value) + '"');
  #    return this.evaluate((element, values) => {
  #      if (element.nodeName.toLowerCase() !== 'select')
  #        throw new Error('Element is not a <select> element.');

  #      const options = Array.from(element.options);
  #      element.value = undefined;
  #      for (const option of options) {
  #        option.selected = values.includes(option.value);
  #        if (option.selected && !element.multiple)
  #          break;
  #      }
  #      element.dispatchEvent(new Event('input', { bubbles: true }));
  #      element.dispatchEvent(new Event('change', { bubbles: true }));
  #      return options.filter(option => option.selected).map(option => option.value);
  #    }, values);
  #  }

  #  /**
  #   * @param {!Array<string>} filePaths
  #   */
  #  async uploadFile(...filePaths) {
  #    const isMultiple = await this.evaluate(element => element.multiple);
  #    assert(filePaths.length <= 1 || isMultiple, 'Multiple file uploads only work with <input type=file multiple>');
  #    // These imports are only needed for `uploadFile`, so keep them
  #    // scoped here to avoid paying the cost unnecessarily.
  #    const path = require('path');
  #    const mime = require('mime-types');
  #    const fs = require('fs');
  #    const readFileAsync = helper.promisify(fs.readFile);

  #    const promises = filePaths.map(filePath => readFileAsync(filePath));
  #    const files = [];
  #    for (let i = 0; i < filePaths.length; i++) {
  #      const buffer = await promises[i];
  #      const filePath = path.basename(filePaths[i]);
  #      const file = {
  #        name: filePath,
  #        content: buffer.toString('base64'),
  #        mimeType: mime.lookup(filePath),
  #      };
  #      files.push(file);
  #    }
  #    await this.evaluateHandle(async(element, files) => {
  #      const dt = new DataTransfer();
  #      for (const item of files) {
  #        const response = await fetch(`data:${item.mimeType};base64,${item.content}`);
  #        const file = new File([await response.blob()], item.name);
  #        dt.items.add(file);
  #      }
  #      element.files = dt.files;
  #      element.dispatchEvent(new Event('input', { bubbles: true }));
  #      element.dispatchEvent(new Event('change', { bubbles: true }));
  #    }, files);
  #  }

  def tap
    scroll_into_view_if_needed
    point = clickable_point
    @page.touchscreen.tap(point.x, point.y)
  end


  def focus
    evaluate('element => element.focus()')
  end

  async def async_focus
    focus
  end

  # @param text [String]
  # @param delay [number|nil]
  def type_text(text, delay: nil)
    focus
    @page.keyboard.type_text(text, delay: delay)
  end

  # @param text [String]
  # @param delay [number|nil]
  # @return [Future]
  async def async_type_text(text, delay: nil)
    type_text(text, delay: delay)
  end

  # @param key [String]
  # @param delay [number|nil]
  def press(key, delay: nil)
    focus
    @page.keyboard.press(key, delay: delay)
  end

  # @param key [String]
  # @param delay [number|nil]
  # @return [Future]
  async def async_press(key, delay: nil)
    press(key, delay: delay)
  end

  #  /**
  #   * @return {!Promise<?{x: number, y: number, width: number, height: number}>}
  #   */
  #  async boundingBox() {
  #    const result = await this._getBoxModel();

  #    if (!result)
  #      return null;

  #    const quad = result.model.border;
  #    const x = Math.min(quad[0], quad[2], quad[4], quad[6]);
  #    const y = Math.min(quad[1], quad[3], quad[5], quad[7]);
  #    const width = Math.max(quad[0], quad[2], quad[4], quad[6]) - x;
  #    const height = Math.max(quad[1], quad[3], quad[5], quad[7]) - y;

  #    return {x, y, width, height};
  #  }

  #  /**
  #   * @return {!Promise<?BoxModel>}
  #   */
  #  async boxModel() {
  #    const result = await this._getBoxModel();

  #    if (!result)
  #      return null;

  #    const {content, padding, border, margin, width, height} = result.model;
  #    return {
  #      content: this._fromProtocolQuad(content),
  #      padding: this._fromProtocolQuad(padding),
  #      border: this._fromProtocolQuad(border),
  #      margin: this._fromProtocolQuad(margin),
  #      width,
  #      height
  #    };
  #  }

  #  /**
  #   *
  #   * @param {!Object=} options
  #   * @returns {!Promise<string|!Buffer>}
  #   */
  #  async screenshot(options = {}) {
  #    let needsViewportReset = false;

  #    let boundingBox = await this.boundingBox();
  #    assert(boundingBox, 'Node is either not visible or not an HTMLElement');

  #    const viewport = this._page.viewport();

  #    if (viewport && (boundingBox.width > viewport.width || boundingBox.height > viewport.height)) {
  #      const newViewport = {
  #        width: Math.max(viewport.width, Math.ceil(boundingBox.width)),
  #        height: Math.max(viewport.height, Math.ceil(boundingBox.height)),
  #      };
  #      await this._page.setViewport(Object.assign({}, viewport, newViewport));

  #      needsViewportReset = true;
  #    }

  #    await this._scrollIntoViewIfNeeded();

  #    boundingBox = await this.boundingBox();
  #    assert(boundingBox, 'Node is either not visible or not an HTMLElement');
  #    assert(boundingBox.width !== 0, 'Node has 0 width.');
  #    assert(boundingBox.height !== 0, 'Node has 0 height.');

  #    const { layoutViewport: { pageX, pageY } } = await this._client.send('Page.getLayoutMetrics');

  #    const clip = Object.assign({}, boundingBox);
  #    clip.x += pageX;
  #    clip.y += pageY;

  #    const imageData = await this._page.screenshot(Object.assign({}, {
  #      clip
  #    }, options));

  #    if (needsViewportReset)
  #      await this._page.setViewport(viewport);

  #    return imageData;
  #  }

  # `$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param selector [String]
  def S(selector)
    handle = evaluate_handle(
      '(element, selector) => element.querySelector(selector)',
      selector,
    )
    element = handle.as_element

    if element
      return element
    end
    handle.dispose
    nil
  end

  # `$$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param selector [String]
  def SS(selector)
    handles = evaluate_handle(
      '(element, selector) => element.querySelectorAll(selector)',
      selector,
    )
    properties = handles.properties
    handles.dispose
    properties.values.map(&:as_element).compact
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

  # `$$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param selector [String]
  # @param page_function [String]
  # @return [Object]
  def SSeval(selector, page_function, *args)
    handles = evaluate_handle(
      '(element, selector) => Array.from(element.querySelectorAll(selector))',
      selector,
    )
    result = handles.evaluate(page_function, *args)
    handles.dispose

    result
  end

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

  #  /**
  #   * @returns {!Promise<boolean>}
  #   */
  #  isIntersectingViewport() {
  #    return this.evaluate(async element => {
  #      const visibleRatio = await new Promise(resolve => {
  #        const observer = new IntersectionObserver(entries => {
  #          resolve(entries[0].intersectionRatio);
  #          observer.disconnect();
  #        });
  #        observer.observe(element);
  #      });
  #      return visibleRatio > 0;
  #    });
  #  }

  # @param quad [Array<Point>]
  private def compute_quad_area(quad)
    # Compute sum of all directed areas of adjacent triangles
    # https://en.wikipedia.org/wiki/Polygon#Simple_polygons
    quad.zip(quad.rotate).map { |p1, p2| (p1.x * p2.y - p2.x * p1.y) / 2 }.reduce(:+).abs
  end
end
