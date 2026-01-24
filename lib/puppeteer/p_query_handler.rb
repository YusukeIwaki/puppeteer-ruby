# rbs_inline: enabled

class Puppeteer::PQueryHandler
  POLLING_DEFAULT_SECONDS = 0.1

  CSS_QUERY_SELECTOR_JS = <<~'JAVASCRIPT'
    (element, selector) => {
      const results = [];
      const isQueryableNode = node => {
        return node && typeof node.querySelectorAll === 'function';
      };
      if (!isQueryableNode(element)) {
        return results;
      }
      const trimmed = selector.trimStart();
      if (!trimmed) {
        return results;
      }
      const IDENT_TOKEN_START = /[-\w\P{ASCII}*]/u;
      if (IDENT_TOKEN_START.test(trimmed[0])) {
        results.push(...element.querySelectorAll(selector));
        return results;
      }
      if (!element.parentElement) {
        results.push(...element.querySelectorAll(selector));
        return results;
      }
      let index = 0;
      for (const child of element.parentElement.children) {
        ++index;
        if (child === element) {
          break;
        }
      }
      results.push(
        ...element.parentElement.querySelectorAll(
          `:scope>:nth-child(${index})${selector}`
        )
      );
      return results;
    }
  JAVASCRIPT

  PIERCE_JS = <<~JAVASCRIPT
    node => {
      if (!node) {
        return [];
      }
      if (node.shadowRoot) {
        return [node.shadowRoot];
      }
      return [node];
    }
  JAVASCRIPT

  PIERCE_ALL_JS = <<~JAVASCRIPT
    root => {
      if (!root) {
        return [];
      }
      const results = [];
      const rootNode = root.shadowRoot ? root.shadowRoot : root;
      results.push(rootNode);
      const walkers = [document.createTreeWalker(rootNode, NodeFilter.SHOW_ELEMENT)];
      for (const walker of walkers) {
        let node;
        while ((node = walker.nextNode())) {
          if (!node.shadowRoot) {
            continue;
          }
          results.push(node.shadowRoot);
          walkers.push(document.createTreeWalker(node.shadowRoot, NodeFilter.SHOW_ELEMENT));
        }
      }
      return results;
    }
  JAVASCRIPT

  DOM_SORT_JS = <<~JAVASCRIPT
    (...elements) => {
      const results = new Set(elements);
      class DepthCalculator {
        constructor() {
          this.cache = new WeakMap();
        }
        calculate(node, depth = []) {
          if (node === null) {
            return depth;
          }
          if (node instanceof ShadowRoot) {
            node = node.host;
          }
          const cached = this.cache.get(node);
          if (cached) {
            return [...cached, ...depth];
          }
          let index = 0;
          for (let prev = node.previousSibling; prev; prev = prev.previousSibling) {
            ++index;
          }
          const value = this.calculate(node.parentNode, [index]);
          this.cache.set(node, value);
          return [...value, ...depth];
        }
      }
      const compareDepths = (a, b) => {
        if (a.length + b.length === 0) {
          return 0;
        }
        const [i = -1, ...restA] = a;
        const [j = -1, ...restB] = b;
        if (i === j) {
          return compareDepths(restA, restB);
        }
        return i < j ? -1 : 1;
      };
      const calculator = new DepthCalculator();
      return [...results]
        .map(result => [result, calculator.calculate(result)])
        .sort(([, a], [, b]) => compareDepths(a, b))
        .map(([result]) => result);
    }
  JAVASCRIPT

  # @rbs query_handler_manager: untyped -- Query handler manager
  # @rbs return: void -- No return value
  def initialize(query_handler_manager: Puppeteer::QueryHandlerManager.instance)
    @query_handler_manager = query_handler_manager
  end

  # @rbs element: Puppeteer::ElementHandle -- Root element
  # @rbs selector: String -- PSelector string
  # @rbs return: Puppeteer::ElementHandle? -- First matching element
  def query_one(element, selector)
    matches = query_all(element, selector)
    return nil if matches.empty?

    matches.first
  end

  # @rbs element: Puppeteer::ElementHandle -- Root element
  # @rbs selector: String -- PSelector string
  # @rbs return: Array[Puppeteer::ElementHandle] -- Matching elements
  def query_all(element, selector)
    selectors, = Puppeteer::PSelectorParser.parse(selector)
    return [] if selectors.empty?

    results = selectors.flat_map do |complex|
      run_complex_selector(element, complex)
    end

    return [] if results.empty?

    dom_sort(results)
  end

  # @rbs element: Puppeteer::ElementHandle -- Root element
  # @rbs selector: String -- PSelector string
  # @rbs return: Puppeteer::JSHandle -- Handle to array of elements
  def query_all_array(element, selector)
    elements = query_all(element, selector)
    return element.execution_context.evaluate_handle('() => []') if elements.empty?

    element.execution_context.evaluate_handle('(...elements) => elements', *elements)
  ensure
    elements&.each(&:dispose)
  end

  # @rbs element_or_frame: Puppeteer::ElementHandle | Puppeteer::Frame -- Root element or frame
  # @rbs selector: String -- PSelector string
  # @rbs visible: bool? -- Wait for element to be visible
  # @rbs hidden: bool? -- Wait for element to be hidden
  # @rbs timeout: Numeric? -- Timeout in milliseconds
  # @rbs polling: (String | Numeric | nil) -- Polling strategy
  # @rbs return: Puppeteer::ElementHandle? -- Matching element
  def wait_for(element_or_frame, selector, visible:, hidden:, timeout:, polling: nil)
    case element_or_frame
    when Puppeteer::Frame
      frame = element_or_frame
      root = nil
    when Puppeteer::ElementHandle
      frame = element_or_frame.frame
      root = frame.puppeteer_world.adopt_handle(element_or_frame)
    else
      raise ArgumentError.new("element_or_frame must be a Frame or ElementHandle. #{element_or_frame.inspect}")
    end

    timeout_ms = timeout.nil? ? frame.default_timeout : timeout
    deadline = timeout_ms && timeout_ms > 0 ? monotonic_time + (timeout_ms / 1000.0) : nil
    polling_interval = polling_interval_seconds(polling, visible: visible, hidden: hidden)

    begin
      loop do
        resolved_root = root || frame.puppeteer_world.document
        handle = query_one(resolved_root, selector)

        if handle
          if visible
            return transfer_handle(frame, handle) if handle.visible?
          elsif hidden
            return transfer_handle(frame, handle) if handle.hidden?
          else
            return transfer_handle(frame, handle)
          end
          handle.dispose
        elsif hidden
          return nil
        end

        raise_timeout(selector) if deadline && monotonic_time >= deadline
        Puppeteer::AsyncUtils.sleep_seconds(polling_interval)
      end
    rescue => err
      if err.is_a?(Puppeteer::TimeoutError)
        raise
      end

      wait_for_selector_error =
        if err.is_a?(Puppeteer::TimeoutError)
          Puppeteer::TimeoutError.new("Waiting for selector `#{selector}` failed")
        else
          Puppeteer::Error.new("Waiting for selector `#{selector}` failed")
        end
      wait_for_selector_error.cause = err
      raise wait_for_selector_error
    ensure
      root&.dispose
    end
  end

  private
    def run_complex_selector(root, complex)
      elements = [root]

      complex.each do |part|
        case part
        when '>>>'
          elements = pierce_all(elements)
        when '>>>>'
          elements = pierce(elements)
        else
          elements = apply_compound(elements, part)
        end
        return [] if elements.empty?
      end

      elements
    end

    def apply_compound(elements, compound)
      compound.reduce(elements) do |current, selector|
        next [] if current.empty?

        if selector.is_a?(String)
          apply_css_selector(current, selector)
        else
          apply_pseudo_selector(current, selector)
        end
      end
    end

    def apply_css_selector(elements, selector)
      elements.flat_map do |element|
        query_css_selector(element, selector)
      end
    end

    def query_css_selector(element, selector)
      return [] if selector.strip.empty?

      array_handle = element.evaluate_handle(CSS_QUERY_SELECTOR_JS, selector)
      array_handle_to_elements(array_handle)
    ensure
      array_handle&.dispose
    end

    def apply_pseudo_selector(elements, pseudo)
      handler = query_handler_for_pseudo(pseudo.name)
      target_context = elements.first&.execution_context

      elements.flat_map do |element|
        handles = handler.query_all(element, pseudo.value) || []
        handles.map do |handle|
          ensure_context(handle, target_context)
        end
      end
    end

    def query_handler_for_pseudo(name)
      handler = @query_handler_manager.query_handlers[name.to_sym]
      return handler if handler

      raise Puppeteer::Error.new("Unknown selector type: #{name}")
    end

    def pierce(elements)
      elements.flat_map do |element|
        array_handle = element.evaluate_handle(PIERCE_JS)
        array_handle_to_elements(array_handle)
      ensure
        array_handle&.dispose
      end
    end

    def pierce_all(elements)
      elements.flat_map do |element|
        array_handle = element.evaluate_handle(PIERCE_ALL_JS)
        array_handle_to_elements(array_handle)
      ensure
        array_handle&.dispose
      end
    end

    def dom_sort(elements)
      return [] if elements.empty?

      context = elements.first.execution_context
      sorted_handle = context.evaluate_handle(DOM_SORT_JS, *elements)
      sorted = array_handle_to_elements(sorted_handle)
      elements.each(&:dispose)
      sorted
    ensure
      sorted_handle&.dispose
    end

    def array_handle_to_elements(array_handle)
      properties = array_handle.properties
      properties.keys.sort_by(&:to_i).filter_map do |key|
        properties[key].as_element
      end
    end

    def ensure_context(handle, context)
      return handle if context.nil? || handle.execution_context == context

      world = context.world
      return handle unless world

      world.transfer_handle(handle)
    end

    def transfer_handle(frame, handle)
      if handle.execution_context == frame.main_world.execution_context
        handle
      else
        frame.main_world.transfer_handle(handle)
      end
    end

    def polling_interval_seconds(polling, visible:, hidden:)
      return polling / 1000.0 if polling.is_a?(Numeric)

      if visible || hidden
        return 0.016
      end

      POLLING_DEFAULT_SECONDS
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def raise_timeout(selector)
      raise Puppeteer::TimeoutError.new("Waiting for selector `#{selector}` failed")
    end
end
