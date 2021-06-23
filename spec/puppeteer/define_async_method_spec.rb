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

      def wait_for_example(sleep_sec, arg1, &block)
        sleep sleep_sec
        "--> #{arg1}#{block&.call}"
      end
      define_async_method :async_wait_for_example

      def not_wait_for_example(arg1, &block)
        "--> #{arg1} #{block&.call}"
      end
      define_async_method :async_not_wait_for_example

      private def wait_for_example2(arg1, &block)
        "--> #{arg1} #{block&.call}"
      end
      define_async_method :async_wait_for_example2

      def args_example(arg1, arg2 = nil)
        "-> #{arg1},#{arg2}"
      end
      define_async_method :async_args_example

      def keyword_args_example(arg1:, arg2: nil)
        "-> #{arg1},#{arg2}"
      end
      define_async_method :async_keyword_args_example
    end

    it 'defined async method wrapped with Concurrent::Promises::Future' do
      instance = DefineAsyncMethodExample.new
      expect(instance.async_fuga).to be_a(Concurrent::Promises::Future)
      expect(instance.async_fuga.value!).to eq('-> fuga')
    end

    it 'preserves the modifier of original method' do
      expect(DefineAsyncMethodExample.private_method_defined?(:fuga)).to eq(true)
      expect(DefineAsyncMethodExample.method_defined?(:fuga)).to eq(false)

      expect(DefineAsyncMethodExample.method_defined?(:piyo)).to eq(true)
    end

    it 'modifies wait_for_ method' do
      instance = DefineAsyncMethodExample.new
      time_start = Time.now
      result = instance.wait_for_example(0.5, "xx") do
        sleep 0.3
        'xxx'
      end
      expect(Time.now - time_start).to be >= 0.5
      expect(result).to eq('--> xx')

      time_start = Time.now
      result = instance.wait_for_example(0.3, "yy") do
        sleep 0.5
        'yyy'
      end
      expect(Time.now - time_start).to be >= 0.5
      expect(result).to eq('--> yy')
    end

    it 'doesnt modify method without prefix "wait_for_"' do
      instance = DefineAsyncMethodExample.new

      result = instance.not_wait_for_example("xx") do
        'yy'
      end
      expect(result).to eq('--> xx yy')
    end

    it 'doesnt modify private wait_for_ method' do
      instance = DefineAsyncMethodExample.new

      result = instance.send(:wait_for_example2, "xx") do
        'yy'
      end
      expect(result).to eq('--> xx yy')
    end

    it 'can be used with private' do
      expect(DefineAsyncMethodExample.private_method_defined?(:async_piyo)).to eq(true)
      expect(DefineAsyncMethodExample.method_defined?(:async_piyo)).to eq(false)
    end

    it 'works with arguments' do
      instance = DefineAsyncMethodExample.new
      expect(instance.async_args_example(:hoge)).to be_a(Concurrent::Promises::Future)
      expect(instance.async_args_example(:hoge).value!).to eq('-> hoge,')
      expect(instance.async_args_example(:hoge, :fuga).value!).to eq('-> hoge,fuga')
    end

    it 'works with keyword arguments' do
      instance = DefineAsyncMethodExample.new
      expect(instance.async_keyword_args_example(arg1: :hoge)).to be_a(Concurrent::Promises::Future)
      expect(instance.async_keyword_args_example(arg1: :hoge).value!).to eq('-> hoge,')
      expect(instance.async_keyword_args_example(arg1: :hoge, arg2: :fuga).value!).to eq('-> hoge,fuga')
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
