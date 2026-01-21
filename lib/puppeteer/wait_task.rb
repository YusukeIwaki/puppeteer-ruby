class Puppeteer::WaitTask
  using Puppeteer::DefineAsyncMethod

  class TerminatedError < Puppeteer::Error; end

  class TimeoutError < ::Puppeteer::TimeoutError
    def initialize(timeout:)
      super("Waiting failed: #{timeout}ms exceeded")
    end
  end

  def initialize(dom_world:, predicate_body:, title:, polling:, timeout:, args: [], binding_function: nil, root: nil)
    if polling.is_a?(String)
      if polling != 'raf' && polling != 'mutation'
        raise ArgumentError.new("Unknown polling option: #{polling}")
      end
    elsif polling.is_a?(Numeric)
      if polling < 0
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
    @run_count = 0
    @dom_world.task_manager.add(self)
    if binding_function
      @dom_world.send(:_bound_functions)[binding_function.name] = binding_function
    end
    @promise = Async::Promise.new
    @poller_handle = nil
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

    async_rerun
  end

  # @return [Puppeteer::JSHandle]
  def await_promise
    @promise.wait
  end

  def terminate(error = nil)
    return if @terminated

    @terminated = true
    if error && !@promise.resolved?
      @promise.reject(error)
    end
    cleanup
  end

  def rerun
    run_count = (@run_count += 1)
    context = nil
    success = nil
    error = nil

    return if @terminated || run_count != @run_count
    reset_poller
    begin
      context = @dom_world.execution_context
      if @binding_function
        @dom_world.add_binding_to_context(context, @binding_function)
      end
      return if @terminated || run_count != @run_count

      @poller_handle = context.evaluate_handle(
        WAIT_FOR_PREDICATE_PAGE_FUNCTION,
        @root,
        @predicate_body,
        @polling,
        *@args,
      )
      success = @poller_handle.evaluate_handle('poller => poller.result()')
    rescue => err
      error = err
    end

    return if @terminated || run_count != @run_count

    if error
      bad_error = get_bad_error(error)
      if bad_error
        @generic_error.cause = bad_error
        terminate(@generic_error)
      else
        reset_poller
      end
      return
    end

    @promise.resolve(success) unless @promise.resolved?
    cleanup
  end

  private def cleanup
    @timeout_cleared = true
    begin
      @timeout_task&.stop
    rescue StandardError
      # Ignore errors during timeout task cleanup.
    end
    reset_poller
    @dom_world.task_manager.delete(self)
  end

  private def reset_poller
    poller = @poller_handle
    @poller_handle = nil
    return unless poller

    return if @dom_world.respond_to?(:detached?) && @dom_world.detached?

    begin
      poller.evaluate('poller => poller.stop()')
    rescue StandardError
      # Ignore errors during poller cleanup.
    end
    begin
      poller.dispose
    rescue StandardError
      # Ignore errors during poller cleanup.
    end
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
  function _(root, predicateBody, polling, ...args) {
      const predicate = new Function('...args', predicateBody);
      const observedRoot = root || document;
      if (polling === 'mutation' && typeof MutationObserver === 'undefined') {
          polling = 'raf';
      }

      function createDeferred() {
          let resolve;
          let reject;
          let finished = false;
          const promise = new Promise((res, rej) => {
              resolve = res;
              reject = rej;
          });
          return {
              promise,
              resolve: (value) => {
                  if (finished) return;
                  finished = true;
                  resolve(value);
              },
              reject: (error) => {
                  if (finished) return;
                  finished = true;
                  reject(error);
              },
              finished: () => finished,
          };
      }

      class MutationPoller {
          constructor(fn, root) {
              this.fn = fn;
              this.root = root;
              this.observer = null;
              this.deferred = null;
          }
          async start() {
              this.deferred = createDeferred();
              const result = await this.fn();
              if (result) {
                  this.deferred.resolve(result);
                  return;
              }
              this.observer = new MutationObserver(async () => {
                  const result = await this.fn();
                  if (!result) {
                      return;
                  }
                  this.deferred.resolve(result);
                  await this.stop();
              });
              this.observer.observe(this.root, {
                  childList: true,
                  subtree: true,
                  attributes: true,
              });
          }
          async stop() {
              if (!this.deferred) {
                  return;
              }
              if (!this.deferred.finished()) {
                  this.deferred.reject(new Error('Polling stopped'));
              }
              if (this.observer) {
                  this.observer.disconnect();
                  this.observer = null;
              }
          }
          result() {
              if (!this.deferred) {
                  return Promise.reject(new Error('Polling never started'));
              }
              return this.deferred.promise;
          }
      }

      class RAFPoller {
          constructor(fn) {
              this.fn = fn;
              this.deferred = null;
              this.rafId = null;
          }
          async start() {
              this.deferred = createDeferred();
              const result = await this.fn();
              if (result) {
                  this.deferred.resolve(result);
                  return;
              }
              const poll = async () => {
                  if (!this.deferred || this.deferred.finished()) {
                      return;
                  }
                  const result = await this.fn();
                  if (result) {
                      this.deferred.resolve(result);
                      await this.stop();
                  } else {
                      this.rafId = requestAnimationFrame(poll);
                  }
              };
              this.rafId = requestAnimationFrame(poll);
          }
          async stop() {
              if (!this.deferred) {
                  return;
              }
              if (!this.deferred.finished()) {
                  this.deferred.reject(new Error('Polling stopped'));
              }
              if (this.rafId) {
                  cancelAnimationFrame(this.rafId);
                  this.rafId = null;
              }
          }
          result() {
              if (!this.deferred) {
                  return Promise.reject(new Error('Polling never started'));
              }
              return this.deferred.promise;
          }
      }

      class IntervalPoller {
          constructor(fn, ms) {
              this.fn = fn;
              this.ms = ms;
              this.interval = null;
              this.deferred = null;
          }
          async start() {
              this.deferred = createDeferred();
              const result = await this.fn();
              if (result) {
                  this.deferred.resolve(result);
                  return;
              }
              this.interval = setInterval(async () => {
                  const result = await this.fn();
                  if (!result) {
                      return;
                  }
                  this.deferred.resolve(result);
                  await this.stop();
              }, this.ms);
          }
          async stop() {
              if (!this.deferred) {
                  return;
              }
              if (!this.deferred.finished()) {
                  this.deferred.reject(new Error('Polling stopped'));
              }
              if (this.interval) {
                  clearInterval(this.interval);
                  this.interval = null;
              }
          }
          result() {
              if (!this.deferred) {
                  return Promise.reject(new Error('Polling never started'));
              }
              return this.deferred.promise;
          }
      }

      const runner = () => predicate(...args);
      let poller;
      if (polling === 'raf') {
          poller = new RAFPoller(runner);
      } else if (polling === 'mutation') {
          poller = new MutationPoller(runner, observedRoot);
      } else if (typeof polling === 'number') {
          poller = new IntervalPoller(runner, polling);
      } else {
          throw new Error('Unknown polling option: ' + polling);
      }
      poller.start();
      return poller;
  }
  JAVASCRIPT
end
