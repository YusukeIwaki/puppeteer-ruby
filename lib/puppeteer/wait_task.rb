class Puppeteer::WaitTask
  using Puppeteer::DefineAsyncMethod

  class TerminatedError < StandardError; end

  class TimeoutError < ::Puppeteer::TimeoutError
    def initialize(title:, timeout:)
      super("waiting for #{title} failed: timeout #{timeout}ms exceeded")
    end
  end

  # @param world [Puppeteer::IsolatedWorld]
  # @param binding_function [Proc]
  # @param polling ['raf'|'mutation'|Numeric]
  # @param root [Puppeteer::ElementHandle|nil]
  # @param timeout [Numeric]
  # @param fn [String]
  def initialize(world:, binding_function:, polling:, root:, timeout:, fn:, args: [])
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
    @result = resolvable_future

    @world = world
    @binding_function = binding_function
    @polling = polling
    @root = root
    @fn = "() => {return(#{fn});}"
    @args = args
    @world.task_manager.add(self)

    if timeout && timeout > 0
      timeout_error = TimeoutError.new(title: title, timeout: timeout)
      Concurrent::Promises.schedule(timeout / 1000.0) { terminate(timeout_error) unless @timeout_cleared }
    end

    @world.bound_functions.add(@binding_function)
    async_rerun
  end

  def await_result
    @result.value!
  end

  def terminate(error)
    @terminated = true
    @promise.reject(error)
    cleanup
  end

  def rerun
    context = @world.execution_context
    @world.add_binding_to_context(context, @binding_function)

    begin
      success = context.evaluate_handle(
        WAIT_FOR_PREDICATE_PAGE_FUNCTION,
        @root,
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
  async function _(root, predicateBody, polling, timeout, ...args) {
      const predicate = new Function('...args', predicateBody);
      root = root || document
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
          const success = await predicate(root, ...args);
          if (success) return Promise.resolve(success);
          let fulfill;
          const result = new Promise((x) => (fulfill = x));
          const observer = new MutationObserver(async () => {
              if (timedOut) {
                  observer.disconnect();
                  fulfill();
              }
              const success = await predicate(root, ...args);
              if (success) {
                  observer.disconnect();
                  fulfill(success);
              }
          });
          observer.observe(root, {
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
              const success = await predicate(root, ...args);
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
              const success = await predicate(root, ...args);
              if (success) fulfill(success);
              else setTimeout(onTimeout, pollInterval);
          }
      }
  }
  JAVASCRIPT
end
