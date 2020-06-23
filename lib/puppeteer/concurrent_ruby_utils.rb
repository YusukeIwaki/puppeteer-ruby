# utility methods for Concurrent::Promises.
module Puppeteer::ConcurrentRubyUtils
  def await_all(*args)
    if args.length == 1 && args[0].is_a?(Enumerable)
      Concurrent::Promises.zip(*(args[0])).value!
    else
      Concurrent::Promises.zip(*args).value!
    end
  end

  def await_any(*args)
    if args.length == 1 && args[0].is_a?(Enumerable)
      Concurrent::Promises.any(*(args[0])).value!
    else
      Concurrent::Promises.any(*args).value!
    end
  end

  # blocking get value of Future.
  def await(future_or_value)
    if future_or_value.is_a?(Concurrent::Promises::Future)
      future_or_value.value!
    else
      future_or_value
    end
  end

  def future(&block)
    Concurrent::Promises.future(&block)
  end

  def resolvable_future(&block)
    future = Concurrent::Promises.resolvable_future
    if block
      block.call(future)
    end
    future
  end
end

include Puppeteer::ConcurrentRubyUtils
