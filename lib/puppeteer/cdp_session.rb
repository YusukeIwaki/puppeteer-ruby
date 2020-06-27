class Puppeteer::CDPSession
  include Puppeteer::DebugPrint
  include Puppeteer::EventCallbackable
  using Puppeteer::DefineAsyncMethod

  class Error < StandardError; end

  # @param {!Connection} connection
  # @param {string} targetType
  # @param {string} sessionId
  def initialize(connection, target_type, session_id)
    @callbacks = {}
    @connection = connection
    @target_type = target_type
    @session_id = session_id
    @pending_messages = {}
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
    callback = Puppeteer::Connection::MessageCallback.new(method: method, promise: promise)
    if pending_message = @pending_messages.delete(id)
      debug_puts "Pending message (id: #{id}) is handled"
      callback_with_message(callback, pending_message)
    else
      @callbacks[id] = callback
    end
    promise
  end

  # @param {{id?: number, method: string, params: Object, error: {message: string, data: any}, result?: *}} object
  def handle_message(message)
    if message['id']
      if callback = @callbacks.delete(message['id'])
        callback_with_message(callback, message)
      else
        debug_puts "unknown id: #{id}. Store it into pending message"

        # RECV is often notified before SEND.
        # Wait about 10 frames before throwing an error.
        message_id = message['id']
        @pending_messages[message_id] = message
        Concurrent::Promises.schedule(0.16, message_id) do |id|
          if @pending_messages.delete(id)
            raise Error.new("unknown id: #{id}")
          end
        end
      end
    else
      emit_event message['method'], message['params']
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
    emit_event 'Events.CDPSession.Disconnected'
  end
end
