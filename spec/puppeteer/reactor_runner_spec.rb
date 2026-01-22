require 'spec_helper'
require 'timeout'

RSpec.describe Puppeteer::ReactorRunner do
  describe '#sync' do
    it 'propagates Async::Stop without hanging' do
      runner = described_class.new
      begin
        expect do
          Timeout.timeout(1.0) do
            runner.sync { raise Async::Stop.new('stopped') }
          end
        end.to raise_error(Async::Stop, 'stopped')
      ensure
        runner.close
      end
    end
  end
end
