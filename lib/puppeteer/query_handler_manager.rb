require 'singleton'

class Puppeteer::QueryHandlerManager
  include Singleton

  DEFAULT_QUERY_HANDLER_NAMES = %i[aria xpath text].freeze

  def query_handlers
    @query_handlers ||= {
      aria: Puppeteer::AriaQueryHandler.new,
      xpath: xpath_handler,
      text: text_query_handler,
    }
  end

  def custom_query_handler_names
    query_handlers.keys.reject { |name| DEFAULT_QUERY_HANDLER_NAMES.include?(name) }.map(&:to_s)
  end

  def unregister_custom_query_handler(name)
    handler_name = name.to_sym
    if DEFAULT_QUERY_HANDLER_NAMES.include?(handler_name)
      raise ArgumentError.new("Cannot unregister built-in query handler: #{name}")
    end
    unless query_handlers.key?(handler_name)
      raise ArgumentError.new("Cannot unregister unknown handler: #{name}")
    end

    query_handlers.delete(handler_name)
  end

  def clear_custom_query_handlers
    query_handlers.each_key do |name|
      next if DEFAULT_QUERY_HANDLER_NAMES.include?(name)

      query_handlers.delete(name)
    end
  end

  private def default_handler
    @default_handler ||= Puppeteer::CustomQueryHandler.new(
      query_one: '(element, selector) => element.querySelector(selector)',
      query_all: '(element, selector) => element.querySelectorAll(selector)',
    )
  end

  private def xpath_handler
    @xpath_handler ||= Puppeteer::CustomQueryHandler.new(
      query_one: <<~JAVASCRIPT,
      (element, selector) => {
        const doc = element.ownerDocument || document;
        const result = doc.evaluate(
          selector,
          element,
          null,
          XPathResult.FIRST_ORDERED_NODE_TYPE
        );
        return result.singleNodeValue;
      }
      JAVASCRIPT
      query_all: <<~JAVASCRIPT,
      (element, selector) => {
        const doc = element.ownerDocument || document;
        const iterator = doc.evaluate(
          selector,
          element,
          null,
          XPathResult.ORDERED_NODE_ITERATOR_TYPE
        );
        const array = [];
        let item;
        while ((item = iterator.iterateNext())) {
          array.push(item);
        }
        return array;
      }
      JAVASCRIPT
    )
  end

  private def text_query_handler
    text_content_js = <<~JAVASCRIPT
    const TRIVIAL_VALUE_INPUT_TYPES = new Set(['checkbox', 'image', 'radio']);

    /**
     * Determines if the node has a non-trivial value property.
     */
    const isNonTrivialValueNode = (node) => {
      if (node instanceof HTMLSelectElement) {
        return true;
      }
      if (node instanceof HTMLTextAreaElement) {
        return true;
      }
      if (
        node instanceof HTMLInputElement &&
        !TRIVIAL_VALUE_INPUT_TYPES.has(node.type)
      ) {
        return true;
      }
      return false;
    };

    const UNSUITABLE_NODE_NAMES = new Set(['SCRIPT', 'STYLE']);

    /**
    * Determines whether a given node is suitable for text matching.
    */
    const isSuitableNodeForTextMatching = (node) => {
      return (
        !UNSUITABLE_NODE_NAMES.has(node.nodeName) && !document.head?.contains(node)
      );
    };

    /**
    * Maps {@link Node}s to their computed {@link TextContent}.
    */
    const textContentCache = new Map();

    /**
    * Builds the text content of a node using some custom logic.
    *
    * @remarks
    * The primary reason this function exists is due to {@link ShadowRoot}s not having
    * text content.
    *
    * @internal
    */
    const createTextContent = (root) => {
      let value = textContentCache.get(root);
      if (value) {
        return value;
      }
      value = {full: '', immediate: []};
      if (!isSuitableNodeForTextMatching(root)) {
        return value;
      }
      let currentImmediate = '';
      if (isNonTrivialValueNode(root)) {
        value.full = root.value;
        value.immediate.push(root.value);
      } else {
        for (let child = root.firstChild; child; child = child.nextSibling) {
          if (child.nodeType === Node.TEXT_NODE) {
            value.full += child.nodeValue ?? '';
            currentImmediate += child.nodeValue ?? '';
            continue;
          }
          if (currentImmediate) {
            value.immediate.push(currentImmediate);
          }
          currentImmediate = '';
          if (child.nodeType === Node.ELEMENT_NODE) {
            value.full += createTextContent(child).full;
          }
        }
        if (currentImmediate) {
          value.immediate.push(currentImmediate);
        }
        if (root instanceof Element && root.shadowRoot) {
          value.full += createTextContent(root.shadowRoot).full;
        }
      }
      textContentCache.set(root, value);
      return value;
    };
    JAVASCRIPT

    @text_query_handler ||= Puppeteer::CustomQueryHandler.new(
      query_one: <<~JAVASCRIPT,
      (element, selector) => {
        #{text_content_js}

        const search = (root) => {
          for (const node of root.childNodes) {
            if (node instanceof Element) {
              let matchedNode;
              if (node.shadowRoot) {
                matchedNode = search(node.shadowRoot);
              } else {
                matchedNode = search(node);
              }
              if (matchedNode) {
                return matchedNode;
              }
            }
          }
          const textContent = createTextContent(root);
          if (textContent.full.includes(selector)) {
            return root;
          }
          return null;
        };
        return search(element);
      }
      JAVASCRIPT

      query_all: <<~JAVASCRIPT,
      (element, selector) => {
        #{text_content_js}

        const search = (root) => {
          let results = [];
          for (const node of root.childNodes) {
            if (node instanceof Element) {
              let matchedNodes;
              if (node.shadowRoot) {
                matchedNodes = search(node.shadowRoot);
              } else {
                matchedNodes = search(node);
              }
              results = results.concat(matchedNodes);
            }
          }
          if (results.length > 0) {
            return results;
          }

          const textContent = createTextContent(root);
          if (textContent.full.includes(selector)) {
            return [root];
          }
          return [];
        };
        return search(element);
      }
      JAVASCRIPT
    )
  end

  class Result
    def initialize(query_handler:, selector:)
      @query_handler = query_handler
      @selector = selector
    end

    def query_one(element_handle)
      @query_handler.query_one(element_handle, @selector)
    end

    def wait_for(element_or_frame, visible:, hidden:, timeout:)
      @query_handler.wait_for(element_or_frame, @selector, visible: visible, hidden: hidden, timeout: timeout)
    end

    def query_all(element_handle)
      @query_handler.query_all(element_handle, @selector)
    end

    def query_all_array(element_handle)
      @query_handler.query_all_array(element_handle, @selector)
    end
  end

  def detect_query_handler(selector)
    unless /^[a-zA-Z]+\// =~ selector
      return Result.new(
        query_handler: default_handler,
        selector: selector,
      )
    end

    chunk = selector.split("/")
    name = chunk.shift
    updated_selector = chunk.join("/")

    query_handler = query_handlers[name.to_sym]

    unless query_handler
      raise ArgumentError.new("Query set to use \"#{name}\", but no query handler of that name was found")
    end

    Result.new(
      query_handler: query_handler,
      selector: updated_selector,
    )
  end
end
