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
  end
end
