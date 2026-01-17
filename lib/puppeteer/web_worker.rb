# frozen_string_literal: true
# rbs_inline: enabled

class Puppeteer::WorkerWorld
  using Puppeteer::DefineAsyncMethod

  # @rbs client: Puppeteer::CDPSession -- CDP session
  def initialize(client)
    @client = client
    @context_promise = Async::Promise.new
  end

  # @rbs context: Puppeteer::ExecutionContext -- Execution context to bind
  # @rbs return: void -- No return value
  def set_context(context)
    @context_promise.resolve(context) unless @context_promise.resolved?
  end

  # @rbs return: Puppeteer::ExecutionContext -- Worker execution context
  def execution_context
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

  # @rbs return: nil -- Workers do not have frames
  def frame
    nil
  end

  # @rbs return: void -- Dispose world resources
  def dispose
    @context_promise = Async::Promise.new
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

    @client.once('Runtime.executionContextCreated') do |event|
      @world.set_context(Puppeteer::ExecutionContext.new(@client, event['context'], @world))
    end
    if console_api_called
      @client.on_event('Runtime.consoleAPICalled') do |event|
        console_api_called.call(@world, event)
      end
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
        begin
          network_manager.add_client(@client)
        rescue => err
          debug_puts(err)
        end
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
