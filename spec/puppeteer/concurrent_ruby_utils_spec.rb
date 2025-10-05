require 'spec_helper'

RSpec.describe Puppeteer::ConcurrentRubyUtils do
  describe '.with_waiting_for_complete' do
    it 'waits for both future and block to complete' do
      start = Time.now
      result = described_class.with_waiting_for_complete(
        Concurrent::Promises.future { sleep 0.5 ; 3 }
      ) do
        sleep 0.3
      end
      expect(Time.now - start).to be >= 0.5
      expect(result).to eq(3)
    end

    it 'waits for the longer of future or block' do
      start = Time.now
      result = described_class.with_waiting_for_complete(
        Concurrent::Promises.future { sleep 0.3 ; 3 }
      ) do
        sleep 0.5
      end
      expect(Time.now - start).to be >= 0.5
      expect(result).to eq(3)
    end
  end

  describe '.future_with_logging' do
    let(:invalid_future) do
      Concurrent::Promises.future(
        &described_class.future_with_logging { undefined_variable_is_me }
      )
    end

    it 'logs errors and rejects the future' do
      expect { invalid_future ; sleep 0.2 }.to output(include('NameError').and(include('undefined_variable_is_me'))).to_stderr
      expect { invalid_future.value! }.to raise_error(NameError)
  end
end
end
