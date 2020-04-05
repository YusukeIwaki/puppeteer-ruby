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

      async def tap
        "my tap!"
      end
    end

    it 'is wrapped with Concurrent::Promises::Future' do
      res = Hoge.new.hoge
      expect(res).to be_a(Concurrent::Promises::Future)
      expect(res.value!).to eq("-> hoge")

      res = Hoge.hogehoge
      expect(res).to be_a(Concurrent::Promises::Future)
      expect(res.value!).to eq("=> hogehoge")

      res = Hoge.new.tap
      expect(res).to be_a(Concurrent::Promises::Future)
      expect(res.value!).to eq("my tap!")
    end
  end
end
