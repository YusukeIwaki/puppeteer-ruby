require 'spec_helper'

RSpec.describe 'Prerender' do
  it 'can navigate to a prerendered page via input' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/prerender/index.html")

      button = page.wait_for_selector('button')
      button.click
      button.dispose

      link = page.wait_for_selector('a')
      page.wait_for_navigation { link.click }
      link.dispose
      expect(
        page.evaluate("() => document.querySelector('div')?.innerText"),
      ).to eq('true')
    end
  end

  it 'can navigate to a prerendered page via Locator' do
    with_test_state do |page:, server:, **|
      timeout = 5000
      3.times do
        page.goto("#{server.prefix}/prerender/declarative.html")

        promises = []
        page
          .locator('a')
          .set_timeout(timeout)
          .on('action') { promises << page.async_wait_for_navigation }
          .click
        await_promises(*promises)

        expect(
          page.evaluate("() => document.querySelector('div')?.innerText"),
        ).to eq('true')
      end
    end
  end

  it 'can navigate to a prerendered page via Puppeteer' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/prerender/index.html")

      button = page.wait_for_selector('button')
      button.click
      button.dispose

      page.goto("#{server.prefix}/prerender/target.html")
      expect(
        page.evaluate("() => document.querySelector('div')?.innerText"),
      ).to eq('false')
    end
  end

  describe 'via frame' do
    it 'can navigate to a prerendered page via input' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/prerender/index.html")

        button = page.wait_for_selector('button')
        button.click
        button.dispose

        main_frame = page.main_frame
        link = main_frame.wait_for_selector('a')
        main_frame.wait_for_navigation { link.click }
        link.dispose
        expect(main_frame).to eq(page.main_frame)
        expect(
          main_frame.evaluate("() => document.querySelector('div')?.innerText"),
        ).to eq('true')
        expect(main_frame).to eq(page.main_frame)
      end
    end

    it 'can navigate to a prerendered page via Puppeteer' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/prerender/index.html")

        button = page.wait_for_selector('button')
        button.click
        button.dispose

        main_frame = page.main_frame
        main_frame.goto("#{server.prefix}/prerender/target.html")
        expect(
          main_frame.evaluate("() => document.querySelector('div')?.innerText"),
        ).to eq('false')
        expect(main_frame).to eq(page.main_frame)
      end
    end
  end

  it 'can screencast' do
    skip('Page#screencast is not implemented in puppeteer-ruby.')
  end

  describe 'with network requests' do
    it 'can receive requests from the prerendered page' do
      with_test_state do |page:, server:, **|
        urls = []
        page.on('request') { |request| urls << request.url }

        page.goto("#{server.prefix}/prerender/index.html")
        button = page.wait_for_selector('button')
        button.click
        button.dispose
        main_frame = page.main_frame
        link = main_frame.wait_for_selector('a')
        main_frame.wait_for_navigation { link.click }
        link.dispose
        expect(main_frame).to eq(page.main_frame)
        expect(
          main_frame.evaluate("() => document.querySelector('div')?.innerText"),
        ).to eq('true')
        expect(main_frame).to eq(page.main_frame)
        expect(urls.any? { |url| url.end_with?('prerender/target.html') }).to eq(true)
        expect(urls.any? { |url| url.include?('prerender/index.html') }).to eq(true)
        expect(urls.any? { |url| url.include?('prerender/target.html?fromPrerendered') }).to eq(true)
      end
    end
  end

  describe 'with emulation' do
    it 'can configure viewport for prerendered pages' do
      with_test_state do |page:, server:, **|
        page.viewport = Puppeteer::Viewport.new(width: 300, height: 400)
        page.goto("#{server.prefix}/prerender/index.html")
        button = page.wait_for_selector('button')
        button.click
        button.dispose
        link = page.wait_for_selector('a')
        page.wait_for_navigation { link.click }
        link.dispose
        result = page.evaluate(<<~JAVASCRIPT)
          () => ({
            width: document.documentElement.clientWidth,
            height: document.documentElement.clientHeight,
            dpr: window.devicePixelRatio,
          })
        JAVASCRIPT
        expect(
          'width' => result['width'],
          'height' => result['height'],
        ).to eq(
          'width' => 300 * result['dpr'],
          'height' => 400 * result['dpr'],
        )
      end
    end
  end
end
