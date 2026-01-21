# frozen_string_literal: true

require "async"
require "async/http/endpoint"
require "async/websocket/client"

class Puppeteer::WebSocketTransport
  class ClosedError < Puppeteer::Error; end

  # @param {string} url
  # @return [Puppeteer::WebSocketTransport]
  def self.create(url)
    transport = new(url)
    transport.connect.wait
    transport
  end

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

  def connect
    return @connect_promise if @connect_promise

    @connect_promise = Async::Promise.new
    @task = Async do |task|
      Async::WebSocket::Client.connect(@endpoint) do |connection|
        @connection = connection
        @connected = true
        @connect_promise.resolve(true) unless @connect_promise.resolved?
        receive_loop(connection)
      end
    rescue Async::Stop
      # Task was stopped; ignore.
    rescue => err
      @connect_promise.reject(err) unless @connect_promise.resolved?
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

  private def receive_loop(connection)
    while (message = connection.read)
      next if message.nil?

      @on_message&.call(message.to_str)
    end
  rescue Async::Stop
    # Task stopped; no-op.
  rescue IOError, Errno::ECONNRESET, Errno::EPIPE
    # Connection closed; no-op.
  ensure
    close unless @closed
  end
end
