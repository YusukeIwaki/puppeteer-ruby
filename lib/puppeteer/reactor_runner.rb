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

      # Override tap to distinguish between Ruby's Object#tap and Puppeteer's tap method.
      # When called with a block only (Ruby's tap), delegate to super.
      # When called with args (Puppeteer's tap), route through the reactor.
      def tap(*args, **kwargs, &block)
        if args.empty? && kwargs.empty? && block
          super(&block)
        else
          @runner.sync do
            args = args.map { |arg| @runner.unwrap(arg) }
            kwargs = kwargs.transform_values { |value| @runner.unwrap(value) }
            result = __getobj__.public_send(:tap, *args, **kwargs, &block)
            @runner.wrap(result)
          end
        end
      end

      def method_missing(name, *args, **kwargs, &block)
        if @runner.closed?
          return false if name == :connected?
          return nil if @owns_runner && close_like?(name)
        end

        begin
          @runner.sync do
            args = args.map { |arg| @runner.unwrap(arg) }
            kwargs = kwargs.transform_values { |value| @runner.unwrap(value) }
            result = __getobj__.public_send(name, *args, **kwargs, &block)
            @runner.wrap(result)
          end
        ensure
          if @owns_runner && close_like?(name)
            @runner.wait_until_idle
            @runner.close
          end
        end
      end

      def respond_to_missing?(name, include_private = false)
        __getobj__.respond_to?(name, include_private) || super
      end

      def class
        __getobj__.class
      end

      def is_a?(klass)
        return true if klass == Proxy || klass == self.class

        __getobj__.is_a?(klass)
      end

      alias kind_of? is_a?

      def instance_of?(klass)
        return true if klass == Proxy || klass == self.class

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
      raise ::Puppeteer::Error.new("ReactorRunner is closed") if closed?

      promise = Async::Promise.new
      job = lambda do
        Async::Promise.fulfill(promise, &block)
      end

      begin
        @queue << job
      rescue ClosedQueueError
        raise ::Puppeteer::Error.new("ReactorRunner is closed")
      end

      promise.wait
    end

    def close
      return if closed?

      @closed = true
      @queue.close
      @thread.join unless runner_thread?
    end

    def wait_until_idle(timeout: 1.0)
      return if closed?

      sync do
        return unless @barrier

        deadline = timeout ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout : nil
        loop do
          break if @barrier.empty?
          break if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          Async::Task.current.sleep(0.01)
        end
      end
    rescue Puppeteer::Error
      # Runner closed while waiting; ignore.
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

    def unwrap(value, seen = nil)
      seen ||= {}

      case value
      when Proxy
        value.__getobj__
      when Array
        object_id = value.object_id
        return seen[object_id] if seen.key?(object_id)

        result = []
        seen[object_id] = result
        value.each { |item| result << unwrap(item, seen) }
        result
      when Hash
        object_id = value.object_id
        return seen[object_id] if seen.key?(object_id)

        result = {}
        seen[object_id] = result
        value.each do |key, item|
          result[unwrap(key, seen)] = unwrap(item, seen)
        end
        result
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
