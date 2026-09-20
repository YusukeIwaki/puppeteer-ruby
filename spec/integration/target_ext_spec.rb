require 'spec_helper'

RSpec.describe 'Target (Ruby-specific shared worker ordering)' do
  it 'should create a shared worker even when session readiness is delayed' do
    Async do |task|
      Puppeteer.launch(**default_launch_options) do |browser|
        with_test_state(browser: browser) do |page:, server:, context:, **|
          # Hold Runtime.runIfWaitingForDebugger for shared worker sessions until
          # the readiness boundary is entered, so a slow runner cannot let
          # Inspector.workerScriptLoaded fire before Target#worker constructs
          # its listener. Real browser, real events; only the resume timing is
          # held. The delay itself stays strictly inside wait_for_ready.
          resume_gate = Async::Promise.new
          cdp_session_class = Puppeteer::CDPSession
          original_async_send = cdp_session_class.instance_method(:async_send_message)
          cdp_session_class.define_method(:async_send_message) do |cdp_method, cdp_params = {}|
            if cdp_method == 'Runtime.runIfWaitingForDebugger' &&
               (worker_target = target) && worker_target.type == 'shared_worker'

              resume_gate.wait
            end
            original_async_send.bind_call(self, cdp_method, cdp_params)
          end

          begin
            page.goto(server.empty_page)
            page.evaluate(%q{() => { new SharedWorker('data:text/javascript,console.log("hi")'); }})

            shared_worker_target = context.wait_for_target(
              predicate: ->(candidate) { candidate.type == 'shared_worker' },
              timeout: 5000,
            )

            raw_session = shared_worker_target.session
            raise 'shared worker target has no session' if raw_session.nil?
            original_wait = raw_session.method(:wait_for_ready)
            readiness_delay = 0.5
            raw_session.define_singleton_method(:wait_for_ready) do
              resume_gate.resolve(true) unless resume_gate.resolved?
              Puppeteer::AsyncUtils.sleep_seconds(readiness_delay)
              original_wait.call
            end

            begin
              worker = task.with_timeout(5) { shared_worker_target.worker }
              result = task.with_timeout(5) do
                worker.evaluate('() => self.toString()')
              end
              expect(result).to eq('[object SharedWorkerGlobalScope]')
            ensure
              begin
                raw_session.singleton_class.send(:remove_method, :wait_for_ready)
              rescue NameError
                # Already removed; ignore.
              end
            end
          ensure
            begin
              cdp_session_class.define_method(:async_send_message, original_async_send)
            ensure
              resume_gate.resolve(true) unless resume_gate.resolved?
            end
          end
        end
      end
    end.wait
  end

  it 'keeps a second worker caller valid when the first caller times out' do
    Async do |task|
      Puppeteer.launch(**default_launch_options) do |browser|
        with_test_state(browser: browser) do |page:, server:, context:, **|
          page.goto(server.empty_page)
          page.evaluate(%q{() => { globalThis.worker = new SharedWorker('data:text/javascript,console.log("probe")'); }})
          target = context.wait_for_target(predicate: ->(candidate) { candidate.type == 'shared_worker' }, timeout: 3000)
          client = target.session
          entered = Async::Promise.new
          release = Async::Promise.new
          original = client.method(:wait_for_ready)
          client.define_singleton_method(:wait_for_ready) do
            entered.resolve(true) unless entered.resolved?
            release.wait
            original.call
          end
          begin
            first = task.async do |first_task|
              first_task.with_timeout(0.1) { target.worker }
            rescue Async::TimeoutError
              :timed_out
            end
            task.with_timeout(5) { entered.wait }
            second = task.async { |second_task| second_task.with_timeout(5) { target.worker } }
            task.sleep(0.2)
            expect(first.wait).to eq(:timed_out)
            expect(second.finished?).to eq(false)
            release.resolve(true)
            result = second.wait
            expect(result).to be_a(Puppeteer::CdpWebWorker)
            # Cached callers share the same constructed worker.
            expect(target.worker).to equal(result)
          ensure
            release.resolve(true) unless release.resolved?
            client.define_singleton_method(:wait_for_ready, original)
            first&.wait
            second&.wait
          end
        end
      end
    end.wait
  end
end
