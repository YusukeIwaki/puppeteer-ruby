class Puppeteer::WebSocketTransport
  # @param {string} url
  # @return [Puppeteer::WebSocketTransport]
  def self.create(url)
    ws = Puppeteer::WebSocket.new(
      url: url,
      max_payload_size: 256 * 1024 * 1024, # 256MB
    )
    Concurrent::Promises.resolvable_future.tap do |future|
      ws.on_open do
        future.fulfill(Puppeteer::WebSocketTransport.new(ws))
      end
      ws.on_error do |error_message|
        future.reject(Puppeteer::WebSocket::TransportError.new(error_message))
      end
    end.value!
  end

  # @param {!WebSocket::Driver} web_socket
  def initialize(web_socket)
    @ws = web_socket
    @ws.on_message do |data|
      @on_message&.call(data)
    end
    @ws.on_close do |reason, code|
      @on_close&.call(reason, code)
    end
    @ws.on_error do |error|
      # Silently ignore all errors - we don't know what to do with them.
    end
  end

  # @param message [String]
  def send_text(message)
    @ws.send_text(message)
  end

  def close
    @ws.close
  rescue EOFError
    # ignore EOLError. The connection is already closed.
  end

  def on_close(&block)
    @on_close = block
  end

  def on_message(&block)
    @on_message = block
  end
end
