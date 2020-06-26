require 'spec_helper'

RSpec.describe Puppeteer::ConcurrentRubyUtils do
  describe 'await' do
    class Fuga
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
      expect(Fuga.new.fuga1).to eq(123)
    end

    it 'wait until value is set, on future exists' do
      expect(Fuga.new.fuga2).to eq('hoge')
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
end
