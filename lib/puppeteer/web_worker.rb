# frozen_string_literal: true
# rbs_inline: enabled

class Puppeteer::WorkerWorld
  using Puppeteer::DefineAsyncMethod

  # @rbs client: Puppeteer::CDPSession -- CDP session
  def initialize(client)
    @client = client
    @context_promise = Async::Promise.new
    @task_manager = Puppeteer::TaskManager.new
    @disposed = false
  end

  attr_reader :task_manager

  # @rbs context: Puppeteer::ExecutionContext -- Execution context to bind
  # @rbs return: void -- No return value
  def set_context(context)
    @context_promise.resolve(context) unless @context_promise.resolved?
  end

  # @rbs return: Puppeteer::ExecutionContext -- Worker execution context
  def execution_context
    if @disposed
      raise Puppeteer::WaitTask::TerminatedError.new(
        'waitForFunction failed: worker got detached.',
      )
    end
    @context_promise.wait
  end

  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs return: untyped -- Evaluation result
  def evaluate(page_function, *args)
    execution_context.evaluate(page_function, *args)
  end

  define_async_method :async_evaluate

  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs return: Puppeteer::JSHandle -- Handle to evaluation result
  def evaluate_handle(page_function, *args)
    execution_context.evaluate_handle(page_function, *args)
  end

  define_async_method :async_evaluate_handle

  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs polling: (Integer | String)? -- Polling interval or mode
  # @rbs timeout: Integer? -- Maximum wait time in milliseconds
  # @rbs return: Puppeteer::JSHandle -- Handle to the truthy evaluation result
  def wait_for_function(page_function, args: [], polling: nil, timeout: nil)
    runner = lambda do
      wait_task = Puppeteer::WaitTask.new(
        dom_world: self,
        predicate_body: page_function,
        title: 'function',
        polling: polling || 100,
        timeout: timeout.nil? ? 30_000 : timeout,
        args: args,
      )
      wait_task.await_promise
    end
    return runner.call if Async::Task.current?

    Sync { runner.call }
  end

  define_async_method :async_wait_for_function

  # @rbs return: nil -- Workers do not have frames
  def frame
    nil
  end

  # @rbs return: void -- Dispose world resources
  def dispose
    return if @disposed

    @disposed = true
    error = Puppeteer::WaitTask::TerminatedError.new(
      'waitForFunction failed: worker got detached.',
    )
    @context_promise.reject(error) unless @context_promise.resolved?
    @task_manager.terminate_all(error)
  end

  def detached?
    @disposed
  end
end

class Puppeteer::WebWorker
  include Puppeteer::EventCallbackable
  using Puppeteer::DefineAsyncMethod

  # @rbs url: String -- Worker URL
  def initialize(url)
    @url = url
    @timeout_settings = Puppeteer::TimeoutSettings.new
  end

  # @rbs return: Puppeteer::TimeoutSettings -- Timeout settings
  attr_reader :timeout_settings

  # @rbs return: String -- Worker URL
  def url
    @url
  end

  # @rbs return: Puppeteer::WorkerWorld -- Main realm
  def main_realm
    raise NotImplementedError
  end

  # @rbs return: Puppeteer::CDPSession -- CDP session
  def client
    raise NotImplementedError
  end

  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs return: untyped -- Evaluation result
  def evaluate(page_function, *args)
    main_realm.evaluate(page_function, *args)
  end

  define_async_method :async_evaluate

  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs return: Puppeteer::JSHandle -- Handle to evaluation result
  def evaluate_handle(page_function, *args)
    main_realm.evaluate_handle(page_function, *args)
  end

  define_async_method :async_evaluate_handle

  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs polling: (Integer | String)? -- Polling interval or mode
  # @rbs timeout: Integer? -- Maximum wait time in milliseconds
  # @rbs return: Puppeteer::JSHandle -- Handle to the truthy evaluation result
  def wait_for_function(page_function, args: [], polling: nil, timeout: nil)
    main_realm.wait_for_function(
      page_function,
      args: args,
      polling: polling || 100,
      timeout: timeout.nil? ? @timeout_settings.timeout : timeout,
    )
  end

  define_async_method :async_wait_for_function

  # @rbs return: void -- Not supported
  def close
    raise Puppeteer::Error.new('WebWorker.close() is not supported')
  end
end

