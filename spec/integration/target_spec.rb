require 'spec_helper'

RSpec.describe 'Target' do
  include Utils::WaitEvent

  it 'Browser.targets should return all of the targets' do
    with_test_state do |browser:, **|
      targets = browser.targets
      expect(
        targets.any? do |target|
          target.type == 'page' && target.url == 'about:blank'
        end,
      ).to eq(true)
      expect(targets.any? { |target| target.type == 'browser' }).to eq(true)
    end
  end

  it 'Browser.pages should return all of the pages' do
    with_test_state do |page:, context:, **|
      all_pages = context.pages
      expect(all_pages.length).to eq(1)
      expect(all_pages).to include(page)
    end
  end

  it 'page should return tab target id' do
    with_test_state do |page:, **|
      expect(page._tab_id.length).to be > 0
    end
  end

  it 'should contain browser target' do
    with_test_state do |browser:, **|
      browser_target = browser.targets.find { |target| target.type == 'browser' }
      expect(browser_target).not_to be_nil
    end
  end

  it 'should be able to use the default page in the browser' do
    with_test_state do |page:, browser:, **|
      all_pages = browser.pages
      original_page = all_pages.find { |candidate| candidate != page }
      expect(
        original_page.evaluate('() => ["Hello", "world"].join(" ")'),
      ).to eq('Hello world')
      expect(original_page.query_selector('body')).not_to be_nil
    end
  end

  it 'should be able to use async waitForTarget' do
    with_test_state do |page:, server:, context:, **|
      target_promise = context.async_wait_for_target(
        predicate: ->(target) { target.page&.url == "#{server.cross_process_prefix}/empty.html" },
        timeout: 3000,
      )

      page.evaluate(
        '(url) => { window.open(url); }',
        "#{server.cross_process_prefix}/empty.html",
      )

      other_page = target_promise.wait.page
      expect(other_page.url).to eq("#{server.cross_process_prefix}/empty.html")
      expect(page).not_to eq(other_page)
    end
  end

  it 'should report when a new page is created and closed' do
    with_test_state do |page:, server:, context:, **|
      target_promise = context.async_wait_for_target(
        predicate: ->(target) { target.url == "#{server.cross_process_prefix}/empty.html" },
        timeout: 3000,
      )

      page.evaluate(
        '(url) => { window.open(url); }',
        "#{server.cross_process_prefix}/empty.html",
      )

      other_page = target_promise.wait.page
      expect(other_page.url).to include(server.cross_process_prefix)
      expect(other_page.evaluate('() => ["Hello", "world"].join(" ")')).to eq('Hello world')
      expect(other_page.query_selector('body')).not_to be_nil

      all_pages = context.pages
      expect(all_pages).to include(page)
      expect(all_pages).to include(other_page)

      closed_target_promise = async_promise { wait_for_event(context, 'targetdestroyed') }
      other_page.close
      closed_target = closed_target_promise.wait
      expect(closed_target.page).to eq(other_page)

      all_pages = context.targets.map(&:page).compact
      expect(all_pages).to include(page)
      expect(all_pages).not_to include(other_page)
    end
  end

  it 'should report when a service worker is created and destroyed' do
    with_test_state do |page:, server:, context:, **|
      page.goto(server.empty_page)
      created_target_promise = async_promise do
        wait_for_event(
          context,
          'targetcreated',
          predicate: ->(target) { target.type == 'service_worker' },
        )
      end

      page.goto("#{server.prefix}/serviceworkers/empty/sw.html")
      created_target = created_target_promise.wait

      expect(created_target.type).to eq('service_worker')
      expect(created_target.url).to eq("#{server.prefix}/serviceworkers/empty/sw.js")

      destroyed_target_promise = async_promise do
        wait_for_event(
          context,
          'targetdestroyed',
          predicate: ->(target) { target == created_target },
        )
      end
      page.evaluate(<<~JAVASCRIPT)
        () => {
          return globalThis.registrationPromise.then((registration) => {
            return registration.unregister();
          });
        }
      JAVASCRIPT
      expect(destroyed_target_promise.wait).to eq(created_target)
    end
  end

  it 'should create a worker from a service worker' do
    with_test_state do |page:, server:, context:, **|
      page.goto("#{server.prefix}/serviceworkers/empty/sw.html")

      target = context.wait_for_target(
        predicate: ->(target) { target.type == 'service_worker' },
        timeout: 3000,
      )
      worker = target.worker

      expect(worker.evaluate('() => self.toString()')).to eq('[object ServiceWorkerGlobalScope]')
    end
  end

  it 'should close a service worker' do
    with_test_state do |page:, server:, context:, **|
      page.goto("#{server.prefix}/serviceworkers/empty/sw.html")

      target = context.wait_for_target(
        predicate: ->(target) { target.type == 'service_worker' },
        timeout: 3000,
      )
      worker = target.worker

      destroyed_target_promise = async_promise do
        wait_for_event(
          context,
          'targetdestroyed',
          predicate: ->(event) { event == target },
        )
      end
      worker.close
      expect(destroyed_target_promise.wait).to eq(target)
    end
  end

  it 'should create a worker from a shared worker' do
    with_test_state do |page:, server:, context:, **|
      page.goto(server.empty_page)
      page.evaluate(%q{() => { new SharedWorker('data:text/javascript,console.log("hi")'); }})

      target = context.wait_for_target(
        predicate: ->(target) { target.type == 'shared_worker' },
        timeout: 3000,
      )
      worker = target.worker

      expect(worker.evaluate('() => self.toString()')).to eq('[object SharedWorkerGlobalScope]')
    end
  end

  it 'should close a shared worker' do
    with_test_state do |page:, server:, context:, **|
      page.goto(server.empty_page)
      page.evaluate(%q{() => { new SharedWorker('data:text/javascript,console.log("hi2")'); }})

      target = context.wait_for_target(
        predicate: ->(target) { target.type == 'shared_worker' },
        timeout: 3000,
      )
      worker = target.worker

      destroyed_target_promise = async_promise do
        wait_for_event(
          context,
          'targetdestroyed',
          predicate: ->(event) { event == target },
        )
      end
      worker.close
      expect(destroyed_target_promise.wait).to eq(target)
    end
  end

  it 'should report when a target url changes' do
    with_test_state do |page:, server:, context:, **|
      page.goto(server.empty_page)

      changed_target_promise = async_promise { wait_for_event(context, 'targetchanged') }
      page.goto("#{server.cross_process_prefix}/")
      expect(changed_target_promise.wait.url).to eq("#{server.cross_process_prefix}/")

      changed_target_promise = async_promise { wait_for_event(context, 'targetchanged') }
      page.goto(server.empty_page)
      expect(changed_target_promise.wait.url).to eq(server.empty_page)
    end
  end

  it 'should not report uninitialized pages' do
    with_test_state do |context:, **|
      target_changed = false
      listener = lambda {
        target_changed = true
      }
      context.on('targetchanged', &listener)

      target, new_page = await_promises(
        async_promise { wait_for_event(context, 'targetcreated') },
        async_promise { context.new_page },
      )
      expect(target.url).to eq('about:blank')

      target_promise = async_promise { wait_for_event(context, 'targetcreated') }
      evaluate_promise = async_promise { new_page.evaluate('() => window.open("about:blank")') }
      target2 = target_promise.wait
      expect(target2.url).to eq('about:blank')
      evaluate_promise.wait
      new_page.close

      expect(target_changed).to eq(false)
      context.off('targetchanged', listener)
    end
  end

  it 'should not crash while redirecting if original request was missed' do
    with_test_state do |page:, server:, context:, **|
      response_writer = nil
      server.set_route('/one-style.css') do |_req, writer|
        response_writer = writer
      end

      await_promises(
        async_promise do
          page.evaluate(
            '(url) => { window.open(url); }',
            "#{server.prefix}/one-style.html",
          )
        end,
        async_promise { server.wait_for_request('/one-style.css') },
      )

      target = context.wait_for_target(
        predicate: ->(candidate) { candidate.url.include?('one-style.html') },
        timeout: 3000,
      )
      new_page = target.page
      load_promise = async_promise { wait_for_event(new_page, 'load') }

      response_writer.status = 302
      response_writer.add_header('location', '/injectedstyle.css')
      response_writer.finish

      load_promise.wait
      new_page.close
    end
  end

  it 'should have an opener' do
    with_test_state do |page:, server:, context:, **|
      page.goto(server.empty_page)

      created_target_promise = async_promise { wait_for_event(context, 'targetcreated') }
      page.goto("#{server.prefix}/popup/window-open.html")
      created_target = created_target_promise.wait

      expect(created_target.page.url).to eq("#{server.prefix}/popup/popup.html")
      expect(created_target.opener).to eq(page.target)
      expect(page.target.opener).to be_nil
    end
  end

  describe 'Browser.waitForTarget' do
    it 'should wait for a target' do
      with_test_state do |browser:, server:, context:, **|
        target_promise = browser.async_wait_for_target(
          predicate: ->(target) { target.url == server.empty_page },
          timeout: 3000,
        )

        page = context.new_page
        expect(target_promise.completed?).to eq(false)
        page.goto(server.empty_page)
        target = target_promise.wait
        expect(target.page).to eq(page)
        page.close
      end
    end

    it 'should timeout waiting for a non-existent target' do
      with_test_state do |browser:, server:, **|
        expect do
          browser.wait_for_target(
            predicate: ->(target) { target.url == "#{server.prefix}/does-not-exist.html" },
            timeout: 1,
          )
        end.to raise_error(Puppeteer::TimeoutError)
      end
    end

    it 'should be able to abort' do
      skip('AbortSignal is not supported')
    end
  end
end
