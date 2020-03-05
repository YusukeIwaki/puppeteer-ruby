require 'socket'
require 'websocket/driver'

# ref: https://github.com/rails/rails/blob/master/actioncable/lib/action_cable/connection/client_socket.rb
# ref: https://github.com/cavalle/chrome_remote/blob/master/lib/chrome_remote/web_socket_client.rb
class Puppeteer::WebSocket
  class DriverImpl # providing #url, #write(string)
    def initialize(url)
      @url = url

      endpoint = URI.parse(url)
      @socket = TCPSocket.new(endpoint.host, endpoint.port)
    end

    attr_reader :url

    def write(data)
      @socket.write(data)
    end

    def readpartial(maxlen = 1024)
      @socket.readpartial(maxlen)
    end
  end

  STATE_CONNECTING = 0
  STATE_OPENED = 1
  STATE_CLOSING = 2
  STATE_CLOSED = 3

  def initialize(url:, max_payload_size:)
    @impl = DriverImpl.new(url)
    @driver = ::WebSocket::Driver.client(@impl, max_length: max_payload_size)

    setup
    @driver.start
    wait_for_opened
  end

  private def setup
    @ready_state = STATE_CONNECTING
    @driver.on(:open) do
      @ready_state = STATE_OPENED
    end
    @driver.on(:close) do |event|
      @ready_state = STATE_CLOSED
      handle_on_close(reason: event.reason, code: event.code)
    end
    @driver.on(:error) do |event|
      if !handle_on_error(error_message: event.message)
        raise Puppeteer::WebSocktTransportError.new(event.message)
      end
    end
    @driver.on(:message) do |event|
      puts "on_message"
      handle_on_message(event.data)
    end
  end

  private def wait_for_opened
    wait_for_data until @ready_state >= STATE_OPENED
  end

  private def wait_for_data
    @driver.parse(@impl.readpartial)
  end

  # @param message [String]
  def send_text(message)
    return if @ready_state >= STATE_CLOSING
    @driver.text(message)
  end

  def read
    wait_for_data until first_message = @message_buffer.shift
    first_message
  end

  def close(code: 1000, reason: "")
    return if @ready_state >= STATE_CLOSING
    @ready_state = STATE_CLOSING
    @driver.close(reason, code)
  end

  # @param block [Proc(reason: String, code: Numeric)]
  def on_close(&block)
    @on_close = block
  end

  # @param block [Proc(error_message: String)]
  def on_error(&block)
    @on_error = block
  end

  def on_message(&block)
    @on_message = block
  end

  private def handle_on_close(reason:, code:)
    @on_close&.call(reason, code)
  end

  private def handle_on_error(error_message:)
    return false if @on_error.nil?

    @on_error.call(error_message)
    true
  end

  private def handle_on_message(data)
    return if @ready_state != STATE_OPENED

    @on_message&.call(data)
  end
end
