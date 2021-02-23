require 'thread'

# https://github.com/puppeteer/puppeteer/blob/master/src/DOMWorld.js
class Puppeteer::DOMWorld
  using Puppeteer::DefineAsyncMethod

  # @param {!Puppeteer.FrameManager} frameManager
  # @param {!Puppeteer.Frame} frame
  # @param {!Puppeteer.TimeoutSettings} timeoutSettings
  def initialize(frame_manager, frame, timeout_settings)
    @frame_manager = frame_manager
    @frame = frame
    @timeout_settings = timeout_settings
    @context_promise = resolvable_future
    @wait_tasks = Set.new
    @detached = false
  end

  attr_reader :frame

  # only used in Puppeteer::WaitTask#initialize
  def _wait_tasks
    @wait_tasks
  end

  # @param context [Puppeteer::ExecutionContext]
  def context=(context)
    if context
      unless @context_promise.resolved?
        @context_promise.fulfill(context)
      end
      @wait_tasks.each(&:async_rerun)
    else
      raise ArgumentError.new("context should now be nil. Use #delete_context for clearing document.")
    end
  end

  def delete_context(execution_context_id)
    @document = nil
    @context_promise = resolvable_future
  end

  def has_context?
    @context_promise.resolved?
  end

  def detach
    @detached = true
    @wait_tasks.each do |wait_task|
      wait_task.terminate(Puppeteer::WaitTask::TerminatedError.new('waitForFunction failed: frame got detached.'))
    end
  end

  class DetachedError < StandardError; end

  # @return {!Promise<!Puppeteer.ExecutionContext>}
  def execution_context
    if @detached
      raise DetachedError.new("Execution Context is not available in detached frame \"#{@frame.url}\" (are you trying to evaluate?)")
    end
    @context_promise.value!
  end

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<!Puppeteer.JSHandle>}
  def evaluate_handle(page_function, *args)
    execution_context.evaluate_handle(page_function, *args)
  end

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<*>}
  def evaluate(page_function, *args)
    execution_context.evaluate(page_function, *args)
  end

  # `$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @return {!Promise<?Puppeteer.ElementHandle>}
  def S(selector)
    document.S(selector)
  end

  private def evaluate_document
    # sometimes execution_context.evaluate_handle('document') returns null object.
    # D, [2020-04-24T02:17:51.023631 #220] DEBUG -- : RECV << {"id"=>20, "result"=>{"result"=>{"type"=>"object", "subtype"=>"null", "value"=>nil}}, "sessionId"=>"78E9CF1E14D81294E320E7C20E5CDE06"}
    # retry if so.
    Timeout.timeout(3) do
      loop do
        handle = execution_context.evaluate_handle('document')
        return handle if handle.is_a?(Puppeteer::ElementHandle)
      end
    end
  rescue Timeout::Error
    raise 'Bug of puppeteer-ruby...'
  end

  private def document
    @document ||= evaluate_document.as_element
  end

  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} expression
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def Sx(expression)
    document.Sx(expression)
  end

  # `$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def Seval(selector, page_function, *args)
    document.Seval(selector, page_function, *args)
  end

  # `$$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def SSeval(selector, page_function, *args)
    document.SSeval(selector, page_function, *args)
  end

  # `$$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def SS(selector)
    document.SS(selector)
  end

  # @return [String]
  def content
    evaluate(<<-JAVASCRIPT)
    () => {
      let retVal = '';
      if (document.doctype)
        retVal = new XMLSerializer().serializeToString(document.doctype);
      if (document.documentElement)
        retVal += document.documentElement.outerHTML;
      return retVal;
    }
    JAVASCRIPT
  end

  # @param html [String]
  # @param timeout [Integer]
  # @param wait_until [String|Array<String>]
  def set_content(html, timeout: nil, wait_until: nil)
    option_wait_until = [wait_until || 'load'].flatten
    option_timeout = timeout || @timeout_settings.navigation_timeout

    # We rely upon the fact that document.open() will reset frame lifecycle with "init"
    # lifecycle event. @see https://crrev.com/608658
    js = <<-JAVASCRIPT
    (html) => {
      document.open();
      document.write(html);
      document.close();
    }
    JAVASCRIPT
    evaluate(js, html)

    watcher = Puppeteer::LifecycleWatcher.new(@frame_manager, @frame, option_wait_until, option_timeout)
    begin
      await_any(
        watcher.timeout_or_termination_promise,
        watcher.lifecycle_promise,
      )
    ensure
      watcher.dispose
    end
  end

  # /**
  #  * @param {!{url?: string, path?: string, content?: string, type?: string}} options
  #  * @return {!Promise<!Puppeteer.ElementHandle>}
  #  */
  # async addScriptTag(options) {
  #   const {
  #     url = null,
  #     path = null,
  #     content = null,
  #     type = ''
  #   } = options;
  #   if (url !== null) {
  #     try {
  #       const context = await this.executionContext();
  #       return (await context.evaluateHandle(addScriptUrl, url, type)).asElement();
  #     } catch (error) {
  #       throw new Error(`Loading script from ${url} failed`);
  #     }
  #   }

  #   if (path !== null) {
  #     let contents = await readFileAsync(path, 'utf8');
  #     contents += '//# sourceURL=' + path.replace(/\n/g, '');
  #     const context = await this.executionContext();
  #     return (await context.evaluateHandle(addScriptContent, contents, type)).asElement();
  #   }

  #   if (content !== null) {
  #     const context = await this.executionContext();
  #     return (await context.evaluateHandle(addScriptContent, content, type)).asElement();
  #   }

  #   throw new Error('Provide an object with a `url`, `path` or `content` property');

  #   /**
  #    * @param {string} url
  #    * @param {string} type
  #    * @return {!Promise<!HTMLElement>}
  #    */
  #   async function addScriptUrl(url, type) {
  #     const script = document.createElement('script');
  #     script.src = url;
  #     if (type)
  #       script.type = type;
  #     const promise = new Promise((res, rej) => {
  #       script.onload = res;
  #       script.onerror = rej;
  #     });
  #     document.head.appendChild(script);
  #     await promise;
  #     return script;
  #   }

  #   /**
  #    * @param {string} content
  #    * @param {string} type
  #    * @return {!HTMLElement}
  #    */
  #   function addScriptContent(content, type = 'text/javascript') {
  #     const script = document.createElement('script');
  #     script.type = type;
  #     script.text = content;
  #     let error = null;
  #     script.onerror = e => error = e;
  #     document.head.appendChild(script);
  #     if (error)
  #       throw error;
  #     return script;
  #   }
  # }

  # /**
  #  * @param {!{url?: string, path?: string, content?: string}} options
  #  * @return {!Promise<!Puppeteer.ElementHandle>}
  #  */
  # async addStyleTag(options) {
  #   const {
  #     url = null,
  #     path = null,
  #     content = null
  #   } = options;
  #   if (url !== null) {
  #     try {
  #       const context = await this.executionContext();
  #       return (await context.evaluateHandle(addStyleUrl, url)).asElement();
  #     } catch (error) {
  #       throw new Error(`Loading style from ${url} failed`);
  #     }
  #   }

  #   if (path !== null) {
  #     let contents = await readFileAsync(path, 'utf8');
  #     contents += '/*# sourceURL=' + path.replace(/\n/g, '') + '*/';
  #     const context = await this.executionContext();
  #     return (await context.evaluateHandle(addStyleContent, contents)).asElement();
  #   }

  #   if (content !== null) {
  #     const context = await this.executionContext();
  #     return (await context.evaluateHandle(addStyleContent, content)).asElement();
  #   }

  #   throw new Error('Provide an object with a `url`, `path` or `content` property');

  #   /**
  #    * @param {string} url
  #    * @return {!Promise<!HTMLElement>}
  #    */
  #   async function addStyleUrl(url) {
  #     const link = document.createElement('link');
  #     link.rel = 'stylesheet';
  #     link.href = url;
  #     const promise = new Promise((res, rej) => {
  #       link.onload = res;
  #       link.onerror = rej;
  #     });
  #     document.head.appendChild(link);
  #     await promise;
  #     return link;
  #   }

  #   /**
  #    * @param {string} content
  #    * @return {!Promise<!HTMLElement>}
  #    */
  #   async function addStyleContent(content) {
  #     const style = document.createElement('style');
  #     style.type = 'text/css';
  #     style.appendChild(document.createTextNode(content));
  #     const promise = new Promise((res, rej) => {
  #       style.onload = res;
  #       style.onerror = rej;
  #     });
  #     document.head.appendChild(style);
  #     await promise;
  #     return style;
  #   }
  # }

  class ElementNotFoundError < StandardError
    def initialize(selector)
      super("No node found for selector: #{selector}")
    end
  end

  # @param selector [String]
  # @param delay [Number]
  # @param button [String] "left"|"right"|"middle"
  # @param click_count [Number]
  def click(selector, delay: nil, button: nil, click_count: nil)
    handle = S(selector) or raise ElementNotFoundError.new(selector)
    handle.click(delay: delay, button: button, click_count: click_count)
    handle.dispose
  end

  # @param selector [String]
  def focus(selector)
    handle = S(selector) or raise ElementNotFoundError.new(selector)
    handle.focus
    handle.dispose
  end

  # /**
  #  * @param {string} selector
  #  */
  # async hover(selector) {
  #   const handle = await this.$(selector);
  #   assert(handle, 'No node found for selector: ' + selector);
  #   await handle.hover();
  #   await handle.dispose();
  # }

  # @param selector [String]
  # @return [Array<String>]
  def select(selector, *values)
    handle = S(selector) or raise ElementNotFoundError.new(selector)
    result = handle.select(*values)
    handle.dispose

    result
  end

  # @param selector [String]
  def tap(selector)
    handle = S(selector) or raise ElementNotFoundError.new(selector)
    handle.tap
    handle.dispose
  end

  # @param selector [String]
  # @param text [String]
  # @param delay [Number]
  def type_text(selector, text, delay: nil)
    handle = S(selector) or raise ElementNotFoundError.new(selector)
    handle.type_text(text, delay: delay)
    handle.dispose
  end

  # @param selector [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil)
    # call wait_for_selector_in_page with custom query selector.
    query_selector_manager = Puppeteer::QueryHandlerManager.instance
    query_selector_manager.detect_query_handler(selector).wait_for(self, visible: visible, hidden: hidden, timeout: timeout)
  end

  # @param query_one [String] JS function (element: Element | Document, selector: string) => Element | null;
  # @param selector [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  private def wait_for_selector_in_page(query_one, selector, visible: nil, hidden: nil, timeout: nil)
    option_wait_for_visible = visible || false
    option_wait_for_hidden = hidden || false
    option_timeout = timeout || @timeout_settings.timeout

    polling =
      if option_wait_for_visible || option_wait_for_hidden
        'raf'
      else
        'mutation'
      end
    title = "selector #{selector}#{option_wait_for_hidden ? 'to be hidden' : ''}"

    selector_predicate = make_predicate_string(
      predicate_arg_def: '(selector, waitForVisible, waitForHidden)',
      predicate_query_handler: query_one,
      async: true,
      predicate_body: <<~JAVASCRIPT
        const node = await predicateQueryHandler(document, selector)
        return checkWaitForOptions(node, waitForVisible, waitForHidden);
      JAVASCRIPT
    )

    wait_task = Puppeteer::WaitTask.new(
      dom_world: self,
      predicate_body: selector_predicate,
      title: title,
      polling: polling,
      timeout: option_timeout,
      args: [selector, option_wait_for_visible, option_wait_for_hidden],
    )
    handle = wait_task.await_promise
    unless handle.as_element
      handle.dispose
      return nil
    end
    handle.as_element
  end

  # @param xpath [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  def wait_for_xpath(xpath, visible: nil, hidden: nil, timeout: nil)
    option_wait_for_visible = visible || false
    option_wait_for_hidden = hidden || false
    option_timeout = timeout || @timeout_settings.timeout

    polling =
      if option_wait_for_visible || option_wait_for_hidden
        'raf'
      else
        'mutation'
      end
    title = "XPath #{xpath}#{option_wait_for_hidden ? 'to be hidden' : ''}"

    xpath_predicate = make_predicate_string(
      predicate_arg_def: '(selector, waitForVisible, waitForHidden)',
      predicate_body: <<~JAVASCRIPT
        const node = document.evaluate(selector, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
        return checkWaitForOptions(node, waitForVisible, waitForHidden);
      JAVASCRIPT
    )

    wait_task = Puppeteer::WaitTask.new(
      dom_world: self,
      predicate_body: xpath_predicate,
      title: title,
      polling: polling,
      timeout: option_timeout,
      args: [xpath, option_wait_for_visible, option_wait_for_hidden],
    )
    handle = wait_task.await_promise
    unless handle.as_element
      handle.dispose
      return nil
    end
    handle.as_element
  end

  # @param page_function [String]
  # @param args [Array]
  # @param polling [Integer|String]
  # @param timeout [Integer]
  # @return [Puppeteer::JSHandle]
  def wait_for_function(page_function, args: [], polling: nil, timeout: nil)
    option_polling = polling || 'raf'
    option_timeout = timeout || @timeout_settings.timeout

    Puppeteer::WaitTask.new(
      dom_world: self,
      predicate_body: page_function,
      title: 'function',
      polling: option_polling,
      timeout: option_timeout,
      args: args,
    ).await_promise
  end


  # @return [String]
  def title
    evaluate('() => document.title')
  end

  private def make_predicate_string(predicate_arg_def:, predicate_body:, predicate_query_handler: nil, async: false)
    predicate_query_handler_string =
      if predicate_query_handler
        "const predicateQueryHandler = #{predicate_query_handler}"
      else
        ""
      end

    <<~JAVASCRIPT
    #{async ? 'async ' : ''}function _#{predicate_arg_def} {
        #{predicate_query_handler_string}
        #{predicate_body}

        function checkWaitForOptions(node, waitForVisible, waitForHidden) {
          if (!node) return waitForHidden;
          if (!waitForVisible && !waitForHidden) return node;
          const element =
            node.nodeType === Node.TEXT_NODE ? node.parentElement : node;

          const style = window.getComputedStyle(element);
          const isVisible =
            style && style.visibility !== 'hidden' && hasVisibleBoundingBox();
          const success =
            waitForVisible === isVisible || waitForHidden === !isVisible;
          return success ? node : null;

          /**
          * @return {boolean}
          */
          function hasVisibleBoundingBox() {
            const rect = element.getBoundingClientRect();
            return !!(rect.top || rect.bottom || rect.width || rect.height);
          }
        }
    }
    JAVASCRIPT
  end
end
