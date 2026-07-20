require 'spec_helper'

RSpec.describe 'Page.webmcp' do
  include Utils::WaitEvent

  def with_webmcp_test_state(&block)
    args = [*default_launch_options[:args], '--enable-features=WebMCP']
    with_browser(args: args) do |browser|
      with_test_state(browser: browser) do |state|
        state[:page].goto(state[:https_server].empty_page)
        block.call(**state)
      end
    end
  end

  def event_promise(emitter, event_name)
    promise = Async::Promise.new
    emitter.once(event_name) { |event| promise.resolve(event) }
    promise
  end

  def register_imperative_tool(page, execute: '() => {}')
    page.evaluate(<<~JAVASCRIPT)
      () => {
        void document.modelContext.registerTool({
          name: 'test-tool-1',
          description: 'A test tool 1',
          inputSchema: {
            type: 'object',
            properties: {
              text: {type: 'string', description: 'Some text'},
            },
            required: ['text'],
          },
          execute: #{execute},
        });
      }
    JAVASCRIPT
  end

  def register_declarative_tool(page, name: 'declarative tool name', description: 'tool description')
    page.evaluate(<<~JAVASCRIPT)
      () => {
        const form = document.createElement('form');
        form.setAttribute('toolname', #{JSON.generate(name)});
        form.setAttribute('tooldescription', #{JSON.generate(description)});
        document.body.appendChild(form);
      }
    JAVASCRIPT
  end

  def imperative_schema
    {
      'type' => 'object',
      'properties' => {
        'text' => { 'type' => 'string', 'description' => 'Some text' },
      },
      'required' => ['text'],
    }
  end

  it 'should list tools' do
    with_webmcp_test_state do |page:, **|
      expect(page.webmcp).to be_a(Puppeteer::WebMCP)
      tools_added = Async::Promise.new
      count = 0
      page.webmcp.on('toolsadded') do
        count += 1
        tools_added.resolve(nil) if count == 2
      end

      page.evaluate(<<~JAVASCRIPT)
        () => {
          void document.modelContext.registerTool({
            name: 'test-tool-1',
            description: 'A test tool 1',
            inputSchema: {
              type: 'object',
              properties: {text: {type: 'string', description: 'Some text'}},
              required: ['text'],
            },
            execute: params => params.text,
            annotations: {readOnlyHint: true, untrustedContentHint: true},
          });
        }
      JAVASCRIPT
      page.evaluate(<<~JAVASCRIPT)
        () => {
          const form = document.createElement('form');
          form.setAttribute('toolname', 'declarative tool name');
          form.setAttribute('tooldescription', 'tool description');
          form.setAttribute('toolautosubmit', '');
          document.body.appendChild(form);
        }
      JAVASCRIPT
      tools_added.wait

      tools = page.webmcp.tools
      expect(tools.length).to eq(2)
      expect(tools[0].name).to eq('test-tool-1')
      expect(tools[0].description).to eq('A test tool 1')
      expect(tools[0].input_schema).to eq(imperative_schema)
      expect(tools[0].annotations).to include('readOnly' => true, 'untrustedContent' => true)
      expect(tools[0].frame).to eq(page.main_frame)
      expect(tools[0].form_element).to be_nil
      expect(tools[0].location).not_to be_nil

      expect(tools[1].name).to eq('declarative tool name')
      expect(tools[1].description).to eq('tool description')
      expect(tools[1].input_schema).to eq(
        'type' => 'object',
        'properties' => {},
        'required' => [],
      )
      expect(tools[1].annotations).to include('autosubmit' => true)
      expect(tools[1].frame).to eq(page.main_frame)
      expect(tools[1].form_element).not_to be_nil
      expect(tools[1].location).to be_nil
    end
  end

  it 'should fire toolsadded events' do
    with_webmcp_test_state do |page:, **|
      imperative_added = event_promise(page.webmcp, 'toolsadded')
      register_imperative_tool(page)
      added_tools = imperative_added.wait.tools
      expect(added_tools.length).to eq(1)
      expect(added_tools.first.name).to eq('test-tool-1')
      expect(added_tools.first.description).to eq('A test tool 1')
      expect(added_tools.first.input_schema).to eq(imperative_schema)
      expect(added_tools.first.annotations).to be_nil
      expect(added_tools.first.frame).to eq(page.main_frame)
      expect(added_tools.first.form_element).to be_nil
      expect(added_tools.first.location).not_to be_nil

      declarative_added = event_promise(page.webmcp, 'toolsadded')
      register_declarative_tool(page)
      added_tools = declarative_added.wait.tools
      expect(added_tools.length).to eq(1)
      expect(added_tools.first.name).to eq('declarative tool name')
      expect(added_tools.first.description).to eq('tool description')
      expect(added_tools.first.annotations).to be_nil
      expect(added_tools.first.input_schema).to eq(
        'type' => 'object',
        'properties' => {},
        'required' => [],
      )
      expect(added_tools.first.frame).to eq(page.main_frame)
      expect(added_tools.first.form_element).not_to be_nil
      expect(added_tools.first.location).to be_nil
    end
  end

  it 'should fire toolsremoved events' do
    with_webmcp_test_state do |page:, **|
      tool_added = event_promise(page.webmcp, 'toolsadded')
      controller = page.evaluate_handle(<<~JAVASCRIPT)
        () => {
          const controller = new AbortController();
          void document.modelContext.registerTool({
            name: 'test-tool-1',
            description: 'A test tool 1',
            inputSchema: {
              type: 'object',
              properties: {text: {type: 'string', description: 'Some text'}},
              required: ['text'],
            },
            execute: () => {},
          }, {signal: controller.signal});
          return controller;
        }
      JAVASCRIPT
      tool_added.wait

      imperative_removed = event_promise(page.webmcp, 'toolsremoved')
      controller.evaluate('controller => controller.abort()')
      removed_tools = imperative_removed.wait.tools
      expect(removed_tools.length).to eq(1)
      expect(removed_tools.first.name).to eq('test-tool-1')
      expect(removed_tools.first.description).to eq('A test tool 1')
      expect(removed_tools.first.input_schema).to eq(imperative_schema)
      expect(removed_tools.first.annotations).to be_nil
      expect(removed_tools.first.frame).to eq(page.main_frame)
      expect(removed_tools.first.form_element).to be_nil
      expect(removed_tools.first.location).not_to be_nil
      controller.dispose

      declarative_added = event_promise(page.webmcp, 'toolsadded')
      register_declarative_tool(page)
      declarative_added.wait
      declarative_removed = event_promise(page.webmcp, 'toolsremoved')
      page.evaluate("() => document.querySelector('form').remove()")
      removed_tools = declarative_removed.wait.tools
      expect(removed_tools.length).to eq(1)
      expect(removed_tools.first.name).to eq('declarative tool name')
      expect(removed_tools.first.description).to eq('tool description')
      expect(removed_tools.first.input_schema).to eq(
        'type' => 'object',
        'properties' => {},
        'required' => [],
      )
      expect(removed_tools.first.annotations).to be_nil
      expect(removed_tools.first.frame).to eq(page.main_frame)
      expect(removed_tools.first.form_element).not_to be_nil
      expect(removed_tools.first.location).to be_nil
    end
  end

  it 'should remove tools on frame navigation' do
    with_webmcp_test_state do |page:, https_server:, **|
      added = event_promise(page.webmcp, 'toolsadded')
      register_declarative_tool(page)
      added.wait
      removed = event_promise(page.webmcp, 'toolsremoved')

      page.goto(https_server.empty_page)
      removed_tools = removed.wait.tools
      expect(removed_tools.length).to eq(1)
      expect(removed_tools.first.name).to eq('declarative tool name')
      expect(page.webmcp.tools).to be_empty
    end
  end

  it 'should handle multiple navigations and report tools correctly' do
    with_webmcp_test_state do |page:, https_server:, **|
      added = event_promise(page.webmcp, 'toolsadded')
      register_declarative_tool(page, name: 'tool-1', description: 'desc-1')
      added.wait
      expect(page.webmcp.tools.map(&:name)).to eq(['tool-1'])

      removed = event_promise(page.webmcp, 'toolsremoved')
      page.goto(https_server.empty_page)
      removed.wait
      expect(page.webmcp.tools).to be_empty

      added = event_promise(page.webmcp, 'toolsadded')
      register_declarative_tool(page, name: 'tool-2', description: 'desc-2')
      added.wait
      expect(page.webmcp.tools.map(&:name)).to eq(['tool-2'])

      removed = event_promise(page.webmcp, 'toolsremoved')
      page.goto(https_server.empty_page)
      removed.wait
      expect(page.webmcp.tools).to be_empty
    end
  end

  it 'should not reset tools on same-document navigation' do
    with_webmcp_test_state do |page:, https_server:, **|
      added = event_promise(page.webmcp, 'toolsadded')
      register_declarative_tool(page)
      added.wait
      expect(page.webmcp.tools.length).to eq(1)
      page.goto("#{https_server.empty_page}#hash")

      expect(page.webmcp.tools.length).to eq(1)
      expect(page.webmcp.tools.map(&:name)).to eq(['declarative tool name'])
    end
  end

  it 'should fire toolinvoked events' do
    with_webmcp_test_state do |page:, **|
      added = event_promise(page.webmcp, 'toolsadded')
      register_imperative_tool(page)
      tool = added.wait.tools.first
      tool_called = event_promise(page.webmcp, 'toolinvoked')
      added_tool_called = event_promise(tool, 'toolinvoked')

      page.evaluate(<<~JAVASCRIPT)
        async () => {
          const [tool] = await navigator.modelContext.getTools();
          navigator.modelContext.executeTool(tool, JSON.stringify({text: 'test'}));
        }
      JAVASCRIPT
      tool_call = tool_called.wait
      added_tool_call = added_tool_called.wait
      [tool_call, added_tool_call].each do |call|
        expect(call.id).not_to be_nil
        expect(call.tool.name).to eq('test-tool-1')
        expect(call.tool.description).to eq('A test tool 1')
        expect(call.tool.input_schema).to eq(imperative_schema)
        expect(call.tool.frame).to eq(page.main_frame)
        expect(call.tool.form_element).to be_nil
        expect(call.tool.location).not_to be_nil
        expect(call.input).to eq('text' => 'test')
      end
    end
  end

  it 'should fire toolresponded event with success' do
    with_webmcp_test_state do |page:, **|
      register_imperative_tool(page, execute: 'params => `hello ${params.text}`')
      tool_called = event_promise(page.webmcp, 'toolinvoked')
      tool_responded = event_promise(page.webmcp, 'toolresponded')

      execute_page_tool(page, JSON.generate('text' => 'world'))
      call = tool_called.wait
      response = tool_responded.wait
      expect(response.id).to eq(call.id)
      expect(response.call).to equal(call)
      expect(response.status).to eq('Completed')
      expect(response.output).to eq('hello world')
      expect(response.error_text).to be_nil
      expect(response.exception).to be_nil
    end
  end

  it 'should fire toolresponded event with exception' do
    with_webmcp_test_state do |page:, **|
      page.evaluate(<<~JAVASCRIPT)
        () => {
          void document.modelContext.registerTool({
            name: 'raise-exception-tool',
            description: 'A tool that raises JS exception',
            execute: () => { throw new Error('sorry!'); },
          });
        }
      JAVASCRIPT
      tool_called = event_promise(page.webmcp, 'toolinvoked')
      tool_responded = event_promise(page.webmcp, 'toolresponded')

      execute_page_tool(page, '{}')
      call = tool_called.wait
      response = tool_responded.wait
      expect(response.id).to eq(call.id)
      expect(response.call).to equal(call)
      expect(response.status).to eq('Error')
      expect(response.output).to be_nil
      expect(response.error_text).to eq('')
      expect(response.exception.fetch('description')).to include('sorry')
    end
  end

  it 'should fire toolresponded event with errorText' do
    with_webmcp_test_state do |page:, **|
      register_imperative_tool(page)
      tool_called = event_promise(page.webmcp, 'toolinvoked')
      tool_responded = event_promise(page.webmcp, 'toolresponded')

      execute_page_tool(page, 'invalid json')
      call = tool_called.wait
      response = tool_responded.wait
      expect(response.id).to eq(call.id)
      expect(response.call).to equal(call)
      expect(response.status).to eq('Error')
      expect(response.output).to be_nil
      expect(response.error_text).to eq('Failed to parse input arguments')
      expect(response.exception).to be_nil
    end
  end

  it 'should invoke tool' do
    with_webmcp_test_state do |page:, **|
      added = event_promise(page.webmcp, 'toolsadded')
      register_imperative_tool(page, execute: 'params => `hello ${params.text}`')
      tool = added.wait.tools.first
      tool_called = event_promise(page.webmcp, 'toolinvoked')

      response = tool.execute('text' => 'world')
      call = tool_called.wait
      expect(response.id).to eq(call.id)
      expect(response.call).to equal(call)
      expect(response.status).to eq('Completed')
      expect(response.output).to eq('hello world')
      expect(response.error_text).to be_nil
      expect(response.exception).to be_nil
    end
  end

  it 'should emit issue event from WebMCP form missing tooldescription' do
    with_webmcp_test_state do |page:, **|
      issue = async_promise { wait_for_event(page, 'issue') }
      page.set_content('<form toolname="mytool"></form>')
      result = issue.wait
      expect(result.code).to eq('GenericIssue')
      expect(result.details.dig('genericIssueDetails', 'errorType')).to eq(
        'FormModelContextMissingToolDescription',
      )
    end
  end

  def execute_page_tool(page, input)
    page.evaluate(<<~JAVASCRIPT, input)
      async input => {
        const [tool] = await navigator.modelContext.getTools();
        navigator.modelContext.executeTool(tool, input);
      }
    JAVASCRIPT
  end
end
