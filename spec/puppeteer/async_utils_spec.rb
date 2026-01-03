require 'spec_helper'

RSpec.describe Puppeteer::AsyncUtils do
  describe '.await_promise_all' do
    it 'waits for all tasks and preserves order' do
      start = Time.now
      results = described_class.await_promise_all(
        -> { described_class.sleep_seconds(0.2); 1 },
        -> { described_class.sleep_seconds(0.1); 2 },
      )
      expect(Time.now - start).to be >= 0.2
      expect(results).to eq([1, 2])
    end
  end

  describe '.async_timeout' do
    it 'raises Async::TimeoutError when exceeded' do
      expect do
        described_class.async_timeout(50, -> { described_class.sleep_seconds(0.1) }).wait
      end.to raise_error(Async::TimeoutError)
    end
  end

  describe '.future_with_logging' do
    it 'logs errors and re-raises' do
      expect do
        expect do
          described_class.future_with_logging { undefined_variable_is_me }.call
        end.to raise_error(NameError)
      end.to output(include('NameError').and(include('undefined_variable_is_me'))).to_stderr
    end
  end
end
