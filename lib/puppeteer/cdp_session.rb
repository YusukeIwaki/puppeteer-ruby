class Puppeteer::CDPSession
  include Puppeteer::DebugPrint
  include Puppeteer::EventCallbackable
  using Puppeteer::DefineAsyncMethod

  class Error < Puppeteer::Error; end

  # @param {!Connection} connection
  # @param {string} targetType
  # @param {string} sessionId
  def initialize(connection, target_type, session_id)
    @callbacks = Concurrent::Hash.new
    @connection = connection
    @target_type = target_type
    @session_id = session_id
  end

  # @internal
  def id
    @session_id
  end

  attr_reader :connection

  # @param method [String]
  # @param params [Hash]
  # @returns [Hash]
  def send_message(method, params = {})
    await async_send_message(method, params)
  end

  # @param method [String]
  # @param params [Hash]
  # @returns [Future<Hash>]
  def async_send_message(method, params = {})
    if !@connection
      raise Error.new("Protocol error (#{method}): Session closed. Most likely the #{@target_type} has been closed.")
    end

    promise = resolvable_future

    @connection.generate_id do |id|
      @callbacks[id] = Puppeteer::Connection::MessageCallback.new(method: method, promise: promise)
      @connection.raw_send(id: id, message: { sessionId: @session_id, method: method, params: params })
    end

    promise
  end

  # @param {{id?: number, method: string, params: Object, error: {message: string, data: any}, result?: *}} object
  def handle_message(message)
    if message['id']
      if callback = @callbacks.delete(message['id'])
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

  def detach
    if !@connection
      raise Error.new("Session already detarched. Most likely the #{@target_type} has been closed.")
    end
    @connection.send_message('Target.detachFromTarget',  sessionId: @session_id)
  end

  def handle_closed
    @callbacks.each_value do |callback|
      callback.reject(
        Puppeteer::Connection::ProtocolError.new(
          method: callback.method,
          error_message: 'Target Closed.'))
    end
    @callbacks.clear
    @connection = nil
    emit_event(CDPSessionEmittedEvents::Disconnected)
  end

  # @param event_name [String]
  def on(event_name, &block)
    add_event_listener(event_name, &block)
  end

  # @param event_name [String]
  def once(event_name, &block)
    observe_first(event_name, &block)
  end
end
