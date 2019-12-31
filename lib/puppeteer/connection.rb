require 'json'

class Puppeteer::Connection
  include Puppeteer::DebugPrint

  def initialize(url, transport, delay = 0)
    @url = url
    @last_id = 0
    @delay = delay

    @transport = transport
    @transport.on_message do |data|
      handle_message(JSON.parse(data))
    end
    @transport.on_close do |reason, code|
      @on_close&.call(reason, code)
    end

    @sessions = {}
    @closed = false
  end

  #  /**
  #   * @param {!CDPSession} session
  #   * @return {!Connection}
  #   */
  #  static fromSession(session) {
  #    return session._connection;
  #  }

  # @param {string} sessionId
  # @return {?CDPSession}
  def session(session_id)
    @sessions[session_id]
  end

  def url
    @url
  end

  # @param {string} method
  # @param {!Object=} params
  def send_message(method, params = {})
    raw_send(message: { method: method, params: params })
  end

  private def generate_id
    @last_id += 1
  end

  private def raw_send(message:)
    id = generate_id
    payload = JSON.fast_generate(message.merge(id: id))
    @transport.send_text(payload)
    debug_print "SEND >> #{payload}"
    read_until{ |message| message["id"] == id }["result"]
  end

  private def raw_read
    JSON.parse(@transport.read)
  end

  private def read_until(&predicate)
    loop do
      message = raw_read
      if predicate.call(message)
        return message
      end
    end
  end

  private def handle_message(message)
    if @delay > 0
      sleep(@delay / 1000)
    end
    debug_print "RECV << #{message}"

    case message['method']
    when 'Target.attachedToTarget'
      session_id = message['params']['sessionId']
      session = CDPSession.new(self, message['params']['targetInfo']['type'], session_id)
      @sessions[session_id] = session
    when 'Target.detachedFromTarget'
      session_id = message['params']['sessionId']
      session = @sessions[session_id]
      if session
        session._onClosed
        @sessions.delete(session_id)
      end
    end

    if message['sessionId']
      session_id = message['sessionId']
      @sessions[session_id]&._onMessage(message)
    elsif message['id']
      # handled in read_until
    else
      @on_message&.call(message)
    end
  end

  private def handle_on_close
    return if @closed
    @closed = true
    @transport.on_message
    @transport.on_close
    # for (const callback of this._callbacks.values())
    #   callback.reject(rewriteError(callback.error, `Protocol error (${callback.method}): Target closed.`));
    # this._callbacks.clear();
    # for (const session of this._sessions.values())
    #   session._onClosed();
    # this._sessions.clear();
    @on_connection_disconnected&.call
  end

  def on_close(&block)
    @on_close = block
  end

  def on_message(&block)
    @on_message = block
  end

  def on_connection_disconnected(&block)
    @on_connection_disconnected = block
  end

  def dispose
    handle_on_close
    @transport.close
  end

  # @param {Protocol.Target.TargetInfo} targetInfo
  # @return {!Promise<!CDPSession>}
  def create_session(target_info)
    result = send_message('Target.attachToTarget', targetId: target_info.target_id, flatten: true)
    session_id = result['sessionId']
    @sessions[session_id]
  end
end