class Puppeteer::CdpWebWorker < Puppeteer::WebWorker
  include Puppeteer::DebugPrint

  # @rbs client: Puppeteer::CDPSession -- Worker CDP session
  # @rbs url: String -- Worker URL
  # @rbs target_id: String -- Target ID
  # @rbs target_type: String -- Target type
  # @rbs console_api_called: Proc? -- Console callback
  # @rbs exception_thrown: Proc? -- Exception callback
  # @rbs network_manager: untyped? -- Network manager for worker requests
  def initialize(client, url, target_id, target_type, console_api_called, exception_thrown, network_manager: nil)
    super(url)
    @client = client
    @target_id = target_id
    @target_type = target_type
    @world = Puppeteer::WorkerWorld.new(@client)
    @worker_loaded_promise = Async::Promise.new

    @client.once('Runtime.executionContextCreated') do |event|
      @world.set_context(Puppeteer::ExecutionContext.new(@client, event['context'], @world))
    end
    @client.once('Inspector.workerScriptLoaded') do
      @worker_loaded_promise.resolve(nil) unless @worker_loaded_promise.resolved?
    end
    @client.on_event('Runtime.consoleAPICalled') do |event|
      values = event['args'].map do |arg|
        remote_object = Puppeteer::RemoteObject.new(arg)
        Puppeteer::JSHandle.create(context: @world.execution_context, remote_object: remote_object)
      end
      console_api_called&.call(@world, event)
      emit_event(
        'console',
        Puppeteer::ConsoleMessage.new(
          event['type'],
          values.map { |value| console_value_from_js_handle(value) }.join(' '),
          values,
          console_message_locations(event['stackTrace']),
        ),
      )
    end
    if exception_thrown
      @client.on_event('Runtime.exceptionThrown') do |event|
        exception_thrown.call(event['exceptionDetails'])
      end
    end
    @client.once(CDPSessionEmittedEvents::Disconnected) do
      @world.dispose
    end

    if network_manager
      Async do
        network_manager.add_client(@client)
      rescue => err
        debug_puts(err)
      end
    end

    @client.async_send_message('Runtime.enable')
  end

  # @rbs return: Puppeteer::WorkerWorld -- Main realm
  def main_realm
    @world
  end

  # @rbs return: Puppeteer::CDPSession -- Worker CDP session
  def client
    @client
  end

  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs return: untyped -- Evaluation result
  def evaluate(page_function, *args)
    @worker_loaded_promise.wait
    super
  end

  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs return: Puppeteer::JSHandle -- Handle to evaluation result
  def evaluate_handle(page_function, *args)
    @worker_loaded_promise.wait
    super
  end

  # @rbs page_function: String -- Function or expression to evaluate
  # @rbs args: Array[untyped] -- Arguments for evaluation
  # @rbs polling: (Integer | String)? -- Polling interval or mode
  # @rbs timeout: Integer? -- Maximum wait time in milliseconds
  # @rbs return: Puppeteer::JSHandle -- Handle to the truthy evaluation result
  def wait_for_function(page_function, args: [], polling: nil, timeout: nil)
    @worker_loaded_promise.wait
    super
  end

  private def console_value_from_js_handle(handle)
    remote_object = handle.remote_object
    return remote_object.value unless remote_object.object_id?

    description = remote_object.description.to_s
    if remote_object.sub_type == 'error' && !description.empty?
      newline_index = description.index("\n")
      return newline_index ? description[0...newline_index] : description
    end

    type = remote_object.sub_type || remote_object.type
    class_name = remote_object.class_name || remote_object.description || 'Object'
    "[#{type} #{class_name}]"
  end

  private def console_message_locations(stack_trace)
    return [] unless stack_trace && stack_trace['callFrames']

    stack_trace['callFrames'].map do |call_frame|
      Puppeteer::ConsoleMessage::Location.new(
        url: call_frame['url'],
        line_number: call_frame['lineNumber'],
        column_number: call_frame['columnNumber'],
      )
    end
  end

  # @rbs return: void -- Close the worker
  def close
    connection = @client.connection
    case @target_type
    when 'service_worker'
      connection&.send_message('Target.closeTarget', targetId: @target_id)
      connection&.send_message('Target.detachFromTarget', sessionId: @client.id)
    when 'shared_worker'
      connection&.send_message('Target.closeTarget', targetId: @target_id)
    else
      evaluate('() => self.close()')
    end
  end
end
