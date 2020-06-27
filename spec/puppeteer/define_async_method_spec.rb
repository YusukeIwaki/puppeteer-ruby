require 'spec_helper'

RSpec.describe Puppeteer::DefineAsyncMethod do
  describe 'define_async_method_for' do
    class DefineAsyncMethodExample
      using Puppeteer::DefineAsyncMethod

      private def fuga
        '-> fuga'
      end
      define_async_method :async_fuga

      def piyo
        '-> piyo'
      end
      private define_async_method :async_piyo
    end

    it 'defined async method wrapped with Concurrent::Promises::Future' do
      instance = DefineAsyncMethodExample.new
      expect(instance.async_fuga).to be_a(Concurrent::Promises::Future)
      expect(instance.async_fuga.value!).to eq('-> fuga')
    end

    it 'can be used with private' do
      expect(DefineAsyncMethodExample.private_method_defined?(:async_piyo)).to eq(true)
      expect(DefineAsyncMethodExample.method_defined?(:async_piyo)).to eq(false)
    end

    it 'raises exception when async method name does not start with async_' do
      expect {
        class DefineAsyncMethodExample1
          using Puppeteer::DefineAsyncMethod

          def ex
            'ex'
          end
          define_async_method :ex
        end
      }.to raise_error(ArgumentError)
    end

    it 'raises exception when async method is already defined' do
      expect {
        class DefineAsyncMethodExample2
          using Puppeteer::DefineAsyncMethod

          private def async_ex
            "async ex"
          end

          def ex
            "ex"
          end
          define_async_method :async_ex
        end
      }.to raise_error(ArgumentError)

      expect {
        class DefineAsyncMethodExample3
          using Puppeteer::DefineAsyncMethod

          def async_ex
            "async ex"
          end

          def ex
            "ex"
          end
          define_async_method :async_ex
        end
      }.to raise_error(ArgumentError)
    end
  end
end
