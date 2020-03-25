class Puppeteer::ElementHandle < Puppeteer::JSHandle
  # /**
  #  * @param {!Puppeteer.ExecutionContext} context
  #  * @param {!Puppeteer.CDPSession} client
  #  * @param {!Protocol.Runtime.RemoteObject} remoteObject
  #  * @param {!Puppeteer.Page} page
  #  * @param {!Puppeteer.FrameManager} frameManager
  #  */
  # constructor(context, client, remoteObject, page, frameManager) {
  #   super(context, client, remoteObject);
  #   this._client = client;
  #   this._remoteObject = remoteObject;
  #   this._page = page;
  #   this._frameManager = frameManager;
  #   this._disposed = false;
  # }

  def as_element
    self
  end

  #   /**
  #   * @return {!Promise<?Puppeteer.Frame>}
  #   */
  #  async contentFrame() {
  #    const nodeInfo = await this._client.send('DOM.describeNode', {
  #      objectId: this._remoteObject.objectId
  #    });
  #    if (typeof nodeInfo.node.frameId !== 'string')
  #      return null;
  #    return this._frameManager.frame(nodeInfo.node.frameId);
  #  }

  #  async _scrollIntoViewIfNeeded() {
  #    const error = await this.evaluate(async(element, pageJavascriptEnabled) => {
  #      if (!element.isConnected)
  #        return 'Node is detached from document';
  #      if (element.nodeType !== Node.ELEMENT_NODE)
  #        return 'Node is not of type HTMLElement';
  #      // force-scroll if page's javascript is disabled.
  #      if (!pageJavascriptEnabled) {
  #        element.scrollIntoView({block: 'center', inline: 'center', behavior: 'instant'});
  #        return false;
  #      }
  #      const visibleRatio = await new Promise(resolve => {
  #        const observer = new IntersectionObserver(entries => {
  #          resolve(entries[0].intersectionRatio);
  #          observer.disconnect();
  #        });
  #        observer.observe(element);
  #      });
  #      if (visibleRatio !== 1.0)
  #        element.scrollIntoView({block: 'center', inline: 'center', behavior: 'instant'});
  #      return false;
  #    }, this._page._javascriptEnabled);
  #    if (error)
  #      throw new Error(error);
  #  }

  #  /**
  #   * @return {!Promise<!{x: number, y: number}>}
  #   */
  #  async _clickablePoint() {
  #    const [result, layoutMetrics] = await Promise.all([
  #      this._client.send('DOM.getContentQuads', {
  #        objectId: this._remoteObject.objectId
  #      }).catch(debugError),
  #      this._client.send('Page.getLayoutMetrics'),
  #    ]);
  #    if (!result || !result.quads.length)
  #      throw new Error('Node is either not visible or not an HTMLElement');
  #    // Filter out quads that have too small area to click into.
  #    const {clientWidth, clientHeight} = layoutMetrics.layoutViewport;
  #    const quads = result.quads.map(quad => this._fromProtocolQuad(quad)).map(quad => this._intersectQuadWithViewport(quad, clientWidth, clientHeight)).filter(quad => computeQuadArea(quad) > 1);
  #    if (!quads.length)
  #      throw new Error('Node is either not visible or not an HTMLElement');
  #    // Return the middle point of the first quad.
  #    const quad = quads[0];
  #    let x = 0;
  #    let y = 0;
  #    for (const point of quad) {
  #      x += point.x;
  #      y += point.y;
  #    }
  #    return {
  #      x: x / 4,
  #      y: y / 4
  #    };
  #  }

  #  /**
  #   * @return {!Promise<void|Protocol.DOM.getBoxModelReturnValue>}
  #   */
  #  _getBoxModel() {
  #    return this._client.send('DOM.getBoxModel', {
  #      objectId: this._remoteObject.objectId
  #    }).catch(error => debugError(error));
  #  }

  #  /**
  #   * @param {!Array<number>} quad
  #   * @return {!Array<{x: number, y: number}>}
  #   */
  #  _fromProtocolQuad(quad) {
  #    return [
  #      {x: quad[0], y: quad[1]},
  #      {x: quad[2], y: quad[3]},
  #      {x: quad[4], y: quad[5]},
  #      {x: quad[6], y: quad[7]}
  #    ];
  #  }

  #  /**
  #   * @param {!Array<{x: number, y: number}>} quad
  #   * @param {number} width
  #   * @param {number} height
  #   * @return {!Array<{x: number, y: number}>}
  #   */
  #  _intersectQuadWithViewport(quad, width, height) {
  #    return quad.map(point => ({
  #      x: Math.min(Math.max(point.x, 0), width),
  #      y: Math.min(Math.max(point.y, 0), height),
  #    }));
  #  }

  #  async hover() {
  #    await this._scrollIntoViewIfNeeded();
  #    const {x, y} = await this._clickablePoint();
  #    await this._page.mouse.move(x, y);
  #  }

  #  /**
  #   * @param {!{delay?: number, button?: "left"|"right"|"middle", clickCount?: number}=} options
  #   */
  #  async click(options) {
  #    await this._scrollIntoViewIfNeeded();
  #    const {x, y} = await this._clickablePoint();
  #    await this._page.mouse.click(x, y, options);
  #  }

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

  #  async tap() {
  #    await this._scrollIntoViewIfNeeded();
  #    const {x, y} = await this._clickablePoint();
  #    await this._page.touchscreen.tap(x, y);
  #  }

  #  async focus() {
  #    await this.evaluate(element => element.focus());
  #  }

  #  /**
  #   * @param {string} text
  #   * @param {{delay: (number|undefined)}=} options
  #   */
  #  async type(text, options) {
  #    await this.focus();
  #    await this._page.keyboard.type(text, options);
  #  }

  #  /**
  #   * @param {string} key
  #   * @param {!{delay?: number, text?: string}=} options
  #   */
  #  async press(key, options) {
  #    await this.focus();
  #    await this._page.keyboard.press(key, options);
  #  }

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

  #  /**
  #   * @param {string} selector
  #   * @return {!Promise<?ElementHandle>}
  #   */
  #  async $(selector) {
  #    const handle = await this.evaluateHandle(
  #        (element, selector) => element.querySelector(selector),
  #        selector
  #    );
  #    const element = handle.asElement();
  #    if (element)
  #      return element;
  #    await handle.dispose();
  #    return null;
  #  }

  #  /**
  #   * @param {string} selector
  #   * @return {!Promise<!Array<!ElementHandle>>}
  #   */
  #  async $$(selector) {
  #    const arrayHandle = await this.evaluateHandle(
  #        (element, selector) => element.querySelectorAll(selector),
  #        selector
  #    );
  #    const properties = await arrayHandle.getProperties();
  #    await arrayHandle.dispose();
  #    const result = [];
  #    for (const property of properties.values()) {
  #      const elementHandle = property.asElement();
  #      if (elementHandle)
  #        result.push(elementHandle);
  #    }
  #    return result;
  #  }

  #  /**
  #   * @param {string} selector
  #   * @param {Function|String} pageFunction
  #   * @param {!Array<*>} args
  #   * @return {!Promise<(!Object|undefined)>}
  #   */
  #  async $eval(selector, pageFunction, ...args) {
  #    const elementHandle = await this.$(selector);
  #    if (!elementHandle)
  #      throw new Error(`Error: failed to find element matching selector "${selector}"`);
  #    const result = await elementHandle.evaluate(pageFunction, ...args);
  #    await elementHandle.dispose();
  #    return result;
  #  }

  #  /**
  #   * @param {string} selector
  #   * @param {Function|String} pageFunction
  #   * @param {!Array<*>} args
  #   * @return {!Promise<(!Object|undefined)>}
  #   */
  #  async $$eval(selector, pageFunction, ...args) {
  #    const arrayHandle = await this.evaluateHandle(
  #        (element, selector) => Array.from(element.querySelectorAll(selector)),
  #        selector
  #    );

  #    const result = await arrayHandle.evaluate(pageFunction, ...args);
  #    await arrayHandle.dispose();
  #    return result;
  #  }

  #  /**
  #   * @param {string} expression
  #   * @return {!Promise<!Array<!ElementHandle>>}
  #   */
  #  async $x(expression) {
  #    const arrayHandle = await this.evaluateHandle(
  #        (element, expression) => {
  #          const document = element.ownerDocument || element;
  #          const iterator = document.evaluate(expression, element, null, XPathResult.ORDERED_NODE_ITERATOR_TYPE);
  #          const array = [];
  #          let item;
  #          while ((item = iterator.iterateNext()))
  #            array.push(item);
  #          return array;
  #        },
  #        expression
  #    );
  #    const properties = await arrayHandle.getProperties();
  #    await arrayHandle.dispose();
  #    const result = [];
  #    for (const property of properties.values()) {
  #      const elementHandle = property.asElement();
  #      if (elementHandle)
  #        result.push(elementHandle);
  #    }
  #    return result;
  #  }

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
end
