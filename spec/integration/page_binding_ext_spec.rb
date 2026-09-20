require 'spec_helper'

# Ruby-specific adversarial coverage for exposed-function result delivery.
# Mirrors upstream Binding.run (packages/puppeteer-core/src/cdp/Binding.ts):
# callback execution and resolve-delivery failures both flow into a single
# reject-delivery attempt, and only a failure of that reject delivery is
# logged. These tests use real browser bindings, with failures injected at
# the JavaScript or CDP command boundary.
RSpec.describe 'Page exposed-function delivery (Ruby-specific)' do
  def launch_with_error_logger(errors, mutex, &block)
    logger = lambda do |prefix|
      if prefix == Puppeteer::DebugPrefixes::ERROR
        lambda { |error| mutex.synchronize { errors << error } }
      end
    end

    options = default_launch_options.merge(logger: logger)
    Puppeteer.launch(**options, &block)
  end

  def wait_until_settled(page, timeout: 15)
    Timeout.timeout(timeout) do
      sleep 0.05 while page.evaluate('() => globalThis.deliveryOutcome') == 'pending'
    end
  end

  it 'rejects the pending promise when resolve delivery throws in the page' do
    errors = []
    mutex = Mutex.new
    launch_with_error_logger(errors, mutex) do |browser|
      page = browser.new_page
      page.expose_function('callback', -> { 123 })
      page.evaluate(<<~JAVASCRIPT)
        () => {
          globalThis.deliveryOutcome = 'pending';
          const p = globalThis.callback();
          for (const entry of globalThis.callback.callbacks.values()) {
            entry.resolve = () => { throw new Error('resolve-delivery-probe'); };
          }
          p.then(
            (value) => { globalThis.deliveryOutcome = 'resolved:' + value; },
            (error) => {
              globalThis.deliveryOutcome = 'rejected:' + error.message;
              globalThis.deliveryStack = error.stack;
            },
          );
        }
      JAVASCRIPT
      wait_until_settled(page)
      expect(page.evaluate('() => globalThis.deliveryOutcome')).to eq('rejected:resolve-delivery-probe')
      expect(page.evaluate('() => globalThis.deliveryStack')).to include('resolve-delivery-probe')
      expect(page.evaluate('() => globalThis.callback.callbacks.size')).to eq(0)
      sleep 0.2
      expect(mutex.synchronize { errors.dup }).to be_empty
    end
  end

  it 'preserves primitive values thrown during resolve delivery' do
    errors = []
    mutex = Mutex.new
    launch_with_error_logger(errors, mutex) do |browser|
      page = browser.new_page
      page.expose_function('callback', -> { 123 })
      %w[undefined null nan infinity negativezero bigint string].each do |kind|
        page.evaluate(<<~JAVASCRIPT, kind)
          (kind) => {
            const values = {
              undefined: undefined,
              null: null,
              nan: NaN,
              infinity: Infinity,
              negativezero: -0,
              bigint: 123n,
              string: 'primitive-probe',
            };
            const value = values[kind];
            globalThis.deliveryOutcome = 'pending';
            const p = globalThis.callback();
            for (const entry of globalThis.callback.callbacks.values()) {
              entry.resolve = () => { throw value; };
            }
            p.then(
              () => { globalThis.deliveryOutcome = 'resolved'; },
              (e) => {
                globalThis.deliveryOutcome = Object.is(e, value)
                  ? 'same:' + kind
                  : 'MISMATCH:' + String(e) + ':' + typeof e;
              },
            );
          }
        JAVASCRIPT
        wait_until_settled(page)
        expect(page.evaluate('() => globalThis.deliveryOutcome')).to(
          eq("same:#{kind}"),
          "expected primitive #{kind} to round-trip identically (Object.is)",
        )
      end
      expect(page.evaluate('() => globalThis.callback.callbacks.size')).to eq(0)
      sleep 0.2
      expect(mutex.synchronize { errors.dup }).to be_empty
    end
  end

  it 'resolves with the callback result on success' do
    errors = []
    mutex = Mutex.new
    launch_with_error_logger(errors, mutex) do |browser|
      page = browser.new_page
      page.expose_function('compute', ->(a, b) { a * b })
      result = page.evaluate('async () => await globalThis.compute(9, 4)')
      expect(result).to eq(36)
      sleep 0.2
      expect(mutex.synchronize { errors.dup }).to be_empty
    end
  end

  it 'rejects with an Error when the Ruby callback raises' do
    errors = []
    mutex = Mutex.new
    launch_with_error_logger(errors, mutex) do |browser|
      page = browser.new_page
      page.expose_function('woof', -> { raise 'WOOF WOOF' })
      message = page.evaluate(<<~JAVASCRIPT)
        async () => {
          try {
            await globalThis.woof();
            return null;
          } catch (error) {
            return error.message;
          }
        }
      JAVASCRIPT
      expect(message).to eq('WOOF WOOF')
      sleep 0.2
      expect(mutex.synchronize { errors.dup }).to be_empty
    end
  end

  it 'logs exactly once when reject delivery also fails' do
    errors = []
    mutex = Mutex.new
    launch_with_error_logger(errors, mutex) do |browser|
      page = browser.new_page
      page.expose_function('callback_for_delivery_failure', ->(*_args) { 'ok' })
      page.evaluate('callback_for_delivery_failure(); callback_for_delivery_failure.callbacks.clear(); 42')
      Timeout.timeout(15) do
        sleep 0.05 while mutex.synchronize { errors.empty? }
      end
      sleep 0.3
      logged = mutex.synchronize { errors.dup }
      expect(logged.length).to eq(1)
      expect(logged.first.message).to include('Evaluation failed')
      expect(logged.first.message).to include("'reject'")
      expect(logged.first.message).not_to include('resolve')
    end
  end

  it 'rejects when the callback result cannot be serialized' do
    errors = []
    mutex = Mutex.new
    launch_with_error_logger(errors, mutex) do |browser|
      page = browser.new_page
      page.expose_function('bad', -> { "\xff".dup.force_encoding('UTF-8') })
      outcome = page.evaluate(<<~JAVASCRIPT)
        async () => {
          try {
            await globalThis.bad();
            return 'resolved';
          } catch (error) {
            return 'rejected:' + error.message;
          }
        }
      JAVASCRIPT
      expect(outcome).to start_with('rejected:')
      expect(outcome).to include('utf-8')
      sleep 0.2
      expect(mutex.synchronize { errors.dup }).to be_empty
    end
  end

  %i[synchronous asynchronous].each do |failure_mode|
    it "rejects and cleans up after #{failure_mode} result-delivery command failure" do
      errors = []
      mutex = Mutex.new
      Async do |task|
        launch_with_error_logger(errors, mutex) do |browser|
          page = browser.new_page
          page.expose_function('callback', -> { 123 })
          client = page.main_frame.client
          original_send = client.method(:async_send_message)
          injected = false
          # Fail only the CDP delivery boundary; keep the browser, binding
          # callback, rejection delivery and page-side Promise real.
          client.define_singleton_method(:async_send_message) do |method, params = {}|
            if !injected && method == 'Runtime.evaluate' && params[:expression].to_s.include?('callbacks.get(seq).resolve(result)')
              injected = true
              error = Puppeteer::Connection::ProtocolError.new(method: method, error_message: 'delivery-command-probe')
              raise error if failure_mode == :synchronous

              promise = Async::Promise.new
              promise.reject(error)
              promise
            else
              original_send.call(method, params)
            end
          end
          page.evaluate(<<~JAVASCRIPT)
            () => {
              globalThis.deliveryOutcome = 'pending';
              callback().then(
                () => { globalThis.deliveryOutcome = 'resolved'; },
                error => { globalThis.deliveryOutcome = 'rejected:' + error.message; },
              );
            }
          JAVASCRIPT
          task.with_timeout(5) do
            task.sleep(0.01) while page.evaluate('() => globalThis.deliveryOutcome') == 'pending'
          end
          expect(injected).to eq(true)
          expect(page.evaluate('() => globalThis.deliveryOutcome')).to eq('rejected:Protocol error (Runtime.evaluate): delivery-command-probe')
          expect(page.evaluate('() => callback.callbacks.size')).to eq(0)
          expect(mutex.synchronize { errors.dup }).to be_empty
        ensure
          client&.define_singleton_method(:async_send_message, original_send) if original_send
        end
      end.wait
    end
  end
end
