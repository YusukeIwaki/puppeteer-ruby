class Puppeteer::WaitTask
  using Puppeteer::DefineAsyncMethod

  class TerminatedError < StandardError; end

  class TimeoutError < ::Puppeteer::TimeoutError
    def initialize(title:, timeout:)
      super("waiting for #{title} failed: timeout #{timeout}ms exceeded")
    end
  end

  def initialize(dom_world:, predicate_body:, title:, polling:, timeout:, args: [], binding_function: nil)
    if polling.is_a?(String)
      if polling != 'raf' && polling != 'mutation'
        raise ArgumentError.new("Unknown polling option: #{polling}")
      end
    elsif polling.is_a?(Numeric)
      unless polling.positive?
        raise ArgumentError.new("Cannot poll with non-positive interval: #{polling}")
      end
    else
      raise ArgumentError.new("Unknown polling options: #{polling}")
    end

    @dom_world = dom_world
    @polling = polling
    @timeout = timeout
    @predicate_body = "return (#{predicate_body})(...args);"
    @args = args
    @binding_function = binding_function
    @run_count = 0
    @dom_world.send(:_wait_tasks).add(self)
    if binding_function
      @dom_world.send(:_bound_functions)[binding_function.name] = binding_function
    end
    @promise = resolvable_future

    # Since page navigation requires us to re-install the pageScript, we should track
    # timeout on our end.
    if timeout && timeout > 0
      timeout_error = TimeoutError.new(title: title, timeout: timeout)
      Concurrent::Promises.schedule(timeout / 1000.0) { terminate(timeout_error) unless @timeout_cleared }
    end
    async_rerun
  end

  # @return [Puppeteer::JSHandle]
  def await_promise
    @promise.value!
  end

  def terminate(error)
    @terminated = true
    @promise.reject(error)
    cleanup
  end

  def rerun
    run_count = (@run_count += 1)
    context = @dom_world.execution_context

    return if @terminated || run_count != @run_count
    if @binding_function
      @dom_world.add_binding_to_context(context, @binding_function)
    end
    return if @terminated || run_count != @run_count

    begin
      success = context.evaluate_handle(
        WAIT_FOR_PREDICATE_PAGE_FUNCTION,
        @predicate_body,
        @polling,
        @timeout,
        *@args,
      )
    rescue => err
      error = err
    end

    if @terminated || run_count != @run_count
      if success
        success.dispose
      end
      return
    end

    # Ignore timeouts in pageScript - we track timeouts ourselves.
    # If the frame's execution context has already changed, `frame.evaluate` will
    # throw an error - ignore this predicate run altogether.
    if !error && (@dom_world.evaluate("s => !s", success) rescue true)
      success.dispose
      return
    end

    # When the page is navigated, the promise is rejected.
    # We will try again in the new execution context.
    if error && error.message.include?('Execution context was destroyed')
      return
    end

    # We could have tried to evaluate in a context which was already
    # destroyed.
    if error && error.message.include?('Cannot find context with specified id')
      return
    end

    if error
      @promise.reject(error)
    else
      @promise.fulfill(success)
    end

    cleanup
  end

  private def cleanup
    @timeout_cleared = true
    @dom_world.send(:_wait_tasks).delete(self)
  end

  private define_async_method :async_rerun

  WAIT_FOR_PREDICATE_PAGE_FUNCTION = <<~JAVASCRIPT
  async function _(predicateBody, polling, timeout, ...args) {
      const predicate = new Function('...args', predicateBody);
      let timedOut = false;
      if (timeout)
          setTimeout(() => (timedOut = true), timeout);
      if (polling === 'raf')
          return await pollRaf();
      if (polling === 'mutation')
          return await pollMutation();
      if (typeof polling === 'number')
          return await pollInterval(polling);
      /**
       * @return {!Promise<*>}
       */
      async function pollMutation() {
          const success = await predicate(...args);
          if (success) return Promise.resolve(success);
          let fulfill;
          const result = new Promise((x) => (fulfill = x));
          const observer = new MutationObserver(async () => {
              if (timedOut) {
                  observer.disconnect();
                  fulfill();
              }
              const success = await predicate(...args);
              if (success) {
                  observer.disconnect();
                  fulfill(success);
              }
          });
          observer.observe(document, {
              childList: true,
              subtree: true,
              attributes: true,
          });
          return result;
      }
      async function pollRaf() {
          let fulfill;
          const result = new Promise((x) => (fulfill = x));
          await onRaf();
          return result;
          async function onRaf() {
              if (timedOut) {
                  fulfill();
                  return;
              }
              const success = await predicate(...args);
              if (success) fulfill(success);
              else requestAnimationFrame(onRaf);
          }
      }
      async function pollInterval(pollInterval) {
          let fulfill;
          const result = new Promise((x) => (fulfill = x));
          await onTimeout();
          return result;
          async function onTimeout() {
              if (timedOut) {
                  fulfill();
                  return;
              }
              const success = await predicate(...args);
              if (success) fulfill(success);
              else setTimeout(onTimeout, pollInterval);
          }
      }
  }
  JAVASCRIPT
end
