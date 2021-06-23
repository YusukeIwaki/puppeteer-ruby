require 'spec_helper'

RSpec.describe Puppeteer::ConcurrentRubyUtils do
  describe 'await' do
    class AwaitExample
      def fuga1
        await 123
      end

      def fuga2
        await fuga
      end

      def fuga
        future { 'hoge' }
      end
    end

    it 'return as it is, on no future' do
      expect(AwaitExample.new.fuga1).to eq(123)
    end

    it 'wait until value is set, on future exists' do
      expect(AwaitExample.new.fuga2).to eq('hoge')
    end
  end

  describe 'await_all' do
    it 'wait all futures' do
      start = Time.now
      await_all(
        future { sleep 0.5 },
        future { sleep 1.2 },
        future { sleep 0.5 },
      )
      expect(Time.now - start).to be >= 1.2
    end

    it 'accept array of futures' do
      start = Time.now
      await_all([
        future { sleep 0.5 },
        future { sleep 1.2 },
        future { sleep 0.5 },
      ])
      expect(Time.now - start).to be >= 1.2
    end
  end

  describe 'with_waiting_for_complete' do
    it 'wait for complete' do
      start = Time.now
      result = future { sleep 0.5 ; 3 }.with_waiting_for_complete do
        sleep 0.3
      end
      expect(Time.now - start).to be >= 0.5
      expect(result).to eq(3)
    end

    it 'wait for block call' do
      start = Time.now
      result = future { sleep 0.3 ; 3 }.with_waiting_for_complete do
        sleep 0.5
      end
      expect(Time.now - start).to be >= 0.5
      expect(result).to eq(3)
    end
  end

  describe 'await_any' do
    it 'wait first future' do
      start = Time.now
      await_any(
        future { sleep 1.2 },
        future { sleep 0.1 },
      )
      expect(Time.now - start).to be < 1
    end

    it 'accept array of futures' do
      start = Time.now
      await_any([
        future { sleep 1.2 },
        future { sleep 0.1 },
      ])
      expect(Time.now - start).to be < 1
    end
  end

  describe 'future' do
    let(:invalid_future) { future { undefined_variable_is_me } }

    it 'warns error' do
      expect { invalid_future ; sleep 1 }.to output(include("NameError").and(include("undefined_variable_is_me"))).to_stderr
      expect { await invalid_future }.to raise_error(NameError)
    end
  end
end
