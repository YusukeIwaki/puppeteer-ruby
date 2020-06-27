require 'spec_helper'

RSpec.describe Puppeteer::AsyncAwaitBehavior do
  describe 'define_async_method_for' do
    class Fuga
      using Puppeteer::AsyncAwaitBehavior

      private def fuga
        '-> fuga'
      end
      define_async_method_for :fuga

      def piyo
        '-> piyo'
      end
      private define_async_method_for :piyo
    end

    it 'defined async method wrapped with Concurrent::Promises::Future' do
      instance = Fuga.new
      expect(instance.async_fuga).to be_a(Concurrent::Promises::Future)
      expect(instance.async_fuga.value!).to eq('-> fuga')
    end

    it 'can be used with private' do
      expect(Fuga.private_method_defined?(:async_piyo)).to eq(true)
      expect(Fuga.method_defined?(:async_piyo)).to eq(false)
    end

    it 'raises exception when async method is already defined' do
      expect {
        class Ex
          using Puppeteer::AsyncAwaitBehavior

          private def async_ex
            "async ex"
          end

          def ex
            "ex"
          end
          define_async_method_for :ex
        end
      }.to raise_error(ArgumentError)

      expect {
        class Ex
          using Puppeteer::AsyncAwaitBehavior

          def async_ex
            "async ex"
          end

          def ex
            "ex"
          end
          define_async_method_for :ex
        end
      }.to raise_error(ArgumentError)
    end
  end
end
