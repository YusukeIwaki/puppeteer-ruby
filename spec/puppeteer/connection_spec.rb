require 'spec_helper'

RSpec.describe Puppeteer::Connection do
  let(:logs) { [] }
  let(:logger) do
    collected = logs
    lambda do |prefix|
      if prefix == Puppeteer::DebugPrefixes::ERROR
        lambda { |error| collected << error }
      end
    end
  end
  let(:transport) do
    double('transport').tap do |transport|
      allow(transport).to receive(:on_message)
      allow(transport).to receive(:on_close)
    end
  end

  def callbacks_of(connection)
    connection.instance_variable_get(:@callbacks)
  end

  describe '#async_send_message with a failing transport' do
    before do
      allow(transport).to receive(:send_text).and_raise(StandardError.new('boom'))
    end

    it 'raises synchronously, logs once, and leaves no callback behind' do
      connection = described_class.new('', transport, 0, logger: logger)

      expect { connection.async_send_message('Target.getTargets', {}) }.to raise_error(StandardError, 'boom')
      expect(logs.map(&:message)).to eq(['boom'])
      expect(callbacks_of(connection)).to be_empty
    end

    it 'logs and cleans up every failed send' do
      connection = described_class.new('', transport, 0, logger: logger)

      3.times do
        expect { connection.async_send_message('Target.getTargets', {}) }.to raise_error(StandardError, 'boom')
      end
      expect(logs.map(&:message)).to eq(['boom', 'boom', 'boom'])
      expect(callbacks_of(connection)).to be_empty
    end
  end
end
