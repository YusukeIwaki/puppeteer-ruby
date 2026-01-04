# frozen_string_literal: true

require "async"
require "async/promise"
require "delegate"
require "thread"

module Puppeteer
  # Runs a dedicated Async reactor in a background thread and proxies calls into it.
  class ReactorRunner
    class Finalizer
      def initialize(queue, thread)
        @queue = queue
        @thread = thread
      end

      def call(_id)
        @queue.close
        @thread.join unless ::Thread.current == @thread
      end
    end

    class Proxy < SimpleDelegator
      # @param runner [ReactorRunner]
      # @param target [Object]
      # @param owns_runner [Boolean]
      def initialize(runner, target, owns_runner: false)
        super(target)
        @runner = runner
        @owns_runner = owns_runner
      end

      def method_missing(name, *args, **kwargs, &block)
        if @owns_runner && @runner.closed? && close_like?(name)
          return nil
        end

        begin
          @runner.sync do
            args = args.map { |arg| @runner.unwrap(arg) }
            kwargs = kwargs.transform_values { |value| @runner.unwrap(value) }
            result = __getobj__.public_send(name, *args, **kwargs, &block)
            @runner.wrap(result)
          end
        ensure
          @runner.close if @owns_runner && close_like?(name)
        end
      end

      def respond_to_missing?(name, include_private = false)
        __getobj__.respond_to?(name, include_private) || super
      end

      def class
        __getobj__.class
      end

      def is_a?(klass)
        __getobj__.is_a?(klass)
      end

      alias kind_of? is_a?

      def instance_of?(klass)
        __getobj__.instance_of?(klass)
      end

      def ==(other)
        __getobj__ == @runner.unwrap(other)
      end

      def eql?(other)
        __getobj__.eql?(@runner.unwrap(other))
      end

      def hash
        __getobj__.hash
      end

      private def close_like?(name)
        name == :close || name == :disconnect
      end
    end

    def initialize
      @queue = Thread::Queue.new
      @ready = Queue.new
      @closed = false
      @thread = Thread.new do
        Sync do |task|
          barrier = Async::Barrier.new(parent: task)
          @barrier = barrier
          @ready << true
          begin
            while (job = @queue.pop)
              barrier.async do
                job.call
              end
            end
          rescue ClosedQueueError
            # Queue closed; exit the reactor loop.
          ensure
            barrier.stop
          end
        end
      ensure
        @barrier = nil
        @closed = true
      end

      ObjectSpace.define_finalizer(self, Finalizer.new(@queue, @thread))
      @ready.pop
    end

    def sync(&block)
      return block.call if runner_thread?
      raise Puppeteer::Error.new("ReactorRunner is closed") if closed?

      promise = Async::Promise.new
      job = lambda do
        Async::Promise.fulfill(promise, &block)
      end

      begin
        @queue << job
      rescue ClosedQueueError
        raise Puppeteer::Error.new("ReactorRunner is closed")
      end

      promise.wait
    end

    def close
      return if closed?

      @closed = true
      @queue.close
      @thread.join unless runner_thread?
    end

    def closed?
      @closed
    end

    def wrap(value)
      return value if value.nil? || value.is_a?(Proxy)

      if value.is_a?(Array)
        return value.map { |item| wrap(item) }
      end

      return Proxy.new(self, value) if proxyable?(value)

      value
    end

    def unwrap(value)
      case value
      when Proxy
        value.__getobj__
      when Array
        value.map { |item| unwrap(item) }
      when Hash
        value.transform_values { |item| unwrap(item) }
      else
        value
      end
    end

    private def runner_thread?
      Thread.current == @thread
    end

    private def proxyable?(value)
      return false if value.is_a?(Module) || value.is_a?(Class)

      name = value.class.name
      return false unless name&.start_with?("Puppeteer")
      return false if name.start_with?("Puppeteer::Bidi")
      return false if value.is_a?(ReactorRunner) || value.is_a?(Proxy)

      true
    end
  end
end
