# frozen_string_literal: true
# rbs_inline: enabled

class Puppeteer::Accessibility
  class SerializedAXNode < Hash #[String, untyped]
    # @rbs values: Hash[String, untyped] -- Serialized node values
    # @rbs element_handle_resolver: Proc -- Resolver for the backing element
    def initialize(values, element_handle_resolver)
      super()
      update(values)
      @element_handle_resolver = element_handle_resolver
    end

    # @rbs return: Puppeteer::ElementHandle? -- Backing element, if available
    def element_handle
      @element_handle_resolver.call
    end
  end

  # @rbs frame: Puppeteer::Frame -- Frame whose accessibility tree is inspected
  def initialize(frame)
    @frame = frame
  end

  # @rbs interesting_only: bool -- Prune uninteresting nodes
  # @rbs include_iframes: bool -- Include descendant iframe trees
  # @rbs root: Puppeteer::ElementHandle? -- Optional root node
  # @rbs return: SerializedAXNode? -- Accessibility snapshot
  def snapshot(interesting_only: true, include_iframes: false, root: nil)
    response = @frame.client.send_message(
      'Accessibility.getFullAXTree',
      frameId: @frame.id,
    )
    backend_node_id = describe_backend_node(root) if root
    default_root = AXNode.create_tree(@frame, response.fetch('nodes', []))
    return nil unless default_root

    populate_iframes(default_root, interesting_only: interesting_only) if include_iframes

    needle = default_root
    if backend_node_id
      needle = default_root.find do |node|
        node.payload['backendDOMNodeId'] == backend_node_id
      end
    end
    return nil unless needle

    return serialize_tree(needle).first unless interesting_only

    interesting_nodes = Set.new
    collect_interesting_nodes(interesting_nodes, default_root, false)
    serialize_tree(needle, interesting_nodes).first
  end

  private def describe_backend_node(root)
    response = @frame.client.send_message(
      'DOM.describeNode',
      objectId: root.remote_object.object_id_value,
    )
    response.dig('node', 'backendNodeId')
  end

  private def populate_iframes(root, interesting_only:)
    if root.role == 'Iframe' && root.payload['backendDOMNodeId']
      begin
        handle = @frame.main_world.adopt_backend_node(root.payload['backendDOMNodeId'])
        frame = handle&.content_frame
        root.iframe_snapshot = frame&.accessibility&.snapshot(
          interesting_only: interesting_only,
          include_iframes: true,
        )
      rescue StandardError
        # Frames may detach while their accessibility trees are populated.
      ensure
        handle&.dispose
      end
    end

    tasks = root.children.map do |child|
      proc { populate_iframes(child, interesting_only: interesting_only) }
    end
    Puppeteer::AsyncUtils.await_promise_all(*tasks) unless tasks.empty?
  end

  private def serialize_tree(node, interesting_nodes = nil)
    children = node.children.flat_map do |child|
      serialize_tree(child, interesting_nodes)
    end
    return children if interesting_nodes && !interesting_nodes.include?(node)

    serialized = node.serialize
    serialized['children'] = children unless children.empty?
    if node.iframe_snapshot
      serialized['children'] ||= []
      serialized['children'] << node.iframe_snapshot
    end
    [serialized]
  end

  private def collect_interesting_nodes(collection, node, inside_control)
    collection << node if node.interesting?(inside_control) || node.iframe_snapshot
    return if node.leaf_node?

    inside_control ||= node.control?
    node.children.each do |child|
      collect_interesting_nodes(collection, child, inside_control)
    end
  end

  class AXNode
    CONTROL_ROLES = Set.new(%w[
      button checkbox ColorWell combobox DisclosureTriangle listbox menu
      menubar menuitem menuitemcheckbox menuitemradio radio scrollbar searchbox
      slider spinbutton switch tab textbox tree treeitem
    ]).freeze
    LANDMARK_ROLES = Set.new(%w[
      banner complementary contentinfo form main navigation region search
    ]).freeze
    LEAF_ROLES = Set.new(%w[
      doc-cover graphics-symbol img image Meter scrollbar slider separator progressbar
    ]).freeze
    TEXT_ROLES = Set.new(%w[LineBreak text InlineTextBox StaticText]).freeze

    # @rbs frame: Puppeteer::Frame -- Owning frame
    # @rbs payload: Hash[String, untyped] -- CDP AX node payload
    def initialize(frame, payload)
      @frame = frame
      @payload = payload
      @children = []
      @iframe_snapshot = nil
      @role = payload.dig('role', 'value') || 'Unknown'
      @ignored = payload['ignored']
      @name = payload.dig('name', 'value') || ''
      @description = payload.dig('description', 'value')
      @richly_editable = false
      @editable = false
      @focusable = false
      @hidden = false
      @busy = false
      @modal = false
      @has_error_message = false
      @has_details = false
      @role_description = nil
      @live = nil
      @cached_has_focusable_child = nil
      read_properties
    end

    attr_reader :payload, :children, :role
    attr_accessor :iframe_snapshot

    def find(&predicate)
      return self if predicate.call(self)

      @children.each do |child|
        result = child.find(&predicate)
        return result if result
      end
      nil
    end

    def leaf_node?
      return true if @children.empty?
      return true if plain_text_field? || TEXT_ROLES.include?(@role)
      return true if LEAF_ROLES.include?(@role)
      return false if has_focusable_child?
      return true if @role == 'heading' && !@name.empty?

      false
    end

    def control?
      CONTROL_ROLES.include?(@role)
    end

    def landmark?
      LANDMARK_ROLES.include?(@role)
    end

    def interesting?(inside_control)
      return false if @role == 'Ignored' || @hidden || @ignored
      return true if landmark?
      return true if @focusable || @richly_editable || @busy
      return true if @live && @live != 'off'
      return true if @modal || @has_error_message || @has_details || @role_description
      return true if control?
      return false if inside_control

      leaf_node? && (!@name.empty? || !@description.to_s.empty?)
    end

    def serialize
      properties = {}
      @payload.fetch('properties', []).each do |property|
        properties[property['name'].downcase] = property.dig('value', 'value')
      end
      properties['name'] = @payload.dig('name', 'value') if @payload['name']
      properties['value'] = @payload.dig('value', 'value') if @payload['value']
      if @payload['description']
        properties['description'] = @payload.dig('description', 'value')
      end

      values = {
        'role' => @role,
        'backendNodeId' => @payload['backendDOMNodeId'],
        'loaderId' => @frame.loader_id,
      }
      %w[name value description keyshortcuts roledescription valuetext url].each do |key|
        values[key] = properties[key] if properties.key?(key)
      end
      %w[
        disabled expanded focused modal multiline multiselectable readonly required
        selected busy atomic
      ].each do |key|
        next if key == 'focused' && @role == 'RootWebArea'
        values[key] = !!properties[key] if properties.key?(key)
      end
      %w[checked pressed].each do |key|
        next unless properties.key?(key)
        value = properties[key]
        values[key] = value == 'mixed' ? 'mixed' : value == 'true'
      end
      %w[level valuemax valuemin].each do |key|
        values[key] = properties[key] if properties.key?(key)
      end
      %w[
        autocomplete haspopup invalid orientation live relevant errormessage details
      ].each do |key|
        value = properties[key]
        values[key] = value if value && value != 'false'
      end
      values.delete_if { |_key, value| value.nil? }

      SerializedAXNode.new(values, method(:element_handle))
    end

    def self.create_tree(frame, payloads)
      nodes_by_id = {}
      payloads.each do |payload|
        nodes_by_id[payload['nodeId']] = new(frame, payload)
      end
      nodes_by_id.each_value do |node|
        node.payload.fetch('childIds', []).each do |child_id|
          child = nodes_by_id[child_id]
          node.children << child if child
        end
      end
      nodes_by_id.each_value.first
    end

    private def read_properties
      @payload.fetch('properties', []).each do |property|
        name = property['name']
        value = property.dig('value', 'value')
        case name
        when 'editable'
          @richly_editable = value == 'richtext'
          @editable = true
        when 'focusable' then @focusable = value
        when 'hidden' then @hidden = value
        when 'busy' then @busy = value
        when 'live' then @live = value
        when 'modal' then @modal = value
        when 'roledescription' then @role_description = value
        when 'errormessage' then @has_error_message = true
        when 'details' then @has_details = true
        end
      end
    end

    private def plain_text_field?
      return false if @richly_editable
      return true if @editable

      ['textbox', 'searchbox'].include?(@role)
    end

    private def has_focusable_child?
      if @cached_has_focusable_child.nil?
        @cached_has_focusable_child = @children.any? do |child|
          child.instance_variable_get(:@focusable) || child.send(:has_focusable_child?)
        end
      end
      @cached_has_focusable_child
    end

    private def element_handle
      backend_node_id = @payload['backendDOMNodeId']
      return nil unless backend_node_id

      handle = @frame.main_world.adopt_backend_node(backend_node_id)
      element = handle.evaluate_handle(<<~JAVASCRIPT)
        node => node.nodeType === Node.TEXT_NODE ? node.parentElement : node
      JAVASCRIPT
      element.as_element
    ensure
      handle&.dispose
    end
  end
end
