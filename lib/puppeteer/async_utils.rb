# frozen_string_literal: true

require "async"
require "async/barrier"
require "async/promise"

module Puppeteer
  # Async helpers for Promise-style coordination using socketry/async.
  module AsyncUtils
    extend self

    def await(task)
      if task.is_a?(Proc)
        task.call
      elsif task.is_a?(Async::Promise)
        current_task = Async::Task.current?
        if current_task
          until task.resolved?
            current_task.sleep(0.001)
          end
        end
        task.wait
      elsif task.respond_to?(:wait)
        task.wait
      else
        task
      end
    end

    # Execute a task with a timeout using Async::Task#with_timeout.
    # @param timeout_ms [Numeric] Timeout duration in milliseconds (0 means no timeout)
    # @param task [Proc, Async::Promise, nil] Task to execute; falls back to block
    # @yield [async_task] Execute a task within the timeout, optionally receiving Async::Task
    # @return [Async::Task] Async task that resolves/rejects once the operation completes
    def async_timeout(timeout_ms, task = nil, &block)
      if task
        runner = lambda do |async_task|
          if timeout_ms == 0
            if task.is_a?(Proc)
              args = task.arity.positive? ? [async_task] : []
              task.call(*args)
            else
              await(task)
            end
          else
            timeout_seconds = timeout_ms / 1000.0
            async_task.with_timeout(timeout_seconds) do
              if task.is_a?(Proc)
                args = task.arity.positive? ? [async_task] : []
                task.call(*args)
              else
                await(task)
              end
            end
          end
        end
      elsif block
        runner = lambda do |async_task|
          if timeout_ms == 0
            args = block.arity.positive? ? [async_task] : []
            await(block.call(*args))
          else
            timeout_seconds = timeout_ms / 1000.0
            async_task.with_timeout(timeout_seconds) do
              args = block.arity.positive? ? [async_task] : []
              await(block.call(*args))
            end
          end
        end
      else
        raise ArgumentError.new("AsyncUtils.async_timeout requires a task or block")
      end

      current_task = Async::Task.current?
      if current_task
        return current_task.async do |async_task|
          runner.call(async_task)
        end
      end

      result = nil
      error = nil
      Async do |async_task|
        result = runner.call(async_task)
      rescue => err
        error = err
      end.wait

      ImmediateTask.new(result, error)
    end

    # Wait for all async tasks to complete and return results.
    def await_promise_all(*tasks)
      Sync { zip(*tasks) }
    end

    # Race multiple async tasks and return the result of the first one to complete.
    def await_promise_race(*tasks)
      Sync { first(*tasks) }
    end

    def future_with_logging(&block)
      proc do |*block_args|
        block.call(*block_args)
      rescue ::Puppeteer::TimeoutError
        raise
      rescue => err
        warn("#{err.message} (#{err.class})")
        raise err
      end
    end

    def sleep_seconds(duration)
      task = Async::Task.current
      if task
        task.sleep(duration)
      else
        Kernel.sleep(duration)
      end
    rescue RuntimeError, NoMethodError
      Kernel.sleep(duration)
    end

    class ImmediateTask
      def initialize(result, error)
        @result = result
        @error = error
      end

      def wait
        raise @error if @error

        @result
      end
    end

    private def zip(*tasks)
      barrier = Async::Barrier.new
      results = Array.new(tasks.size)

      begin
        tasks.each_with_index do |task, index|
          barrier.async do
            results[index] = await(task)
          end
        end

        barrier.wait
        results
      rescue Exception
        drain_barrier_tasks(barrier)
        raise
      end
    end

    private def first(*tasks)
      barrier = Async::Barrier.new
      result = nil

      begin
        tasks.each do |task|
          barrier.async(finished: false) do
            await(task)
          end
        end

        barrier.wait do |completed_task|
          result = completed_task.wait
          break
        end

        result
      ensure
        drain_barrier_tasks(barrier)
      end
    end

    private def drain_barrier_tasks(barrier)
      pending = barrier.tasks.to_a
      return if pending.empty?

      barrier.stop
      pending.each do |waiting|
        task = waiting.task
        next unless task.completed? || task.failed? || task.stopped?

        begin
          task.wait
        rescue StandardError
          # The race winner is already decided; ignore losers' errors.
        end
      end
    end
  end
end

module AsyncPromiseWaitRetry
  def wait(...)
    loop do
      begin
        return super
      rescue ThreadError => e
        raise unless e.message == 'Attempt to unlock a mutex which is not locked'
        next unless resolved?

        value = self.value
        raise value if value.is_a?(Exception)
        return value
      end
    end
  end
end

Async::Promise.prepend(AsyncPromiseWaitRetry)
