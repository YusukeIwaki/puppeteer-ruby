# frozen_string_literal: true

require 'async'
require 'async/http/server'
require 'async/http/client'
require 'async/http/endpoint'
require 'async/websocket/adapters/http'
require 'protocol/http/response'
require 'protocol/http/middleware'
require 'protocol/http2'
require 'openssl'
require 'socket'
require 'timeout'

module TestServer
  class WebSocketHTTP2Server
    attr_reader :port, :url, :last_request_version

    def initialize(path: '/ws')
      @path = path
      @port = find_available_port
      @url = "wss://localhost:#{@port}#{@path}"

      @server_thread = nil
      @server = nil

      @ready_mutex = Mutex.new
      @ready_condition = ConditionVariable.new
      @ready = false
      @server_error = nil
    end

    def start
      return if @server_thread&.alive?

      @server_thread = Thread.new do
        run_server
      rescue StandardError => error
        signal_server_failure(error)
      end

      wait_until_ready
      wait_for_server
    end

    def stop
      shutdown_server

      if @server_thread&.alive?
        @server_thread.join(1)
        if @server_thread.alive?
          @server_thread.kill
          @server_thread.join(1)
        end
      end
      @server_thread = nil

      @ready_mutex.synchronize do
        @ready = false
        @server_error = nil
      end
    end

    private def run_server
      Sync do
        ssl_context = OpenSSL::SSL::SSLContext.new
        ssl_context.cert = TestServer.ssl_context.cert
        ssl_context.key = TestServer.ssl_context.key
        ssl_context.alpn_protocols = ['h2', 'http/1.1']
        ssl_context.alpn_select_cb = lambda do |protocols|
          protocols.include?('h2') ? 'h2' : protocols.first
        end

        endpoint = Async::HTTP::Endpoint.parse(
          "https://localhost:#{@port}",
          ssl_context: ssl_context,
        )
        app = Protocol::HTTP::Middleware.for do |request|
          handle_request(request)
        end
        @server = Async::HTTP::Server.new(app, endpoint)

        signal_server_ready

        @server.run
      ensure
        @server&.close
      end
    end

    private def handle_request(request)
      if websocket_request?(request)
        @last_request_version = request.version

        if request.version.to_s.match?(/http\/2/i)
          # Simulate servers that advertise h2 but don't support WebSocket over HTTP/2.
          request.stream.send_reset_stream(::Protocol::HTTP2::Error::INTERNAL_ERROR)
          raise Async::Stop
        end

        return Async::WebSocket::Adapters::HTTP.open(request) do |connection|
          while (message = connection.read)
            connection.write(message)
          end
        end
      end

      Protocol::HTTP::Response[200, { 'content-type' => 'text/plain' }, ['OK']]
    end

    private def websocket_request?(request)
      Array(request.protocol).any? { |protocol| protocol.to_s.casecmp?('websocket') }
    end

    private def signal_server_ready
      @ready_mutex.synchronize do
        @ready = true
        @ready_condition.broadcast
      end
    end

    private def signal_server_failure(error)
      @ready_mutex.synchronize do
        @server_error = error
        @ready = true
        @ready_condition.broadcast
      end
    end

    private def wait_until_ready
      @ready_mutex.synchronize do
        @ready_condition.wait(@ready_mutex) unless @ready
      end
      raise @server_error if @server_error
    end

    private def wait_for_server
      endpoint = Async::HTTP::Endpoint.parse(
        "https://localhost:#{@port}",
        ssl_context: TestServer.client_ssl_context,
      )

      Sync do |task|
        task.with_timeout(5) do
          client = Async::HTTP::Client.new(endpoint)
          begin
            loop do
              begin
                response = client.get('/')
                status = response.status
                response.finish
                break if status < 500
              rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, Errno::ECONNRESET, SocketError
                task.sleep(0.05)
              end
            end
          ensure
            client.close
          end
        end
      end
    rescue Async::TimeoutError
      raise 'WebSocket HTTP/2 test server failed to start'
    end

    private def shutdown_server
      @server.close if @server&.respond_to?(:close)
      @server = nil
    end

    private def find_available_port
      server = TCPServer.new('127.0.0.1', 0)
      port = server.addr[1]
      server.close
      port
    end
  end
end
