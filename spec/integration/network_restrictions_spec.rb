require 'spec_helper'

RSpec.describe 'Network Restrictions' do
  it 'should block page.goto when destination is in the blocklist', sinatra: true do
    with_browser(block_list: ['*://*:*/empty.html']) do |browser|
      with_test_state(browser: browser) do |page:, server:, **|
        allowed_url = "#{server.prefix}/title.html"
        blocked_url = "#{server.prefix}/empty.html"

        page.goto(allowed_url)
        error = nil
        begin
          page.goto(blocked_url)
        rescue => err
          error = err
        end
        expect(error).not_to be_nil
        expect(error.message).to include('net::ERR_INTERNET_DISCONNECTED')
      end
    end
  end

  it 'should block window.location.href navigation to URLs in the blocklist', sinatra: true do
    with_browser(block_list: ['*://*:*/empty.html']) do |browser|
      with_test_state(browser: browser) do |page:, server:, **|
        allowed_url = "#{server.prefix}/title.html"
        blocked_url = "#{server.prefix}/empty.html"

        page.goto(allowed_url)
        navigation_promise = async_promise do
          begin
            page.wait_for_navigation(timeout: 2000)
          rescue => err
            err
          end
        end
        page.evaluate('(url) => { window.location.href = url; }', blocked_url)
        navigation_promise.wait

        expect(page.url).not_to eq(blocked_url)
      end
    end
  end

  it 'should fail fetch requests to URLs in the blocklist', sinatra: true do
    with_browser(block_list: ['*://*:*/empty.html']) do |browser|
      with_test_state(browser: browser) do |page:, server:, **|
        allowed_url = "#{server.prefix}/title.html"
        blocked_url = "#{server.prefix}/empty.html"

        page.goto(allowed_url)
        fetch_error = page.evaluate(<<~JAVASCRIPT, blocked_url)
          async (url) => {
            try {
              await fetch(url);
              return null;
            } catch (e) {
              return e.message;
            }
          }
        JAVASCRIPT
        expect(fetch_error).to be_truthy
        expect(fetch_error).to include('Failed to fetch')
      end
    end
  end

  it 'should prevent loading of blocklisted subresources (e.g., images)', sinatra: true do
    with_browser(block_list: ['*://*:*/pptr.png']) do |browser|
      with_test_state(browser: browser) do |page:, server:, **|
        allowed_url = "#{server.prefix}/one-style.css"
        blocked_url = "#{server.prefix}/pptr.png"
        failed_requests = {}
        finished_requests = Set.new

        page.on('requestfailed') do |request|
          failed_requests[request.url] = request.failure&.[](:errorText)
        end
        page.on('requestfinished') do |request|
          finished_requests.add(request.url)
        end

        page.goto(server.empty_page)
        page.set_content(<<~HTML, wait_until: 'networkidle0')
          <img src="#{blocked_url}" />
          <link rel="stylesheet" href="#{allowed_url}" />
        HTML

        expect(failed_requests.key?(blocked_url)).to eq(true)
        expect(failed_requests[blocked_url]).to include('net::ERR_INTERNET_DISCONNECTED')
        expect(finished_requests.include?(allowed_url)).to eq(true)
      end
    end
  end

  it 'should detach from blocked targets when connecting to running browser', sinatra: true do
    with_test_state do |browser:, page:, server:, **|
      blocked_url = "#{server.prefix}/empty.html"
      page.goto(blocked_url)

      connected_browser = Puppeteer.connect(
        browser_ws_endpoint: browser.ws_endpoint,
        block_list: ['*://*:*/empty.html'],
      )
      begin
        blocked_target = connected_browser.targets.find { |target| target.url == blocked_url }
        expect(blocked_target).to be_nil
      ensure
        connected_browser.disconnect
      end
    end
  end

  it 'should not block chrome://version/ even if it matches blocklist' do
    chrome_url = 'chrome://version/'
    with_browser(block_list: [chrome_url]) do |browser|
      with_test_state(browser: browser) do |page:, **|
        page.goto(chrome_url)
        expect(page.url).to eq(chrome_url)
      end
    end
  end
end
