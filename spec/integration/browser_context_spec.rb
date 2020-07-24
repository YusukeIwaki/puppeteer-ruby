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

      popup_target = await_all(
        resolvable_future { |f| browser.once('targetcreated') { |target| f.fulfill(target) } },
        page.async_evaluate('url => { window.open(url); return null }', 'about:blank'),
      ).first
      expect(popup_target.browser_context).to eq(context)
      context.close
    end
  end

  describe 'target events' do
    sinatra do
      get '/test' do
        'test'
      end
    end

    it 'should fire target events' do
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
      page.goto('http://127.0.0.1:4567/test')
      page.close

      expect(events).to eq([
        "CREATED: about:blank",
        "CHANGED: http://127.0.0.1:4567/test",
        "DESTROYED: http://127.0.0.1:4567/test",
      ])
      context.close
    end
  end

  describe 'wait for target' do
    sinatra do
      get '/test' do
        'test'
      end
    end

    it 'should wait for a target' do
      context = browser.create_incognito_browser_context
      resolved = false
      target_promise = context.async_wait_for_target(predicate: -> (target) { target.url == 'http://127.0.0.1:4567/test' })
      target_promise.then { resolved = true }

      page = context.new_page
      expect(resolved).to eq(false)
      page.goto('http://127.0.0.1:4567/test')
      target = await target_promise
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
      page.goto('http://127.0.0.1:4567/test')
      expect(resolved).to eq(false)
      expect { await target_promise }.to raise_error(Puppeteer::TimeoutError)
      context.close
    end
  end

  describe 'isolation' do
    sinatra do
      get '/isolation' do
        'test isolation'
      end
    end

    it 'should isolate localStorage and cookies' do
      # Create two incognito contexts.
      contexts = 2.times.map { browser.create_incognito_browser_context }

      contexts.each do |context|
        expect(context.targets.length).to eq(0)
      end

      pages = contexts.map.with_index do |context, index|
        context.new_page.tap do |page|
          page.goto('http://127.0.0.1:4567/isolation')
          page.evaluate <<~JAVASCRIPT
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

    it 'should work across sessions' do
      expect(browser.browser_contexts.length).to eq(1)
      context = browser.create_incognito_browser_context
      expect(browser.browser_contexts.length).to eq(2)
      Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint) do |remote_browser|
        expect(remote_browser.browser_contexts.length).to eq(2)
      end
      context.close
    end
  end
end
