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

  # @param element [Puppeteer::ElementHandle]
  # @param selector [String]
  private def query_one_id(element, selector)
    parse_result = parse_aria_selector(selector)
    res = element.query_ax_tree(accessible_name: parse_result[:name], role: parse_result[:role])

    if res.first.is_a?(Hash)
      res.first['backendDOMNodeId']
    else
      nil
    end
  end

  def query_one(element, selector)
    id = query_one_id(element, selector)

    if id
      element.frame.main_world.adopt_backend_node(id)
    else
      nil
    end
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

    # addHandlerToWorld
    binding_function = Puppeteer::IsolaatedWorld::BindingFunction.new(
      name: 'ariaQuerySelector',
      proc: -> (sel) {
        id = query_one_id(element || frame.puppeteer_world.document, sel)

        if id
          frame.puppeteer_world.adopt_backend_node(id)
        else
          nil
        end
      },
    )
    result = frame.puppeteer_world.send(:wait_for_selector_in_page,
      '(_, selector) => globalThis.ariaQuerySelector(selector)',
      element,
      selector,
      visible: visible,
      hidden: hidden,
      timeout: timeout,
      polling: polling,
      binding_function: binding_function,
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
    world = element.frame.main_world
    parse_result = parse_aria_selector(selector)
    res = element.query_ax_tree(accessible_name: parse_result[:name], role: parse_result[:role])
    if res.empty?
      nil
    else
      promises = res.map do |ax_node|
        world.send(:async_adopt_backend_node, ax_node['backendDOMNodeId'])
      end
      Puppeteer::AsyncUtils.await_promise_all(*promises)
    end
  end

  def query_all_array(element, selector)
    element_handles = query_all(element, selector)
    element.execution_context.evaluate_handle('(...elements) => elements', *element_handles)
  end
end
