class Puppeteer::CDPSession
  include Puppeteer::EventCallbackable
  using Puppeteer::AsyncAwaitBehavior

  class Error < StandardError ; end

  # @param {!Connection} connection
  # @param {string} targetType
  # @param {string} sessionId
  def initialize(connection, target_type, session_id)
    @callbacks = {}
    @connection = connection
    @target_type = target_type
    @session_id = session_id
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
    id = @connection.raw_send(message: { sessionId: @session_id, method: method, params: params })
    promise = resolvable_future
    @callbacks[id] = Puppeteer::Connection::MessageCallback.new(method: method, promise: promise)
    promise
  end

  # @param {{id?: number, method: string, params: Object, error: {message: string, data: any}, result?: *}} object
  def handle_message(message)
    if message['id']
      if callback = @callbacks.delete(message['id'])
        if message['error']
          callback.reject(
            Puppeteer::Connection::ProtocolError.new(
              method: callback.method,
              error_message: response['error']['message'],
              error_data: response['error']['data']))
        else
          callback.resolve(message['result'])
        end
      else
        raise Error.new("unknown id: #{message['id']}")
      end
    else
      emit_event message['method'], message['params']
    end
  end

  def detach
    if !@connection
      raise Error.new("Session already detarched. Most likely the #{@target_type} has been closed.")
    end
    @connection.send_message('Target.detachFromTarget',  sessionId: @session_id)
  end

  def handle_closed
    @callbacks.values.each do |callback|
      callback.reject(
        Puppeteer::Connection::ProtocolError.new(
          method: callback.method,
          error_message: 'Target Closed.'))
    end
    @callbacks.clear
    @connection = nil
    emit_event 'Events.CDPSession.Disconnected'
  end
end
