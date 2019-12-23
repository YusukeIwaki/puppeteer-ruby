require 'json'

class Puppeteer::Connection
  def initialize(url, transport, delay = 0)
    @url = url
    @last_id = 0
    @delay = delay

    @transport = transport

    @closed = false
  end

  #  /**
  #   * @param {!CDPSession} session
  #   * @return {!Connection}
  #   */
  #  static fromSession(session) {
  #    return session._connection;
  #  }

  #  /**
  #   * @param {string} sessionId
  #   * @return {?CDPSession}
  #   */
  #  session(sessionId) {
  #    return this._sessions.get(sessionId) || null;
  #  }

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
    puts "SEND >> #{payload}"
    read_until{ |message| message["id"] == id }["result"]
  end

  private def raw_read
    message = JSON.parse(@transport.read)
    puts "RECV << #{message}"
    message
  end

  private def read_until(&predicate)
    loop do
      message = raw_read
      if predicate.call(message)
        return message
      end
    end
  end

  private def handle_on_close

  end

  def dispose
    handle_on_close
    @transport.close
  end
end
