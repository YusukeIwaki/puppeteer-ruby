require 'thread'

# https://github.com/puppeteer/puppeteer/blob/master/src/DOMWorld.js
class Puppeteer::DOMWorld
  using Puppeteer::DefineAsyncMethod

  class BindingFunction
    def initialize(name:, proc:)
      @name = name
      @proc = proc
    end

    def call(*args)
      @proc.call(*args)
    end

    attr_reader :name

    def page_binding_init_string
      <<~JAVASCRIPT
      (type, bindingName) => {
        /* Cast window to any here as we're about to add properties to it
         * via win[bindingName] which TypeScript doesn't like.
         */
        const win = window;
        const binding = win[bindingName];

        win[bindingName] = (...args) => {
          const me = window[bindingName];
          let callbacks = me.callbacks;
          if (!callbacks) {
            callbacks = new Map();
            me.callbacks = callbacks;
          }
          const seq = (me.lastSeq || 0) + 1;
          me.lastSeq = seq;
          const promise = new Promise((resolve, reject) =>
            callbacks.set(seq, { resolve, reject })
          );
          binding(JSON.stringify({ type, name: bindingName, seq, args }));
          return promise;
        };
      }
      JAVASCRIPT
    end
  end

  # @param client [Puppeteer::CDPSession]
  # @param frame_manager [Puppeteer::FrameManager]
  # @param frame [Puppeteer::Frame]
  # @param timeout_settings [Puppeteer::TimeoutSettings]
  def initialize(client, frame_manager, frame, timeout_settings)
    # Keep own reference to client because it might differ from the FrameManager's
    # client for OOP iframes.
    @client = client
    @frame_manager = frame_manager
    @frame = frame
    @timeout_settings = timeout_settings
    @context_promise = resolvable_future
    @wait_tasks = Set.new
    @bound_functions = {}
    @ctx_bindings = Set.new
    @detached = false

    @client.on_event('Runtime.bindingCalled', &method(:handle_binding_called))
  end

  attr_reader :frame

  # only used in Puppeteer::WaitTask#initialize
  private def _wait_tasks
    @wait_tasks
  end

  # only used in Puppeteer::WaitTask#initialize
  private def _bound_functions
    @bound_functions
  end

  # @param context [Puppeteer::ExecutionContext]
  def context=(context)
    if context
      @ctx_bindings.clear
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

  # `$()` in JavaScript.
  # @param {string} selector
  # @return {!Promise<?Puppeteer.ElementHandle>}
  def query_selector(selector)
    document.query_selector(selector)
  end
  alias_method :S, :query_selector

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

  # `$eval()` in JavaScript.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def eval_on_selector(selector, page_function, *args)
    document.eval_on_selector(selector, page_function, *args)
  end
  alias_method :Seval, :eval_on_selector

  # `$$eval()` in JavaScript.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def eval_on_selector_all(selector, page_function, *args)
    document.eval_on_selector_all(selector, page_function, *args)
  end
  alias_method :SSeval, :eval_on_selector_all

  # `$$()` in JavaScript.
  # @param {string} selector
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def query_selector_all(selector)
    document.query_selector_all(selector)
  end
  alias_method :SS, :query_selector_all

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

  # @param url [String?]
  # @param path [String?]
  # @param content [String?]
  # @param id [String?]
  # @param type [String?]
  def add_script_tag(url: nil, path: nil, content: nil, id: nil, type: nil)
    if url
      begin
        return execution_context.
          evaluate_handle(ADD_SCRIPT_URL, url, id, type || '').
          as_element
      rescue Puppeteer::ExecutionContext::EvaluationError # for Chrome
        raise "Loading script from #{url} failed"
      rescue Puppeteer::Connection::ProtocolError # for Firefox
        raise "Loading script from #{url} failed"
      end
    end

    if path
      contents = File.read(path)
      contents += "//# sourceURL=#{path.gsub(/\n/, '')}"
      return execution_context.
        evaluate_handle(ADD_SCRIPT_CONTENT, contents, id, type || 'text/javascript').
        as_element
    end

    if content
      return execution_context.
        evaluate_handle(ADD_SCRIPT_CONTENT, content, id, type || 'text/javascript').
        as_element
    end

    raise ArgumentError.new('Provide an object with a `url`, `path` or `content` property')
  end

  ADD_SCRIPT_URL = <<~JAVASCRIPT
  async (url, id, type) => {
    const script = document.createElement('script');
    script.src = url;
    if (id) script.id = id;
    if (type) script.type = type;
    const promise = new Promise((res, rej) => {
      script.onload = res;
      script.onerror = rej;
    });
    document.head.appendChild(script);
    await promise;
    return script;
  }
  JAVASCRIPT

  ADD_SCRIPT_CONTENT = <<~JAVASCRIPT
  (content, id, type) => {
    const script = document.createElement('script');
    script.type = type;
    script.text = content;
    if (id) script.id = id;
    let error = null;
    script.onerror = e => error = e;
    document.head.appendChild(script);
    if (error)
      throw error;
    return script;
  }
  JAVASCRIPT

  # @param url [String?]
  # @param path [String?]
  # @param content [String?]
  def add_style_tag(url: nil, path: nil, content: nil)
    if url
      begin
        return execution_context.evaluate_handle(ADD_STYLE_URL, url).as_element
      rescue Puppeteer::ExecutionContext::EvaluationError # for Chrome
        raise "Loading style from #{url} failed"
      rescue Puppeteer::Connection::ProtocolError # for Firefox
        raise "Loading style from #{url} failed"
      end
    end

    if path
      contents = File.read(path)
      contents += "/*# sourceURL=#{path.gsub(/\n/, '')}*/"
      return execution_context.evaluate_handle(ADD_STYLE_CONTENT, contents).as_element
    end

    if content
      return execution_context.evaluate_handle(ADD_STYLE_CONTENT, content).as_element
    end

    raise ArgumentError.new('Provide an object with a `url`, `path` or `content` property')
  end

  ADD_STYLE_URL = <<~JAVASCRIPT
    async (url) => {
      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = url;
      const promise = new Promise((res, rej) => {
        link.onload = res;
        link.onerror = rej;
      });
      document.head.appendChild(link);
      await promise;
      return link;
    }
  JAVASCRIPT

  ADD_STYLE_CONTENT = <<~JAVASCRIPT
    async (content) => {
      const style = document.createElement('style');
      style.type = 'text/css';
      style.appendChild(document.createTextNode(content));
      const promise = new Promise((res, rej) => {
        style.onload = res;
        style.onerror = rej;
      });
      document.head.appendChild(style);
      await promise;
      return style;
    }
  JAVASCRIPT

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
    handle = query_selector(selector) or raise ElementNotFoundError.new(selector)
    handle.click(delay: delay, button: button, click_count: click_count)
    handle.dispose
  end

  # @param selector [String]
  def focus(selector)
    handle = query_selector(selector) or raise ElementNotFoundError.new(selector)
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
    handle = query_selector(selector) or raise ElementNotFoundError.new(selector)
    result = handle.select(*values)
    handle.dispose

    result
  end

  # @param selector [String]
  def tap(selector)
    handle = query_selector(selector) or raise ElementNotFoundError.new(selector)
    handle.tap
    handle.dispose
  end

  # @param selector [String]
  # @param text [String]
  # @param delay [Number]
  def type_text(selector, text, delay: nil)
    handle = query_selector(selector) or raise ElementNotFoundError.new(selector)
    handle.type_text(text, delay: delay)
    handle.dispose
  end

  # @param selector [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil, root: nil)
    # call wait_for_selector_in_page with custom query selector.
    query_selector_manager = Puppeteer::QueryHandlerManager.instance
    query_selector_manager.detect_query_handler(selector).wait_for(self, visible: visible, hidden: hidden, timeout: timeout, root: root)
  end

  private def binding_identifier(name, context)
    "#{name}_#{context.send(:_context_id)}"
  end


  def add_binding_to_context(context, binding_function)
    return if @ctx_bindings.include?(binding_identifier(binding_function.name, context))

    expression = binding_function.page_binding_init_string
    begin
      context.client.send_message('Runtime.addBinding',
        name: binding_function.name,
        executionContextName: context.send(:_context_name))
      context.evaluate(expression, 'internal', binding_function.name)
    rescue => err
      # We could have tried to evaluate in a context which was already
      # destroyed. This happens, for example, if the page is navigated while
      # we are trying to add the binding
      allowed = [
        'Execution context was destroyed',
        'Cannot find context with specified id',
      ]
      if allowed.any? { |msg| err.message.include?(msg) }
        # ignore
      else
        raise
      end
    end
    @ctx_bindings << binding_identifier(binding_function.name, context)
  end

  private def handle_binding_called(event)
    return unless has_context?
    payload = JSON.parse(event['payload']) rescue nil
    name = payload['name']
    args = payload['args']

    # The binding was either called by something in the page or it was
    # called before our wrapper was initialized.
    return unless payload
    return unless payload['type'] == 'internal'
    context = execution_context
    return unless @ctx_bindings.include?(binding_identifier(name, context))
    return unless context.send(:_context_id) == event['executionContextId']

    result = @bound_functions[name].call(*args)
    deliver_result_js = <<~JAVASCRIPT
    (name, seq, result) => {
      globalThis[name].callbacks.get(seq).resolve(result);
      globalThis[name].callbacks.delete(seq);
    }
    JAVASCRIPT

    begin
      context.evaluate(deliver_result_js, name, payload['seq'], result)
    rescue => err
      # The WaitTask may already have been resolved by timing out, or the
      # exection context may have been destroyed.
      # In both caes, the promises above are rejected with a protocol error.
      # We can safely ignores these, as the WaitTask is re-installed in
      # the next execution context if needed.
      return if err.message.include?('Protocol error')
      raise
    end
  end

  # @param query_one [String] JS function (element: Element | Document, selector: string) => Element | null;
  # @param selector [String]
  # @param visible [Boolean] Wait for element visible (not 'display: none' nor 'visibility: hidden') on true. default to false.
  # @param hidden [Boolean] Wait for element invisible ('display: none' nor 'visibility: hidden') on true. default to false.
  # @param timeout [Integer]
  private def wait_for_selector_in_page(query_one, selector, visible: nil, hidden: nil, timeout: nil, root: nil, binding_function: nil)
    option_wait_for_visible = visible || false
    option_wait_for_hidden = hidden || false
    option_timeout = timeout || @timeout_settings.timeout
    option_root = root

    polling =
      if option_wait_for_visible || option_wait_for_hidden
        'raf'
      else
        'mutation'
      end
    title = "selector #{selector}#{option_wait_for_hidden ? 'to be hidden' : ''}"

    selector_predicate = make_predicate_string(
      predicate_arg_def: '(root, selector, waitForVisible, waitForHidden)',
      predicate_query_handler: query_one,
      async: true,
      predicate_body: <<~JAVASCRIPT
        const node = await predicateQueryHandler(root, selector)
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
      root: option_root,
      binding_function: binding_function,
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
  def wait_for_xpath(xpath, visible: nil, hidden: nil, timeout: nil, root: nil)
    option_wait_for_visible = visible || false
    option_wait_for_hidden = hidden || false
    option_timeout = timeout || @timeout_settings.timeout
    option_root = root

    polling =
      if option_wait_for_visible || option_wait_for_hidden
        'raf'
      else
        'mutation'
      end
    title = "XPath #{xpath}#{option_wait_for_hidden ? 'to be hidden' : ''}"

    xpath_predicate = make_predicate_string(
      predicate_arg_def: '(root, selector, waitForVisible, waitForHidden)',
      predicate_body: <<~JAVASCRIPT
        const node = document.evaluate(selector, root, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
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
      root: option_root,
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
