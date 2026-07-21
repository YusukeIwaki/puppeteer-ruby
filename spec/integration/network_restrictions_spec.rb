require 'spec_helper'

RSpec.describe 'Network Restrictions' do
  include Utils::AttachFrame

  def with_network_restrictions(**options, &block)
    with_browser(**options) do |browser|
      with_test_state(browser: browser, &block)
    end
  end

  describe 'blocklist validation' do
    let(:block_list) do
      [
        '*://*:*/empty.html',
        '*://*:*/pptr.png',
        '*://*:*/serviceworkers/empty/sw.js',
        '*://*:*/serviceworkers/fetch/style.css',
      ]
    end

    it 'should block page.goto when the destination is in the blocklist', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, **|
        allowed_url = "#{server.prefix}/title.html"
        blocked_url = "#{server.prefix}/empty.html"

        page.goto(allowed_url)
        expect { page.goto(blocked_url) }.to raise_error(
          /is blocked by blocklist\/allowlist rules/,
        )
      end
    end

    it 'should block window.location.href navigation to URLs in the blocklist', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, **|
        allowed_url = "#{server.prefix}/title.html"
        blocked_url = "#{server.prefix}/empty.html"

        page.goto(allowed_url)
        navigation_promise = async_promise do
          page.wait_for_navigation(timeout: 2000)
        rescue => err
          err
        end
        page.evaluate('(url) => { window.location.href = url; }', blocked_url)
        navigation_promise.wait

        expect(page.url).not_to eq(blocked_url)
      end
    end

    it 'should fail fetch requests to URLs in the blocklist', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, **|
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
        expect(fetch_error).to include('Failed to fetch')
      end
    end

    it 'should fail service worker registration for blocklisted script URLs', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, **|
        page.goto("#{server.prefix}/title.html")
        blocked_url = "#{server.prefix}/serviceworkers/empty/sw.js"

        service_worker_error = page.evaluate(<<~JAVASCRIPT, blocked_url)
          async (url) => {
            try {
              await navigator.serviceWorker.register(url);
              return null;
            } catch (e) {
              return e.message;
            }
          }
        JAVASCRIPT
        expect(service_worker_error).to be_truthy
        expect(service_worker_error).to include('Failed to register a ServiceWorker')
      end
    end

    it 'should fail fetch requests from within a service worker to URLs in the blocklist', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, context:, **|
        page.goto("#{server.prefix}/serviceworkers/fetch/sw.html")
        target = context.wait_for_target(
          predicate: ->(candidate) { candidate.type == 'service_worker' },
          timeout: 3000,
        )
        worker = target.worker
        blocked_url = "#{server.prefix}/serviceworkers/fetch/style.css"

        fetch_error = worker.evaluate(<<~JAVASCRIPT, blocked_url)
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

    it 'should prevent loading of blocklisted subresources (e.g., images)', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, **|
        allowed_url = "#{server.prefix}/one-style.css"
        blocked_url = "#{server.prefix}/pptr.png"
        failed_requests = {}
        finished_requests = Set.new

        page.on('requestfailed') do |request|
          failed_requests[request.url] = request.failure&.[](:errorText)
        end
        page.on('requestfinished') { |request| finished_requests.add(request.url) }

        page.goto("#{server.prefix}/title.html")
        idle = page.async_wait_for_network_idle
        page.set_content(<<~HTML)
          <img src="#{blocked_url}" />
          <link rel="stylesheet" href="#{allowed_url}" />
        HTML
        idle.wait

        expect(failed_requests.key?(blocked_url)).to eq(true)
        expect(failed_requests[blocked_url]).to include('net::ERR_INTERNET_DISCONNECTED')
        expect(finished_requests.include?(allowed_url)).to eq(true)
      end
    end

    it 'should block frame.goto when the destination is in the blocklist', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, **|
        page.goto("#{server.prefix}/frames/one-frame.html")
        frame = page.frames.find { |candidate| candidate != page.main_frame }
        blocked_url = "#{server.prefix}/empty.html"

        expect { frame.goto(blocked_url) }.to raise_error(
          /is blocked by blocklist\/allowlist rules/,
        )
      end
    end

    it 'should block OOPIF frame.goto when the destination is in the blocklist', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, **|
        page.goto("#{server.prefix}/title.html")
        frame = attach_frame(page, 'frame1', "#{server.cross_process_prefix}/title.html")
        blocked_url = "#{server.prefix}/empty.html"

        expect { frame.goto(blocked_url) }.to raise_error(
          /is blocked by blocklist\/allowlist rules/,
        )
      end
    end

    it 'should block CDP standard emulation reset when blocklist is active' do
      with_network_restrictions(block_list: block_list) do |page:, **|
        session = page.target.create_cdp_session
        expect do
          session.send_message('Network.emulateNetworkConditions', {
            offline: false,
            latency: 0,
            downloadThroughput: 0,
            uploadThroughput: 0,
          })
        end.to raise_error(
          /Cannot reset network conditions: rule-based emulation is enabled/,
        )
      end
    end

    it 'should block page.emulateNetworkConditions reset when blocklist is active' do
      with_network_restrictions(block_list: block_list) do |page:, **|
        conditions = Puppeteer::NetworkCondition.new(download: 0, upload: 0, latency: 0)
        expect { page.emulate_network_conditions(conditions) }.to raise_error(
          /Cannot reset network conditions: rule-based emulation is enabled/,
        )
      end
    end

    it 'should block fetch requests from within local iframes to URLs in the blocklist', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, **|
        page.goto("#{server.prefix}/frames/one-frame.html")
        frame = page.frames.find { |candidate| candidate != page.main_frame }
        fetch_error = frame.evaluate(<<~JAVASCRIPT, "#{server.prefix}/empty.html")
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

    it 'should block fetch requests from within OOPIFs to URLs in the blocklist', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, **|
        page.goto("#{server.prefix}/title.html")
        frame = attach_frame(page, 'frame1', "#{server.cross_process_prefix}/title.html")
        fetch_error = frame.evaluate(<<~JAVASCRIPT, "#{server.prefix}/empty.html")
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

    it 'should block iframe content from loading if the iframe URL is in the blocklist', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, **|
        page.goto("#{server.prefix}/title.html")
        page.set_content("<iframe src=\"#{server.prefix}/empty.html\"></iframe>")
        frame = page.frames.find { |candidate| candidate != page.main_frame }

        expect(frame.content).not_to include("Hi, I'm frame")
      end
    end

    it 'should block out-of-process iframe (OOPIF) content from loading if the iframe URL is in the blocklist', sinatra: true do
      with_network_restrictions(block_list: block_list) do |page:, server:, **|
        page.goto("#{server.prefix}/title.html")
        frame = attach_frame(page, 'frame1', "#{server.cross_process_prefix}/empty.html")
        expect(frame.url).to eq('chrome-error://chromewebdata/')
      end
    end
  end

  describe 'allowlist validation' do
    let(:allow_list) { ['*://*:*/empty.html', '*://*:*/one-style.css'] }

    it 'should only allow navigation to URLs in the allowlist', sinatra: true do
      with_network_restrictions(allow_list: allow_list) do |page:, server:, **|
        allowed_url = "#{server.prefix}/empty.html"
        blocked_url = "#{server.prefix}/title.html"

        page.goto(allowed_url)
        expect { page.goto(blocked_url) }.to raise_error(
          /is blocked by blocklist\/allowlist rules/,
        )
        expect(page.url).not_to eq(blocked_url)
      end
    end

    it 'should block window.location.href navigation to URLs not in the allowlist', sinatra: true do
      with_network_restrictions(allow_list: allow_list) do |page:, server:, **|
        allowed_url = "#{server.prefix}/empty.html"
        blocked_url = "#{server.prefix}/title.html"

        page.goto(allowed_url)
        navigation_promise = async_promise do
          page.wait_for_navigation(timeout: 2000)
        rescue => err
          err
        end
        page.evaluate('(url) => { window.location.href = url; }', blocked_url)
        navigation_promise.wait

        expect(page.url).not_to eq(blocked_url)
        expect(page.content).not_to include('Woof-Woof')
      end
    end

    it 'should fail fetch requests to URLs not in the allowlist', sinatra: true do
      with_network_restrictions(allow_list: allow_list) do |page:, server:, **|
        page.goto("#{server.prefix}/empty.html")
        fetch_error = page.evaluate(<<~JAVASCRIPT, "#{server.prefix}/title.html")
          async (url) => {
            try {
              await fetch(url);
              return null;
            } catch (e) {
              return e.message;
            }
          }
        JAVASCRIPT
        expect(fetch_error).to include('Failed to fetch')
      end
    end

    it 'should fail service worker registration for script URLs not in the allowlist', sinatra: true do
      with_network_restrictions(allow_list: allow_list) do |page:, server:, **|
        page.goto("#{server.prefix}/empty.html")
        blocked_url = "#{server.prefix}/serviceworkers/empty/sw.js"
        service_worker_error = page.evaluate(<<~JAVASCRIPT, blocked_url)
          async (url) => {
            try {
              await navigator.serviceWorker.register(url);
              return null;
            } catch (e) {
              return e.message;
            }
          }
        JAVASCRIPT
        expect(service_worker_error).to be_truthy
        expect(service_worker_error).to include('Failed to register a ServiceWorker')
      end
    end

    it 'should prevent loading of subresources not in the allowlist (e.g., images)', sinatra: true do
      with_network_restrictions(allow_list: allow_list) do |page:, server:, **|
        allowed_url = "#{server.prefix}/one-style.css"
        blocked_url = "#{server.prefix}/pptr.png"
        failed_requests = {}
        finished_requests = Set.new

        page.on('requestfailed') do |request|
          failed_requests[request.url] = request.failure&.[](:errorText)
        end
        page.on('requestfinished') { |request| finished_requests.add(request.url) }

        page.goto("#{server.prefix}/empty.html")
        idle = page.async_wait_for_network_idle
        page.set_content(<<~HTML)
          <img src="#{blocked_url}" />
          <link rel="stylesheet" href="#{allowed_url}" />
        HTML
        idle.wait

        expect(failed_requests.key?(blocked_url)).to eq(true)
        expect(failed_requests[blocked_url]).to include('net::ERR_INTERNET_DISCONNECTED')
        expect(finished_requests.include?(allowed_url)).to eq(true)
      end
    end

    it 'should block OOPIF frame.goto when the destination is not in the allowlist', sinatra: true do
      with_network_restrictions(allow_list: allow_list) do |page:, server:, **|
        page.goto("#{server.prefix}/empty.html")
        frame = attach_frame(page, 'frame1', "#{server.cross_process_prefix}/empty.html")

        expect { frame.goto("#{server.prefix}/title.html") }.to raise_error(
          /is blocked by blocklist\/allowlist rules/,
        )
      end
    end

    it 'should block fetch requests from within OOPIFs to URLs not in the allowlist', sinatra: true do
      with_network_restrictions(allow_list: allow_list) do |page:, server:, **|
        page.goto("#{server.prefix}/empty.html")
        frame = attach_frame(page, 'frame1', "#{server.cross_process_prefix}/empty.html")
        fetch_error = frame.evaluate(<<~JAVASCRIPT, "#{server.prefix}/title.html")
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

    it 'should block iframe content from loading if the iframe URL is not in the allowlist', sinatra: true do
      with_network_restrictions(allow_list: allow_list) do |page:, server:, **|
        page.goto("#{server.prefix}/empty.html")
        page.set_content("<iframe src=\"#{server.prefix}/title.html\"></iframe>")
        frame = page.frames.find { |candidate| candidate != page.main_frame }

        expect(frame.content).not_to include("Hi, I'm frame")
      end
    end

    it 'should block out-of-process iframe (OOPIF) content from loading if the iframe URL is not in the allowlist', sinatra: true do
      with_network_restrictions(allow_list: allow_list) do |page:, server:, **|
        page.goto("#{server.prefix}/empty.html")
        frame = attach_frame(page, 'frame1', "#{server.cross_process_prefix}/title.html")
        expect(frame.url).to eq('chrome-error://chromewebdata/')
      end
    end

    it 'should block CDP standard emulation reset when allowlist is active' do
      with_network_restrictions(allow_list: allow_list) do |page:, **|
        session = page.target.create_cdp_session
        expect do
          session.send_message('Network.emulateNetworkConditions', {
            offline: false,
            latency: 0,
            downloadThroughput: 0,
            uploadThroughput: 0,
          })
        end.to raise_error(
          /Cannot reset network conditions: rule-based emulation is enabled/,
        )
      end
    end

    it 'should block page.emulateNetworkConditions reset when allowlist is active' do
      with_network_restrictions(allow_list: allow_list) do |page:, **|
        conditions = Puppeteer::NetworkCondition.new(download: 0, upload: 0, latency: 0)
        expect { page.emulate_network_conditions(conditions) }.to raise_error(
          /Cannot reset network conditions: rule-based emulation is enabled/,
        )
      end
    end
  end

  it 'should detach from targets violating blocklist when connecting to a running browser', sinatra: true do
    with_test_state(create_page: false) do |browser:, server:, **|
      page = browser.new_page
      connected_browser = nil
      begin
        blocked_url = "#{server.prefix}/empty.html"
        page.goto(blocked_url)
        connected_browser = Puppeteer.connect(
          browser_ws_endpoint: browser.ws_endpoint,
          block_list: ['*://*:*/empty.html'],
        )

        expect(connected_browser.targets.none? { |target| target.url == blocked_url }).to eq(true)
      ensure
        connected_browser&.disconnect
        page.close unless page.closed?
      end
    end
  end

  it 'should detach from targets violating allowlist when connecting to a running browser', sinatra: true do
    with_test_state(create_page: false) do |browser:, server:, **|
      page = browser.new_page
      connected_browser = nil
      begin
        blocked_url = "#{server.prefix}/title.html"
        page.goto(blocked_url)
        connected_browser = Puppeteer.connect(
          browser_ws_endpoint: browser.ws_endpoint,
          allow_list: ['*://*:*/empty.html'],
        )

        expect(connected_browser.targets.none? { |target| target.url == blocked_url }).to eq(true)
      ensure
        connected_browser&.disconnect
        page.close unless page.closed?
      end
    end
  end

  it 'should throw an error when both blocklist and allowlist are specified' do
    expect do
      Puppeteer.launch(
        **default_launch_options,
        block_list: ['*://*:*/empty.html'],
        allow_list: ['*://*:*/empty.html'],
      )
    end.to raise_error(/Cannot specify both blocklist and allowlist/)

    with_test_state(create_page: false) do |browser:, **|
      expect do
        Puppeteer.connect(
          browser_ws_endpoint: browser.ws_endpoint,
          block_list: ['*://*:*/empty.html'],
          allow_list: ['*://*:*/empty.html'],
        )
      end.to raise_error(/Cannot specify both blocklist and allowlist/)
    end
  end

  it 'should throw an error for an invalid pattern' do
    expect do
      Puppeteer.launch(
        **default_launch_options,
        block_list: ['(invalid pattern'],
      )
    end.to raise_error(/URLPattern/)
  end

  it 'should block chrome://version/ when it matches blocklist' do
    blocked_url = 'chrome://version/'
    with_network_restrictions(block_list: [blocked_url]) do |page:, **|
      expect { page.goto(blocked_url) }.to raise_error(
        /is blocked by blocklist\/allowlist rules/,
      )
    end
  end
end
