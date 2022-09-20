class Puppeteer::CustomQueryHandler
  # @param query_one [String] JS function (element: Element | Document, selector: string) => Element | null;
  # @param query_all [String] JS function (element: Element | Document, selector: string) => Element[] | NodeListOf<Element>;
  def initialize(query_one: nil, query_all: nil)
    @query_one = query_one
    @query_all = query_all
  end

  def query_one(element, selector)
    unless @query_one
      raise NotImplementedError.new("#{self.class}##{__method__} is not implemented.")
    end

    handle = element.evaluate_handle(@query_one, selector)
    element = handle.as_element

    if element
      return element
    end
    handle.dispose
    nil
  end

  def wait_for(element_or_frame, selector, visible: nil, hidden: nil, timeout: nil)
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

    result = frame.puppeteer_world.send(:wait_for_selector_in_page,
      @query_one,
      element,
      selector,
      visible: visible,
      hidden: hidden,
      timeout: timeout,
    )

    element&.dispose

    if result.is_a?(Puppeteer::ElementHandle)
      result.frame.main_world.transfer_handle(result)
    else
      result&.dispose
      nil
    end
  end

  def query_all(element, selector)
    unless @query_all
      raise NotImplementedError.new("#{self.class}##{__method__} is not implemented.")
    end

    handles = element.evaluate_handle(@query_all, selector)
    properties = handles.properties
    handles.dispose
    properties.values.map(&:as_element).compact
  end

  def query_all_array(element, selector)
    unless @query_all
      raise NotImplementedError.new("#{self.class}##{__method__} is not implemented.")
    end

    handles = element.evaluate_handle(@query_all, selector)
    handles.evaluate_handle('(res) => Array.from(res)')
  end
end
