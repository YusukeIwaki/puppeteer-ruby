# rbs_inline: enabled

class Puppeteer::CDPSession
  include Puppeteer::DebugPrint
  include Puppeteer::EventCallbackable
  using Puppeteer::DefineAsyncMethod

  class Error < Puppeteer::Error; end

  # @rbs connection: Puppeteer::Connection -- CDP connection
  # @rbs target_type: String -- Target type
  # @rbs session_id: String -- CDP session id
  # @rbs return: void -- No return value
  def initialize(connection, target_type, session_id)
    @callbacks = {}
    @callbacks_mutex = Mutex.new
    @connection = connection
    @target_type = target_type
    @session_id = session_id
    @ready_promise = Async::Promise.new
    @target = nil
  end

  # @rbs return: String -- CDP session id
  def id
    @session_id
  end

  attr_reader :connection #: Puppeteer::Connection?
  attr_accessor :target #: Puppeteer::Target?

  # @rbs return: void -- Resolve session readiness
  def mark_ready
    @ready_promise.resolve(true) unless @ready_promise.resolved?
  end

  # @rbs return: bool -- True when session is ready
  def wait_for_ready
    @ready_promise.wait
  end

  # @rbs method: String -- CDP method name
  # @rbs params: Hash[String, untyped] -- CDP parameters
  # @rbs return: Hash[String, untyped] -- CDP response
  def send_message(method, params = {})
    async_send_message(method, params).wait
  end

  # @rbs method: String -- CDP method name
  # @rbs params: Hash[String, untyped] -- CDP parameters
  # @rbs return: Async::Promise[Hash[String, untyped]] -- Async CDP response
  def async_send_message(method, params = {})
    if !@connection
      raise Error.new("Protocol error (#{method}): Session closed. Most likely the #{@target_type} has been closed.")
    end

    promise = Async::Promise.new

    @connection.generate_id do |id|
      @callbacks_mutex.synchronize do
        @callbacks[id] = Puppeteer::Connection::MessageCallback.new(method: method, promise: promise)
      end
      @connection.raw_send(id: id, message: { sessionId: @session_id, method: method, params: params })
    end

    promise
  end

  # @rbs message: Hash[String, untyped] -- Raw CDP message
  # @rbs return: void -- No return value
  def handle_message(message)
    if message['id']
      if callback = @callbacks_mutex.synchronize { @callbacks.delete(message['id']) }
        callback_with_message(callback, message)
      else
        raise Error.new("unknown id: #{message['id']}")
      end
    else
      emit_event(message['method'], message['params'])
    end
  end

  private def callback_with_message(callback, message)
    if message['error']
      callback.reject(
        Puppeteer::Connection::ProtocolError.new(
          method: callback.method,
          error_message: message['error']['message'],
          error_data: message['error']['data']))
    else
      callback.resolve(message['result'])
    end
  end

  # @rbs return: void -- Detach the session
  def detach
    if !@connection
      raise Error.new("Session already detarched. Most likely the #{@target_type} has been closed.")
    end
    @connection.send_message('Target.detachFromTarget',  sessionId: @session_id)
  end

  # @rbs return: void -- Close the session and reject pending callbacks
  def handle_closed
    callbacks = @callbacks_mutex.synchronize do
      @callbacks.values.tap { @callbacks.clear }
    end
    callbacks.each do |callback|
      callback.reject(
        Puppeteer::Connection::ProtocolError.new(
          method: callback.method,
          error_message: 'Target Closed.'))
    end
    @ready_promise.reject(Error.new("Session closed")) unless @ready_promise.resolved?
    @connection = nil
    emit_event(CDPSessionEmittedEvents::Disconnected)
  end

  # @rbs event_name: String -- CDP event name
  # @rbs &block: ^(untyped) -> void -- Event handler
  # @rbs return: String -- Listener id
  def on(event_name, &block)
    add_event_listener(event_name, &block)
  end

  # @rbs event_name: String -- CDP event name
  # @rbs &block: ^(untyped) -> void -- Event handler
  # @rbs return: String -- Listener id
  def once(event_name, &block)
    observe_first(event_name, &block)
  end
end
