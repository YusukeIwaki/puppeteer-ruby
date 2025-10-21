require 'spec_helper'

RSpec.describe Puppeteer::BrowserContext, puppeteer: :browser do
  describe 'default context' do
    it 'should have default context' do
      expect(browser.browser_contexts.length).to eq(1)

      default_context = browser.browser_contexts.first
      expect(default_context).not_to be_incognito
    end

    it 'cannot be closed' do
      default_context = browser.browser_contexts.first
      expect { default_context.close }.to raise_error(/cannot be closed/)
    end
  end

  describe 'create incognito context' do
    it 'should create new incognito context' do
      context = browser.create_incognito_browser_context
      expect(context).to be_incognito
      expect(browser.browser_contexts.length).to eq(2)
      expect(browser.browser_contexts).to include(context)

      context.close
      expect(browser.browser_contexts.length).to eq(1)
    end

    it 'should close all belonging targets once closing context' do
      expect(browser.pages.length).to eq(1)

      context = browser.create_incognito_browser_context
      context.new_page
      expect(browser.pages.length).to eq(2)
      expect(context.pages.length).to eq(1)

      context.close
      expect(browser.pages.length).to eq(1)
    end

    it 'window.open should use parent tab context' do
      context = browser.create_incognito_browser_context
      page = context.new_page
      page.goto('about:blank')

      target_promise = Concurrent::Promises.resolvable_future.tap do |future|
        browser.once('targetcreated') { |target| future.fulfill(target) }
      end
      popup_target = Puppeteer::ConcurrentRubyUtils.with_waiting_for_complete(target_promise) do
        page.evaluate('url => { window.open(url); return null }', 'about:blank')
      end
      expect(popup_target.browser_context).to eq(context)
      context.close
    end
  end

  describe 'target events', sinatra: true do
    before {
      sinatra.get('/test') do
        'test'
      end
    }

    it_fails_firefox 'should fire target events' do
      context = browser.create_incognito_browser_context
      events = []
      context.on('targetcreated') do |target|
        events << "CREATED: #{target.url}"
      end
      context.on('targetchanged') do |target|
        events << "CHANGED: #{target.url}"
      end
      context.on('targetdestroyed') do |target|
        events << "DESTROYED: #{target.url}"
      end

      page = context.new_page
      page.goto("#{server_prefix}/test")
      page.close

      expect(events).to eq([
        "CREATED: about:blank",
        "CHANGED: #{server_prefix}/test",
        "DESTROYED: #{server_prefix}/test",
      ])
      context.close
    end
  end

  describe 'wait for target', sinatra: true do
    before {
      sinatra.get('/test') do
        'test'
      end
    }

    it_fails_firefox 'should wait for a target' do
      context = browser.create_incognito_browser_context
      resolved = false
      target_promise = context.async_wait_for_target(predicate: -> (target) { target.url == "#{server_prefix}/test" })
      target_promise.then { resolved = true }

      page = context.new_page
      expect(resolved).to eq(false)
      page.goto("#{server_prefix}/test")
      target = target_promise.value!
      expect(target.page).to eq(page)
      context.close
    end

    it 'should timeout waiting for a non-existent target' do
      context = browser.create_incognito_browser_context
      resolved = false
      target_promise = context.async_wait_for_target(timeout: 500, predicate: -> (target) { target.url == '?????' })
      target_promise.then { resolved = true }

      page = context.new_page
      expect(resolved).to eq(false)
      page.goto("#{server_prefix}/test")
      expect(resolved).to eq(false)
      expect { target_promise.value! }.to raise_error(Puppeteer::TimeoutError)
      context.close
    end
  end

  describe 'isolation', sinatra: true do
    before {
      sinatra.get('/isolation') do
        'test isolation'
      end
    }

    it 'should isolate localStorage and cookies' do
      # Create two incognito contexts.
      contexts = 2.times.map { browser.create_incognito_browser_context }

      contexts.each do |context|
        expect(context.targets.length).to eq(0)
      end

      pages = contexts.map.with_index do |context, index|
        context.new_page.tap do |page|
          page.goto("#{server_prefix}/isolation")
          page.evaluate(<<~JAVASCRIPT)
          () => {
            localStorage.setItem('name', 'page#{index}');
            document.cookie = 'name=page#{index}';
          }
          JAVASCRIPT
        end
      end

      contexts.each_with_index do |context, index|
        expect(context.targets.length).to eq(1)

        # Make sure pages don't share localstorage or cookies.
        expect(pages[index].evaluate("() => localStorage.getItem('name')")).to eq("page#{index}")
        expect(pages[index].evaluate("() => document.cookie")).to eq("name=page#{index}")
      end

      contexts.each(&:close)
      expect(browser.browser_contexts.length).to eq(1)
    end

    it_fails_firefox 'should work across sessions' do
      expect(browser.browser_contexts.length).to eq(1)
      context = browser.create_incognito_browser_context
      expect(browser.browser_contexts.length).to eq(2)
      Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint) do |remote_browser|
        expect(remote_browser.browser_contexts.length).to eq(2)
      end
      context.close
    end
  end

  it 'should provide a context id' do
    expect(browser.browser_contexts.length).to eq(1)
    expect(browser.browser_contexts.first.id).to be_nil

    context = browser.create_incognito_browser_context
    begin
      expect(browser.browser_contexts.length).to eq(2)
      expect(browser.browser_contexts.last.id).not_to be_nil
    ensure
      context.close
    end
  end
end
