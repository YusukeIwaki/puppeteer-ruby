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

  def wait_for(dom_world, selector, visible: nil, hidden: nil, timeout: nil, root: nil)
    unless @query_one
      raise NotImplementedError.new("#{self.class}##{__method__} is not implemented.")
    end

    dom_world.send(:wait_for_selector_in_page, @query_one, selector, visible: visible, hidden: hidden, timeout: timeout, root: root)
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
