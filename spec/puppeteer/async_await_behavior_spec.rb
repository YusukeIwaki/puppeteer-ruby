require 'spec_helper'

RSpec.describe Puppeteer::AsyncAwaitBehavior do
  describe 'async' do
    class Hoge
      using Puppeteer::AsyncAwaitBehavior

      async def hoge
        "-> hoge"
      end

      async def self.hogehoge
        "=> hogehoge"
      end
    end

    it 'is wrapped with Concurrent::Promises::Future' do
      res = Hoge.new.hoge
      expect(res).to be_a(Concurrent::Promises::Future)
      expect(res.value!).to eq("-> hoge")

      res = Hoge.hogehoge
      expect(res).to be_a(Concurrent::Promises::Future)
      expect(res.value!).to eq("=> hogehoge")
    end
  end

  describe 'await' do
    class Fuga
      using Puppeteer::AsyncAwaitBehavior

      def fuga1
        await 123
      end

      def fuga2
        await fuga
      end

      async def fuga
        "hoge"
      end
    end

    it 'return as it is, on no future' do
      expect(Fuga.new.fuga1).to eq(123)
    end

    it 'wait until value is set, on future exists' do
      expect(Fuga.new.fuga2).to eq("hoge")
    end
  end
end
