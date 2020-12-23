require 'spec_helper'

RSpec.describe Puppeteer::CDPSession do
  let(:connection) { double(Puppeteer::Connection) }
  let(:cdp_session_id) { SecureRandom.hex(16) }
  let(:cdp_session) { Puppeteer::CDPSession.new(connection, 'page', cdp_session_id) }

  describe '#send_message' do
    before {
      allow(connection).to receive(:generate_id) { |&block| block.call(SecureRandom.hex(16)) }
      allow(connection).to receive(:raw_send) do |kwargs|
        id = kwargs[:id]
        message = kwargs[:message]

        Thread.new(id) do |message_id|
          resp = {
            'sessionId' => cdp_session_id,
            'id' => message_id,
            'result' => "pong",
          }
          cdp_session.handle_message(resp)
        end
      end
    }

    it 'should be thread safe' do
      Timeout.timeout(5) do
        await_all(1000.times.map { cdp_session.async_send_message('ping') })
      end
    end

    it 'should raise error for unknown id' do
      resp = {
        'sessionId' => cdp_session_id,
        'id' => -123,
        'result' => "pong",
      }
      expect { cdp_session.handle_message(resp) }.to raise_error(/unknown id: -123/)
    end
  end
end
