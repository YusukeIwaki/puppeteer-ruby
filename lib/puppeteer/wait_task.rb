class Puppeteer::WaitTask
  using Puppeteer::DefineAsyncMethod

  class TerminatedError < Puppeteer::Error; end

  class TimeoutError < ::Puppeteer::TimeoutError
    def initialize(timeout:)
      super("Waiting failed: #{timeout}ms exceeded")
    end
  end

  def initialize(dom_world:, predicate_body:, title:, polling:, timeout:, args: [], binding_function: nil, root: nil, signal: nil)
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
    @root = root
    @predicate_body = build_predicate_body(predicate_body)
    @args = args
    @binding_function = binding_function
    @signal = signal
    @run_count = 0
    @dom_world.task_manager.add(self)
    if binding_function
      @dom_world.send(:_bound_functions)[binding_function.name] = binding_function
    end
    @promise = Async::Promise.new
    @generic_error = Puppeteer::Error.new('Waiting failed')

    # Since page navigation requires us to re-install the pageScript, we should track
    # timeout on our end.
    if timeout && timeout > 0
      timeout_error = TimeoutError.new(timeout: timeout)
      @timeout_task = Async do |task|
        task.sleep(timeout / 1000.0)
        # Avoid stopping the timeout task from inside terminate/cleanup.
        @timeout_task = nil
        terminate(timeout_error) unless @timeout_cleared
      end
    end

    if @signal
      if @signal.respond_to?(:aborted?) && @signal.aborted?
        terminate(@signal.reason || Puppeteer::AbortError.new)
        return
      end
      @signal_listener_id = @signal.add_event_listener('abort') do |reason|
        terminate(reason || Puppeteer::AbortError.new)
      end
    end

    async_rerun
  end

  # @return [Puppeteer::JSHandle]
  def await_promise
    @promise.wait
  end

  def terminate(error)
    return if @terminated

    @terminated = true
    @promise.reject(error) unless @promise.resolved?
    cleanup
  end

  def rerun
    run_count = (@run_count += 1)
    context = nil
    success = nil
    error = nil

    return if @terminated || run_count != @run_count
    begin
      context = @dom_world.execution_context
      if @binding_function
        @dom_world.add_binding_to_context(context, @binding_function)
      end
      return if @terminated || run_count != @run_count

      success = context.evaluate_handle(
        WAIT_FOR_PREDICATE_PAGE_FUNCTION,
        @root,
        @predicate_body,
        @polling,
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
      bad_error = get_bad_error(error)
      if bad_error
        @generic_error.cause = bad_error
        @promise.reject(@generic_error)
        cleanup
      end
      return
    end

    @promise.resolve(success)
    cleanup
  end

  private def cleanup
    @timeout_cleared = true
    begin
      @timeout_task&.stop
    rescue StandardError
      # Ignore errors during timeout task cleanup.
    end
    @signal&.remove_event_listener(@signal_listener_id) if @signal_listener_id
    @dom_world.task_manager.delete(self)
  end

  private def build_predicate_body(predicate_body)
    stripped = predicate_body.to_s.strip
    is_function =
      stripped.start_with?('function') ||
      stripped.start_with?('async function') ||
      stripped.include?('=>')

    if is_function
      "return (#{predicate_body})(...args);"
    else
      "return (#{predicate_body});"
    end
  end

  private def get_bad_error(error)
    message = error.message.to_s
    if message.include?('Execution context is not available in detached frame')
      return Puppeteer::Error.new('Waiting failed: Frame detached')
    end
    return nil if message.include?('Execution context was destroyed')
    return nil if message.include?('Cannot find context with specified id')
    return nil if message.include?('DiscardedBrowsingContextError')
    return nil if message.include?('Inspected target navigated or closed')

    error
  end

  define_async_method :async_rerun

  WAIT_FOR_PREDICATE_PAGE_FUNCTION = <<~JAVASCRIPT
  async function _(root, predicateBody, polling, ...args) {
      const predicate = new Function('...args', predicateBody);
      const observedRoot = root || document;
      if (polling === 'mutation' && typeof MutationObserver === 'undefined') {
          polling = 'raf';
      }
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
              const success = await predicate(...args);
              if (success) {
                  observer.disconnect();
                  fulfill(success);
              }
          });
          observer.observe(observedRoot, {
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
              const success = await predicate(...args);
              if (success) fulfill(success);
              else setTimeout(onTimeout, pollInterval);
          }
      }
  }
  JAVASCRIPT
end
