class Puppeteer::AriaQueryHandler
  private def normalize(value)
    value.gsub(/ +/, ' ').strip
  end

  # @param selector [String]
  private def parse_aria_selector(selector)
    known_attributes = %w(name role)
    query_options = {}
    attribute_regexp = /\[\s*(?<attribute>\w+)\s*=\s*(?<quote>"|')(?<value>\\.|.*?(?=\k<quote>))\k<quote>\s*\]/
    default_name = selector.gsub(attribute_regexp) do
      attribute = $1.strip
      value = $3
      unless known_attributes.include?(attribute)
        raise ArgumentError.new("Unkown aria attribute \"#{attribute}\" in selector")
      end
      query_options[attribute.to_sym] = normalize(value)
      ''
    end

    if default_name.length > 0
      query_options[:name] ||= normalize(default_name)
    end

    query_options
  end

  def query_one(element, selector)
    context = element.execution_context
    parse_result = parse_aria_selector(selector)
    res = element.query_ax_tree(accessible_name: parse_result[:name], role: parse_result[:role])
    if res.empty?
      nil
    else
      context.adopt_backend_node_id(res.first['backendDOMNodeId'])
    end
  end

  def wait_for(dom_world, selector, visible: nil, hidden: nil, timeout: nil)
    # addHandlerToWorld
    binding_function = Puppeteer::DOMWorld::BindingFunction.new(
      name: 'ariaQuerySelector',
      proc: -> (sel) { query_one(dom_world.send(:document), sel) },
    )
    dom_world.send(:wait_for_selector_in_page,
      '(_, selector) => globalThis.ariaQuerySelector(selector)',
      selector,
      visible: visible,
      hidden: hidden,
      timeout: timeout,
      binding_function: binding_function)
  end

  def query_all(element, selector)
    context = element.execution_context
    parse_result = parse_aria_selector(selector)
    res = element.query_ax_tree(accessible_name: parse_result[:name], role: parse_result[:role])
    if res.empty?
      nil
    else
      promises = res.map do |ax_node|
        context.send(:async_adopt_backend_node_id, ax_node['backendDOMNodeId'])
      end
      await_all(*promises)
    end
  end

  def query_all_array(element, selector)
    element_handles = query_all(element, selector)
    element.execution_context.evaluate_handle('(...elements) => elements', *element_handles)
  end
end
