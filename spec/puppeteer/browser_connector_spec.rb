require 'spec_helper'
require 'tmpdir'

RSpec.describe Puppeteer::BrowserConnector do
  let(:transport) { instance_double(Puppeteer::WebSocketTransport) }
  let(:connection) { instance_double(Puppeteer::Connection) }

  describe '#connection' do
    it 'connects to the DevToolsActivePort endpoint for a channel' do
      Dir.mktmpdir do |user_data_dir|
        File.write(File.join(user_data_dir, 'DevToolsActivePort'), "9222\n/devtools/browser/abc123\n")
        allow(Puppeteer::ChromeUserDataDir).to receive(:resolve_default).with('chrome').and_return(user_data_dir)

        expect(Puppeteer::WebSocketTransport).to receive(:create).with(
          'ws://localhost:9222/devtools/browser/abc123',
          headers: nil,
          ws_options: {},
        ).and_return(transport)
        expect(Puppeteer::Connection).to receive(:new).with(
          'ws://localhost:9222/devtools/browser/abc123',
          transport,
          25,
          protocol_timeout: 12,
        ).and_return(connection)

        result = described_class.new(
          channel: 'chrome',
          slow_mo: 25,
          protocol_timeout: 12,
        ).send(:connection)

        expect(result).to eq(connection)
      end
    end

    it 'ignores blank lines in DevToolsActivePort' do
      Dir.mktmpdir do |user_data_dir|
        File.write(File.join(user_data_dir, 'DevToolsActivePort'), "\n 9223 \n\n /devtools/browser/def456 \n")
        allow(Puppeteer::ChromeUserDataDir).to receive(:resolve_default).with('chrome-beta').and_return(user_data_dir)
        allow(Puppeteer::WebSocketTransport).to receive(:create).with(
          'ws://localhost:9223/devtools/browser/def456',
          headers: nil,
          ws_options: {},
        ).and_return(transport)
        allow(Puppeteer::Connection).to receive(:new).and_return(connection)

        expect(described_class.new(channel: 'chrome-beta').send(:connection)).to eq(connection)
      end
    end

    it 'wraps missing DevToolsActivePort errors with channel and path context' do
      Dir.mktmpdir do |user_data_dir|
        port_path = File.join(user_data_dir, 'DevToolsActivePort')
        allow(Puppeteer::ChromeUserDataDir).to receive(:resolve_default).with('chrome').and_return(user_data_dir)

        expect {
          described_class.new(channel: 'chrome').send(:connection)
        }.to raise_error(Puppeteer::Error, "Could not find DevToolsActivePort for chrome at #{port_path}")
      end
    end

    it 'wraps invalid DevToolsActivePort content errors' do
      Dir.mktmpdir do |user_data_dir|
        File.write(File.join(user_data_dir, 'DevToolsActivePort'), "9222\n")
        allow(Puppeteer::ChromeUserDataDir).to receive(:resolve_default).with('chrome').and_return(user_data_dir)

        expect {
          described_class.new(channel: 'chrome').send(:connection)
        }.to raise_error(Puppeteer::Error, /Could not find DevToolsActivePort for chrome/)
      end
    end

    it 'rejects multiple connection options' do
      expect {
        described_class.new(
          browser_ws_endpoint: 'ws://localhost:9222/devtools/browser/test',
          channel: 'chrome',
        ).send(:connection)
      }.to raise_error(
        ArgumentError,
        'Exactly one of browserWSEndpoint, browserURL, transport or channel must be passed to puppeteer.connect',
      )
    end

    describe 'ws_options' do
      it 'prefers ws_options headers over top-level headers' do
        ws_headers = { 'Authorization' => 'Bearer ws' }
        top_headers = { 'Authorization' => 'Bearer top' }
        websocket_url = 'ws://localhost:9222/devtools/browser/test'
        ws_options = { headers: ws_headers, keep_alive: true, keep_alive_interval_ms: 5000 }

        expect(Puppeteer::WebSocketTransport).to receive(:create).with(
          websocket_url,
          headers: ws_headers,
          ws_options: ws_options,
        ).and_return(transport)
        expect(Puppeteer::Connection).to receive(:new).and_return(connection)

        result = described_class.new(
          browser_ws_endpoint: websocket_url,
          headers: top_headers,
          ws_options: ws_options,
        ).send(:connection)

        expect(result).to eq(connection)
      end

      it 'forwards keep-alive options without headers' do
        websocket_url = 'ws://localhost:9222/devtools/browser/test'
        ws_options = { keep_alive: true }

        expect(Puppeteer::WebSocketTransport).to receive(:create).with(
          websocket_url,
          headers: nil,
          ws_options: ws_options,
        ).and_return(transport)
        expect(Puppeteer::Connection).to receive(:new).and_return(connection)

        result = described_class.new(
          browser_ws_endpoint: websocket_url,
          ws_options: ws_options,
        ).send(:connection)

        expect(result).to eq(connection)
      end
    end

    describe 'getWSEndpoint via browserURL' do
      it 'should forward headers to the /json/version HTTP request' do
        headers = { 'Authorization' => 'Bearer test-token' }
        browser_url = 'http://localhost:1234'
        websocket_url = 'ws://localhost:1234/devtools/browser/1'
        expected_uri = URI('http://localhost:1234/json/version')

        expect(Net::HTTP).to receive(:get).with(expected_uri, headers).and_return(
          JSON.generate('webSocketDebuggerUrl' => websocket_url),
        )
        expect(Puppeteer::WebSocketTransport).to receive(:create).with(
          websocket_url,
          headers: headers,
          ws_options: {},
        ).and_return(transport)
        expect(Puppeteer::Connection).to receive(:new).and_return(connection)

        result = described_class.new(
          browser_url: browser_url,
          headers: headers,
        ).send(:connection)

        expect(result).to eq(connection)
      end
    end
  end
end
