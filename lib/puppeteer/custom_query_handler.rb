class Puppeteer::CustomQueryHandler
  # @param query_one [String] JS function (element: Element | Document, selector: string) => Element | null;
  # @param query_all [String] JS function (element: Element | Document, selector: string) => Element[] | NodeListOf<Element>;
  def initialize(query_one: nil, query_all: nil)
    @query_one = query_one
    @query_all = query_all
  end

  def query_one(element, selector)
    if @query_one
      return query_one_with_query_one(element, selector)
    end

    if @query_all
      elements = query_all_with_query_all(element, selector)
      return nil if elements.empty?

      first = elements.shift
      elements.each(&:dispose)
      return first
    end

    raise NotImplementedError.new("#{self.class}##{__method__} is not implemented.")
  end

  def wait_for(element_or_frame, selector, visible: nil, hidden: nil, timeout: nil, polling: nil)
    case element_or_frame
    when Puppeteer::Frame
      frame = element_or_frame
      element = nil
    when Puppeteer::ElementHandle
      frame = element_or_frame.frame
      element = frame.puppeteer_world.adopt_handle(element_or_frame)
    else
      raise ArgumentError.new("element_or_frame must be a Frame or ElementHandle. #{element_or_frame.inspect}")
    end

    unless @query_one
      raise NotImplementedError.new("#{self.class}##{__method__} is not implemented.")
    end

    begin
      result = frame.puppeteer_world.send(:wait_for_selector_in_page,
        @query_one,
        element,
        selector,
        visible: visible,
        hidden: hidden,
        timeout: timeout,
        polling: polling,
      )

      if result.is_a?(Puppeteer::ElementHandle)
        result.frame.main_world.transfer_handle(result)
      else
        result&.dispose
        nil
      end
    rescue => err
      wait_for_selector_error =
        if err.is_a?(Puppeteer::TimeoutError)
          Puppeteer::TimeoutError.new("Waiting for selector `#{selector}` failed")
        else
          Puppeteer::Error.new("Waiting for selector `#{selector}` failed")
        end
      wait_for_selector_error.cause = err
      raise wait_for_selector_error
    ensure
      element&.dispose
    end
  end

  def query_all(element, selector)
    if @query_all
      return query_all_with_query_all(element, selector)
    end

    if @query_one
      element_handle = query_one_with_query_one(element, selector)
      return element_handle ? [element_handle] : []
    end

    raise NotImplementedError.new("#{self.class}##{__method__} is not implemented.")
  end

  def query_all_array(element, selector)
    if @query_all
      handles = element.evaluate_handle(@query_all, selector)
      begin
        return handles.evaluate_handle('(res) => Array.from(res)')
      ensure
        handles.dispose
      end
    end

    if @query_one
      elements = query_all(element, selector)
      begin
        return element.execution_context.evaluate_handle('(...elements) => elements', *elements)
      ensure
        elements.each(&:dispose)
      end
    end

    raise NotImplementedError.new("#{self.class}##{__method__} is not implemented.")
  end

  private def query_one_with_query_one(element, selector)
    handle = element.evaluate_handle(@query_one, selector)
    element = handle.as_element

    if element
      return element
    end
    handle.dispose
    nil
  end

  private def query_all_with_query_all(element, selector)
    handles = element.evaluate_handle(@query_all, selector)
    properties = handles.properties
    handles.dispose
    properties.values.map(&:as_element).compact
  end
end
