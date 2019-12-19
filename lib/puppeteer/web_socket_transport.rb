require 'socket'
require 'websocket/driver'

class Puppeteer::WebSocketTransport
  class WebSocketDriverImpl # providing #url, #write(string)
    def initialize(url)
      @url = url

      endpoint = URI.parse(url)
      @socket = TCPSocket.new(endpoint.host, endpoint.port)
    end

    attr_reader :url

    def write(data)
      @socket.write(data)
    end
  end

  # @param {string} url
  # @return {!Promise<!WebSocketTransport>}
  def self.create(url)
    impl = WebSocketDriverImpl.new(url)
    max_payload_size = 256 * 1024 * 1024 # 256MB

    started = false
    error = nil
    web_socket = WebSocket::Driver.new(impl, max_length: max_payload_size)
    web_socket.on(:start) do
      started = true
    end
    web_socket.on(:error) do |err|
      error = err
    end

    until started || !err.nil?
      puts "waiting for start/error"
      sleep 0.1
    end
    raise err unless err.nil?
    web_socket
  end

  # @param {!WebSocket::Driver} web_socket
  def initialize(web_socket)
    @ws = web_socket
    @ws.on(:message) do |event|
      # this.onmessage.call(null, event.data); if (this.onmessage)
    end
    @ws.on(:close) do |event|
      # this.onclose.call(null); if (this.onclose)
    end

    #   this._ws.addEventListener('error', () => {});
    #   this.onmessage = null;
    #   this.onclose = null;

  end

  def send_message(message)
    @ws.send_message(message)
  end

  def close
    @ws.close
  end

  # close() {
  #   this._ws.close();
  # }
end
