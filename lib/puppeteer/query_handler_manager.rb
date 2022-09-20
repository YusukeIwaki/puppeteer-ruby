require 'singleton'

class Puppeteer::QueryHandlerManager
  include Singleton

  def query_handlers
    @query_handlers ||= {
      aria: Puppeteer::AriaQueryHandler.new,
      xpath: xpath_handler,
    }
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
