require 'spec_helper'

RSpec.describe Puppeteer::ConcurrentRubyUtils do
  describe '.await' do
    it 'returns value when given raw object' do
      expect(described_class.await(123)).to eq(123)
    end

    it 'waits for future completion' do
      future = Concurrent::Promises.future { 'hoge' }
      expect(described_class.await(future)).to eq('hoge')
    end
  end

  describe '.await_all' do
    it 'waits for all futures' do
      start = Time.now
      described_class.await_all(
        Concurrent::Promises.future { sleep 0.5 },
        Concurrent::Promises.future { sleep 1.2 },
        Concurrent::Promises.future { sleep 0.5 },
      )
      expect(Time.now - start).to be >= 1.2
    end

    it 'accepts an array of futures' do
      start = Time.now
      described_class.await_all([
        Concurrent::Promises.future { sleep 0.5 },
        Concurrent::Promises.future { sleep 1.2 },
        Concurrent::Promises.future { sleep 0.5 },
      ])
      expect(Time.now - start).to be >= 1.2
    end
  end

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

  describe '.await_any' do
    it 'resolves when the first future completes' do
      start = Time.now
      described_class.await_any(
        Concurrent::Promises.future { sleep 1.2 },
        Concurrent::Promises.future { sleep 0.1 },
      )
      expect(Time.now - start).to be < 1
    end

    it 'accepts an array of futures' do
      start = Time.now
      described_class.await_any([
        Concurrent::Promises.future { sleep 1.2 },
        Concurrent::Promises.future { sleep 0.1 },
      ])
      expect(Time.now - start).to be < 1
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
      expect { described_class.await(invalid_future) }.to raise_error(NameError)
    end
  end
end
