require 'spec_helper'

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

      expect { connect_in_reactor(transport) }.to raise_error(Protocol::HTTP2::StreamError)
    end

    it 'connects successfully by forcing HTTP/1.1', ws_http2: true do
      transport = described_class.new(ws_http2_server.url)

      expect { connect_in_reactor(transport) }.not_to raise_error

      expect(ws_http2_server.last_request_version).to eq('HTTP/1.1')
    end
  end
end
