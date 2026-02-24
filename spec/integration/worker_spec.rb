require 'spec_helper'

RSpec.describe 'Workers' do
  def wait_for_event(emitter, event_name)
    promise = Async::Promise.new
    emitter.once(event_name) do |*args|
      promise.resolve(args.length == 1 ? args.first : args)
    end
    promise
  end

  it 'Page.workers', sinatra: true do
    with_test_state do |page:, server:, **|
      await_promises(
        wait_for_event(page, 'workercreated'),
        async_promise { page.goto("#{server.prefix}/worker/worker.html") },
      )
      worker = page.workers.first
      expect(worker.url).to include('worker.js')

      result = nil
      5.times do
        begin
          result = worker.evaluate('() => globalThis.workerFunction()')
          break
        rescue
          Puppeteer::AsyncUtils.sleep_seconds(0.2)
        end
      end
      expect(result).to eq('worker function result')

      page.goto(server.empty_page)
      expect(page.workers.length).to eq(0)
    end
  end

  it 'should emit created and destroyed events' do
    with_test_state do |page:, **|
      worker_created = wait_for_event(page, 'workercreated')
      worker_obj = page.evaluate_handle('() => new Worker("data:text/javascript,1")')
      worker = worker_created.wait

      worker_this_obj = worker.evaluate_handle('() => this')
      worker_destroyed = await_promises(
        wait_for_event(page, 'workerdestroyed'),
        async_promise { page.evaluate('(worker) => worker.terminate()', worker_obj) },
      ).first

      expect(worker_destroyed).to eq(worker)

      error = nil
      begin
        worker_this_obj.property('self')
      rescue => err
        error = err
      ensure
        begin
          worker_this_obj.dispose
        rescue StandardError
          # Ignore errors caused by closed worker sessions.
        end
        begin
          worker_obj.dispose
        rescue StandardError
          # Ignore errors caused by closed worker sessions.
        end
      end

      expect(error).not_to be_nil
      expect(
        [
          'Realm already destroyed.',
          'Execution context is not available in detached frame',
          'Session closed. Most likely the worker has been closed.',
        ].any? { |message| error.message.include?(message) },
      ).to eq(true)
    end
  end

  it 'should report console logs' do
    with_test_state do |page:, **|
      message = await_promises(
        wait_for_event(page, 'console'),
        async_promise { page.evaluate('() => new Worker("data:text/javascript,console.log(1)")') },
      ).first

      expect(message.text).to eq('1')
      location = message.location
      expect(location.url).to eq('')
      expect(location.line_number).to eq(0)
      expect(location.column_number).to eq(8)
    end
  end

  it 'should work with console logs' do
    with_test_state do |page:, **|
      log_promise = wait_for_event(page, 'console')
      page.evaluate('() => new Worker("data:text/javascript,console.log(1,2,3,this)")')
      log = log_promise.wait

      expect([
        '1 2 3 [object DedicatedWorkerGlobalScope]',
        '1 2 3 [object WorkerGlobalScope]',
      ]).to include(log.text)
      expect(log.args.length).to eq(4)
    end
  end

  it 'should have an execution context' do
    with_test_state do |page:, **|
      worker_created = wait_for_event(page, 'workercreated')
      page.evaluate('() => new Worker("data:text/javascript,console.log(1)")')
      worker = worker_created.wait

      expect(worker.evaluate('1+1')).to eq(2)
    end
  end

  it 'should report errors' do
    with_test_state do |page:, **|
      error_promise = wait_for_event(page, 'pageerror')
      page.evaluate('() => new Worker("data:text/javascript, throw new Error(\\"this is my error\\");")')
      error_log = error_promise.wait

      expect(error_log.message).to include('this is my error')
    end
  end

  it 'can be closed', sinatra: true do
    with_test_state do |page:, server:, **|
      await_promises(
        wait_for_event(page, 'workercreated'),
        async_promise { page.goto("#{server.prefix}/worker/worker.html") },
      )
      worker = page.workers.first
      expect(worker.url).to include('worker.js')

      await_promises(
        wait_for_event(page, 'workerdestroyed'),
        async_promise { worker.close },
      )
    end
  end

  it 'should work with waitForNetworkIdle', sinatra: true do
    with_test_state do |page:, server:, **|
      await_promises(
        wait_for_event(page, 'workercreated'),
        async_promise { page.goto("#{server.prefix}/worker/worker.html", wait_until: 'networkidle0') },
      )

      page.wait_for_network_idle(timeout: 3000)
    end
  end

  it 'should retrieve body for main worker requests', sinatra: true do
    with_test_state do |page:, server:, **|
      test_response = nil
      worker_url = "#{server.prefix}/worker/worker.js"

      page.on('response') do |response|
        test_response = response if response.request.url == worker_url
      end

      await_promises(
        wait_for_event(page, 'workercreated'),
        async_promise { page.goto("#{server.prefix}/worker/worker.html", wait_until: 'networkidle0') },
      )

      expect(test_response).not_to be_nil
      expect(test_response.text).to include('hello from the worker')
    end
  end
end
