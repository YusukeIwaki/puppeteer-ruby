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
end
