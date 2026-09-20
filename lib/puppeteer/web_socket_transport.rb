# frozen_string_literal: true

require "async"
require "async/http/endpoint"
require "async/websocket/client"

class Puppeteer::WebSocketTransport
  include Puppeteer::DebugPrint

  class ClosedError < Puppeteer::Error; end

  # How often to ping the browser when keep-alive is enabled, and how long to
  # wait for the matching pong before treating the connection as dead.
  DEFAULT_KEEP_ALIVE_INTERVAL_MS = 30_000

  # @param {string} url
  # @return [Puppeteer::WebSocketTransport]
  def self.create(url, headers: nil, ws_options: nil, logger: nil)
    transport = new(url, headers: headers, ws_options: ws_options, logger: logger)
    transport.connect.wait
    transport
  end

  def initialize(url, headers: nil, ws_options: nil, logger: nil)
    @url = url
    @headers = headers
    @ws_options = ws_options || {}
    @logger = logger
    # Force HTTP/1.1 for WebSocket connections.
    # Some servers (e.g., Google Cloud Run) advertise HTTP/2 via ALPN but don't
    # properly support WebSocket over HTTP/2 (RFC 8441), causing stream errors.
    @endpoint = Async::HTTP::Endpoint.parse(url, alpn_protocols: ["http/1.1"])
    @connection = nil
    @task = nil
    @closed = false
    @connected = false
    @on_message = nil
    @on_close = nil
    @connect_promise = nil
    @write_mutex = Mutex.new
    @keep_alive_task = nil
  end

  def connect
    return @connect_promise if @connect_promise

    @connect_promise = Async::Promise.new
    @task = Async do |task|
      Async::WebSocket::Client.connect(@endpoint, headers: @headers) do |connection|
        @connection = connection
        @connected = true
        @connect_promise.resolve(true) unless @connect_promise.resolved?
        start_keep_alive(connection) if @ws_options && @ws_options[:keep_alive]
        receive_loop(connection)
      end
    rescue Async::Stop
      # Task was stopped; ignore.
    rescue => err
      if @connect_promise.resolved?
        # Silently log post-connect errors; there is nothing else to do
        # with them (mirrors upstream's socket error handler).
        log_error(err)
      else
        @connect_promise.reject(err)
      end
      close
    ensure
      @connected = false
    end

    @connect_promise
  end

  # @param message [String]
  def send_text(message)
    raise ClosedError.new("Transport is closed") if @closed

    @write_mutex.synchronize do
      @connection&.write(message)
      @connection&.flush
    end
  rescue IOError, Errno::ECONNRESET, Errno::EPIPE
    close
    raise
  end

  def close
    return if @closed

    @closed = true
    stop_keep_alive
    begin
      @connection&.close
    rescue Async::Stop
      # Connection already closing; ignore.
    end
    @on_close&.call(nil, nil)
    begin
      @task&.stop
    rescue Async::Stop
      # Task was already stopping; ignore.
    end
  rescue IOError, Errno::ECONNRESET, Errno::EPIPE
    @on_close&.call(nil, nil)
  end

  def on_close(&block)
    @on_close = block
  end

  def on_message(&block)
    @on_message = block
  end

  def connected?
    @connected && !@closed
  end

  def closed?
    @closed
  end

  # The peer only reports a close when it sends a TCP FIN. A connection
  # dropped by a proxy, a load balancer reaping an idle socket, or a killed
  # remote browser leaves a half-open socket that never reports `close`, so
  # ping periodically and terminate when the pong for the previous ping never
  # arrived.
  private def start_keep_alive(connection)
    interval = ((@ws_options[:keep_alive_interval_ms] || DEFAULT_KEEP_ALIVE_INTERVAL_MS) / 1000.0)
    state = { awaiting_pong: false }
    connection.define_singleton_method(:receive_pong) do |_frame|
      state[:awaiting_pong] = false
    end
    @keep_alive_task = Async do |task|
      loop do
        task.sleep(interval)
        break if @closed
        if state[:awaiting_pong]
          # Close rather than handshaking: the peer is not answering, so a
          # close handshake would hang. This surfaces the dead connection.
          close
          break
        end
        state[:awaiting_pong] = true
        begin
          @write_mutex.synchronize do
            @connection&.send_ping
            @connection&.flush
          end
        rescue IOError, Errno::ECONNRESET, Errno::EPIPE
          close
          break
        end
      end
    end
  end

  private def stop_keep_alive
    task = @keep_alive_task
    @keep_alive_task = nil
    return unless task
    return if task.current?

    begin
      task.stop
    rescue Async::Stop
      # Task was already stopping; ignore.
    end
  end

  private def receive_loop(connection)
    while (message = connection.read)
      next if message.nil?

      @on_message&.call(message.to_str)
    end
  rescue Async::Stop
    # Task stopped; no-op.
  rescue IOError, Errno::ECONNRESET, Errno::EPIPE => err
    # Connection dropped; report it like upstream's socket error handler.
    log_error(err)
  ensure
    close unless @closed
  end

  # Forwards errors to the custom error logger (when configured) while
  # preserving the traditional DEBUG output.
  private def log_error(error)
    @logger&.call(Puppeteer::DebugPrefixes::ERROR)&.call(error)
    debug_puts(error)
  end
end
