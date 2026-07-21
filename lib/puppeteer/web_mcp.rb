# frozen_string_literal: true
# rbs_inline: enabled

class Puppeteer::WebMCPTool
  include Puppeteer::EventCallbackable

  # @rbs web_mcp: Puppeteer::WebMCP -- Owning WebMCP instance
  # @rbs tool: Hash[String, untyped] -- CDP tool payload
  # @rbs frame: Puppeteer::Frame -- Defining frame
  def initialize(web_mcp, tool, frame)
    @web_mcp = web_mcp
    @name = tool['name']
    @description = tool['description']
    @input_schema = tool['inputSchema']
    @annotations = tool['annotations']
    @frame = frame
    @backend_node_id = tool['backendNodeId']
    @raw_stack_trace = tool['stackTrace']
    @form_element = nil

    call_frame = @raw_stack_trace&.fetch('callFrames', [])&.first
    if call_frame
      @location = Puppeteer::ConsoleMessage::Location.new(
        url: call_frame['url'],
        line_number: call_frame['lineNumber'],
        column_number: call_frame['columnNumber'],
      )
    end
  end

  attr_reader :name, :description, :input_schema, :annotations, :frame,
              :location, :raw_stack_trace

  # @rbs return: Puppeteer::ElementHandle? -- Declarative form element
  def form_element
    return @form_element if @form_element && !@form_element.disposed?
    return nil unless @backend_node_id

    @form_element = @frame.main_world.adopt_backend_node(@backend_node_id)
  end

  # @rbs input: Hash[untyped, untyped] -- Tool input
  # @rbs return: Puppeteer::WebMCPToolCallResult -- Invocation result
  def execute(input = {})
    invocation_id = @web_mcp.invoke_tool(self, input).fetch('invocationId')
    promise = Async::Promise.new
    listener = nil
    listener = @web_mcp.add_event_listener('toolresponded') do |result|
      next unless result.id == invocation_id

      @web_mcp.remove_event_listener(listener)
      promise.resolve(result)
    end
    promise.wait
  end
end

class Puppeteer::WebMCPToolCall
  # @rbs id: String -- Invocation id
  # @rbs tool: Puppeteer::WebMCPTool -- Invoked tool
  # @rbs input: String -- JSON-encoded input
  def initialize(id, tool, input)
    @id = id
    @tool = tool
    @input = JSON.parse(input)
  rescue JSON::ParserError => error
    warn(error.message) if ENV['DEBUG']
    @input = {}
  end

  attr_reader :id, :tool, :input
end

class Puppeteer::WebMCPToolCallResult
  # @rbs id: String -- Invocation id
  # @rbs call: Puppeteer::WebMCPToolCall? -- Corresponding call
  # @rbs status: String -- Invocation status
  # @rbs output: untyped -- Invocation output
  # @rbs error_text: String? -- Error text
  # @rbs exception: Hash[String, untyped]? -- Remote exception
  def initialize(id:, call:, status:, output:, error_text:, exception:)
    @id = id
    @call = call
    @status = status
    @output = output
    @error_text = error_text
    @exception = exception
  end

  attr_reader :id, :call, :status, :output, :error_text, :exception
end

class Puppeteer::WebMCP
  include Puppeteer::EventCallbackable
  include Puppeteer::DebugPrint
  using Puppeteer::DefineAsyncMethod

  ToolsEvent = Struct.new(:tools, keyword_init: true)

  # @rbs client: Puppeteer::CDPSession -- Primary page session
  # @rbs frame_manager: Puppeteer::FrameManager -- Page frame manager
  def initialize(client, frame_manager)
    @client = client
    @frame_manager = frame_manager
    @tools = {}
    @pending_calls = {}
    @context_listener_ids = {}
    bind_listeners
  end

  # @rbs return: void -- Enable the WebMCP CDP domain when available
  def initialize_domain
    @client.send_message('WebMCP.enable')
  rescue => error
    debug_puts(error)
    nil
  end

  define_async_method :async_initialize_domain

  # @rbs tool: Puppeteer::WebMCPTool -- Tool to invoke
  # @rbs input: Hash[untyped, untyped] -- Invocation input
  # @rbs return: Hash[String, untyped] -- Invocation metadata
  def invoke_tool(tool, input)
    @client.send_message('WebMCP.invokeTool', {
      frameId: tool.frame.id,
      toolName: tool.name,
      input: input,
    })
  end

  # @rbs return: Array[Puppeteer::WebMCPTool] -- Registered tools
  def tools
    @tools.values.flat_map(&:values)
  end

  # @rbs client: Puppeteer::CDPSession -- Replacement primary session
  # @rbs return: void -- No return value
  def update_client(client)
    @client.remove_event_listener(*@listener_ids) if @listener_ids
    @client = client
    bind_listeners
  end

  private def bind_listeners
    @listener_ids = []
    @listener_ids << @client.add_event_listener('WebMCP.toolsAdded') do |event|
      handle_tools_added(event)
    end
    @listener_ids << @client.add_event_listener('WebMCP.toolsRemoved') do |event|
      handle_tools_removed(event)
    end
    @listener_ids << @client.add_event_listener('WebMCP.toolInvoked') do |event|
      handle_tool_invoked(event)
    end
    @listener_ids << @client.add_event_listener('WebMCP.toolResponded') do |event|
      handle_tool_responded(event)
    end
  end

  private def handle_tools_added(event)
    added = event.fetch('tools', []).filter_map do |payload|
      frame = @frame_manager.frame(payload['frameId'])
      next unless frame

      frame_tools = (@tools[payload['frameId']] ||= {})
      listen_to_context_destroyed(frame) if frame_tools.empty?
      tool = Puppeteer::WebMCPTool.new(self, payload, frame)
      frame_tools[tool.name] = tool
      tool
    end
    emit_event('toolsadded', ToolsEvent.new(tools: added))
  end

  private def handle_tools_removed(event)
    removed = event.fetch('tools', []).filter_map do |payload|
      tool = @tools.dig(payload['frameId'], payload['name'])
      @tools[payload['frameId']]&.delete(payload['name'])
      tool
    end
    emit_event('toolsremoved', ToolsEvent.new(tools: removed))
  end

  private def handle_tool_invoked(event)
    tool = @tools.dig(event['frameId'], event['toolName'])
    return unless tool

    call = Puppeteer::WebMCPToolCall.new(event['invocationId'], tool, event['input'])
    @pending_calls[call.id] = call
    tool.emit_event('toolinvoked', call)
    emit_event('toolinvoked', call)
  end

  private def handle_tool_responded(event)
    call = @pending_calls.delete(event['invocationId'])
    result = Puppeteer::WebMCPToolCallResult.new(
      id: event['invocationId'],
      call: call,
      status: event['status'],
      output: event['output'],
      error_text: event['errorText'],
      exception: event['exception'],
    )
    emit_event('toolresponded', result)
  end

  private def listen_to_context_destroyed(frame)
    context = frame.main_world.context
    return unless context
    return if @context_listener_ids[frame.id]

    listener_id = context.once('disposed') do
      handle_context_disposed(frame)
    end
    @context_listener_ids[frame.id] = [context, listener_id]
  end

  private def handle_context_disposed(frame)
    @pending_calls.clear
    @context_listener_ids.delete(frame.id)
    frame_tools = @tools.delete(frame.id)
    return unless frame_tools

    removed = frame_tools.values
    emit_event('toolsremoved', ToolsEvent.new(tools: removed)) unless removed.empty?
  end
end
