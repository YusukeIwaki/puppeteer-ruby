require 'spec_helper'
require 'base64'
require 'digest'
require 'socket'

# Minimal WebSocket server that completes the handshake, counts ping
# frames, and never answers them, like a peer that died without a TCP FIN.
class NonPongingWsServer
  WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

  def initialize
    @mutex = Mutex.new
    @pings = 0
    @server = TCPServer.new('127.0.0.1', 0)
    @thread = Thread.new { serve }
  end

  def url
    "ws://127.0.0.1:#{@server.addr[1]}/"
  end

  def ping_count
    @mutex.synchronize { @pings }
  end

  def close
    @server.close rescue nil
    @thread.join(2)
  end

  private def serve
    loop do
      socket = @server.accept
      Thread.new { handle(socket) }
    end
  rescue IOError
    # Server closed; ignore.
  end

  private def handle(socket)
    request = +''
    while (line = socket.gets) && line != "\r\n"
      request << line
    end
    key = request[/sec-websocket-key: (.+?)\r/i, 1]&.strip
    accept = Base64.strict_encode64(Digest::SHA1.digest("#{key}#{WS_GUID}"))
    socket.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{accept}\r\n\r\n")
    loop do
      header = socket.read(2)
      break unless header && header.bytesize == 2

      opcode = header.getbyte(0) & 0x0F
      length = header.getbyte(1) & 0x7F
      length = socket.read(2).unpack1('n') if length == 126
      length = socket.read(8).unpack1('Q>') if length == 127
      socket.read(4) if (header.getbyte(1) & 0x80) != 0 # mask key
      socket.read(length) if length > 0
      if opcode == 0x9 # ping
        @mutex.synchronize { @pings += 1 }
      elsif opcode == 0x8 # close
        break
      end
    end
  rescue IOError, SystemCallError
    # Client went away; ignore.
  ensure
    socket.close rescue nil
  end
end

RSpec.describe Puppeteer::WebSocketTransport do
  def connect_in_reactor(transport, timeout: 5)
    runner = Puppeteer::ReactorRunner.new
    runner.sync do
      Async::Task.current.with_timeout(timeout) do
        promise = transport.connect
        Puppeteer::AsyncUtils.await(promise)
      ensure
        transport.close
      end
    end
  ensure
    runner&.close
  end

  describe 'HTTP/2 ALPN behavior' do
    let(:unsafe_transport_class) do
      Class.new(Puppeteer::WebSocketTransport) do
        def initialize(url)
          @url = url
          @endpoint = Async::HTTP::Endpoint.parse(url)
          @connection = nil
          @task = nil
          @closed = false
          @connected = false
          @on_message = nil
          @on_close = nil
          @connect_promise = nil
          @write_mutex = Mutex.new
        end
      end
    end

    it 'fails with HTTP/2 websocket when ALPN is not forced', ws_http2: true do
      transport = unsafe_transport_class.new(ws_http2_server.url)

      expect { connect_in_reactor(transport) }.to raise_error(Protocol::HTTP::Error)
    end

    it 'connects successfully by forcing HTTP/1.1', ws_http2: true do
      transport = described_class.new(ws_http2_server.url)

      expect { connect_in_reactor(transport) }.not_to raise_error

      expect(ws_http2_server.last_request_version).to eq('HTTP/1.1')
    end
  end

  describe 'keep-alive' do
    def with_reactor(&block)
      runner = Puppeteer::ReactorRunner.new
      runner.sync(&block)
    ensure
      runner&.close
    end

    it 'closes the transport when the peer stops answering pings' do
      server = NonPongingWsServer.new
      begin
        with_reactor do
          transport = described_class.new(server.url, ws_options: { keep_alive: true, keep_alive_interval_ms: 50 })
          closed_promise = Async::Promise.new
          transport.on_close { closed_promise.resolve(true) unless closed_promise.resolved? }
          transport.connect.wait
          Async::Task.current.with_timeout(10) { closed_promise.wait }
          expect(transport.closed?).to eq(true)
          expect(server.ping_count).to be >= 1
        end
      ensure
        server.close
      end
    end

    it 'stays open while the peer answers pings' do
      Puppeteer.launch(**default_launch_options) do |browser|
        with_reactor do
          transport = described_class.new(
            browser.ws_endpoint,
            ws_options: { keep_alive: true, keep_alive_interval_ms: 50 },
          )
          closed = false
          transport.on_close { closed = true }
          transport.connect.wait
          Async::Task.current.sleep(0.3)
          expect(closed).to eq(false)
          expect(transport.connected?).to eq(true)
          transport.close
        end
      end
    end

    it 'does not ping when keepAlive is not enabled' do
      server = NonPongingWsServer.new
      begin
        with_reactor do
          transport = described_class.new(server.url)
          closed = false
          transport.on_close { closed = true }
          transport.connect.wait
          Async::Task.current.sleep(0.3)
          expect(server.ping_count).to eq(0)
          expect(closed).to eq(false)
          transport.close
        end
      ensure
        server.close
      end
    end
  end
end
