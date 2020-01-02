class Puppeteer::CDPSession
  include Puppeteer::EventCallbackable

  class Error < StandardError ; end

  # @param {!Connection} connection
  # @param {string} targetType
  # @param {string} sessionId
  def initialize(connection, target_type, session_id)
    @connection = connection
    @target_type = target_type
    @session_id = session_id
  end

  attr_reader :connection

  # @param {string} method
  # @param {!Object=} params
  # @return {!Promise<?Object>}
  def send_message(method, params = {})
    if !@connection
      raise Error.new("Protocol error (#{method}): Session closed. Most likely the #{@target_type} has been closed.")
    end
    @connection.raw_send(message: { sessionId: @session_id, method: method, params: params })
  end

  # @param {{id?: number, method: string, params: Object, error: {message: string, data: any}, result?: *}} object
  def handle_message(message)
    if message['id']
      # handled in raw_read
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
    @connection = nil
    emit_event 'Events.CDPSession.Disconnected'
  end
end
