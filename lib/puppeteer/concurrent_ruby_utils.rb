# Utility helpers around Concurrent::Promises without polluting the global namespace.
module Puppeteer::ConcurrentRubyUtils
  module_function

  def future_with_logging(&block)
    proc do |*block_args|
      block.call(*block_args)
    rescue Puppeteer::TimeoutError
      # Suppress timeout noise but keep semantics.
      raise
    rescue => err
      Logger.new($stderr).warn(err)
      raise err
    end
  end

  def await_all(*args)
    futures = normalize_futures(args)
    Concurrent::Promises.zip(*futures).value!
  end

  def await_any(*args)
    futures = normalize_futures(args)
    Concurrent::Promises.any(*futures).value!
  end

  def await(future_or_value)
    future_or_value.is_a?(Concurrent::Promises::Future) ? future_or_value.value! : future_or_value
  end

  def with_waiting_for_complete(future, &block)
    async_block_call = Concurrent::Promises.delay do
      block.call
    rescue => err
      Logger.new($stderr).warn(err)
      raise err
    end

    Concurrent::Promises.zip(future, async_block_call).value!.first
  end

  def normalize_futures(args)
    futures = if args.length == 1 && args.first.is_a?(Enumerable)
                args.first.to_a
              else
                args
              end

    unless futures.all? { |future| future.is_a?(Concurrent::Promises::Future) }
      raise ArgumentError, "All argument must be a Future: #{futures}"
    end

    futures
  end
  private_class_method :normalize_futures
end
