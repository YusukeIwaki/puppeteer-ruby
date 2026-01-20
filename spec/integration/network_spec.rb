require 'spec_helper'

RSpec.describe 'network' do
  include Utils::AttachFrame
  include Utils::Favicon
  include Utils::WaitEvent

  describe 'Page.Events.Request' do
    it 'should fire for navigation requests' do
      with_test_state do |page:, server:, **|
        requests = []
        page.on('request') do |request|
          requests << request unless favicon_request?(request)
        end
        page.goto(server.empty_page)
        expect(requests.length).to eq(1)
      end
    end

    it 'should fire for iframes' do
      with_test_state do |page:, server:, **|
        requests = []
        page.on('request') do |request|
          requests << request unless favicon_request?(request)
        end
        page.goto(server.empty_page)
        attach_frame(page, 'frame1', server.empty_page)
        expect(requests.length).to eq(2)
      end
    end

    it 'should fire for fetches' do
      with_test_state do |page:, server:, **|
        requests = []
        page.on('request') do |request|
          requests << request unless favicon_request?(request)
        end
        page.goto(server.empty_page)
        page.evaluate("() => fetch('/empty.html')")
        expect(requests.length).to eq(2)
      end
    end
  end

  describe 'Request.frame' do
    it 'should work for main frame navigation request' do
      with_test_state do |page:, server:, **|
        requests = []
        page.on('request') do |request|
          requests << request unless favicon_request?(request)
        end
        page.goto(server.empty_page)
        expect(requests.length).to eq(1)
        expect(requests[0].frame).to eq(page.main_frame)
      end
    end

    it 'should work for subframe navigation request' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        requests = []
        page.on('request') do |request|
          requests << request unless favicon_request?(request)
        end
        attach_frame(page, 'frame1', server.empty_page)
        expect(requests.length).to eq(1)
        expect(requests[0].frame).to eq(page.frames[1])
      end
    end

    it 'should work for fetch requests' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        requests = []
        page.on('request') do |request|
          requests << request unless favicon_request?(request)
        end
        page.evaluate("() => fetch('/digits/1.png')")
        expect(requests.length).to eq(1)
        expect(requests[0].frame).to eq(page.main_frame)
      end
    end
  end

  describe 'Request.headers' do
    it 'should define Browser in user agent header' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page)
        user_agent = response.request.headers['user-agent']

        if Puppeteer.env.chrome?
          expect(user_agent).to include('Chrome')
        else
          expect(user_agent).to include('Firefox')
        end
      end
    end

    describe 'cookie header' do
      it 'should show Cookie header' do
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)
          page.evaluate("() => { document.cookie = 'username=John Doe'; }")
          response = page.goto("#{server.prefix}/title.html")

          cookie = response.request.headers['cookie']
          expect(cookie).to include('username=John Doe')
        end
      end

      it 'should show Cookie header for redirect' do
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)
          server.set_redirect('/foo.html', '/title.html')
          page.evaluate("() => { document.cookie = 'username=John Doe'; }")
          response = page.goto("#{server.prefix}/foo.html")

          cookie1 = response.request.redirect_chain[0].headers['cookie']
          expect(cookie1).to include('username=John Doe')

          cookie2 = response.request.headers['cookie']
          expect(cookie2).to include('username=John Doe')
        end
      end

      it 'should show Cookie header for fetch request' do
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)
          page.evaluate("() => { document.cookie = 'username=John Doe'; }")

          response_promise = async_promise do
            wait_for_event(page, 'response', predicate: ->(response) {
              !favicon_request?(response.request)
            })
          end
          page.evaluate("() => fetch('/title.html')")
          response = response_promise.wait

          cookie = response.request.headers['cookie']
          expect(cookie).to include('username=John Doe')
        end
      end
    end
  end

  describe 'Response.headers' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        server.set_route('/empty.html') do |_request, writer|
          writer.add_header('foo', 'bar')
          writer.finish
        end
        response = page.goto(server.empty_page)
        expect(response.headers['foo']).to eq('bar')
      end
    end
  end

  describe 'Request.initiator' do
    it 'should return the initiator' do
      with_test_state do |page:, server:, **|
        initiators = {}
        page.on('request') do |request|
          initiators[request.url.split('/').last] = request.initiator
        end
        page.goto("#{server.prefix}/initiator.html")

        expect(initiators['initiator.html']['type']).to eq('other')
        expect(initiators['initiator.js']['type']).to eq('parser')
        expect(initiators['initiator.js']['url']).to eq("#{server.prefix}/initiator.html")
        expect(initiators['frame.html']['type']).to eq('parser')
        expect(initiators['frame.html']['url']).to eq("#{server.prefix}/initiator.html")
        expect(initiators['script.js']['type']).to eq('parser')
        expect(initiators['script.js']['url']).to eq("#{server.prefix}/frames/frame.html")
        expect(initiators['style.css']['type']).to eq('parser')
        expect(initiators['style.css']['url']).to eq("#{server.prefix}/frames/frame.html")
        expect(initiators['initiator.js']['type']).to eq('parser')
        expect(initiators['injectedfile.js']['type']).to eq('script')
        expect(initiators['injectedfile.js']['stack']['callFrames'][0]['url']).to eq(
          "#{server.prefix}/initiator.js",
        )
        expect(initiators['injectedstyle.css']['type']).to eq('script')
        expect(initiators['injectedstyle.css']['stack']['callFrames'][0]['url']).to eq(
          "#{server.prefix}/initiator.js",
        )
        expect(initiators['initiator.js']['url']).to eq("#{server.prefix}/initiator.html")
      end
    end
  end

  describe 'Response.fromCache' do
    it 'should return |false| for non-cached content' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page)
        expect(response.from_cache?).to eq(false)
      end
    end

    [
      { html: 'one-style.html', resource: 'one-style.css', type: 'stylesheet' },
      { html: 'one-script.html', resource: 'one-script.js', type: 'script' },
    ].each do |entry|
      it "should work for #{entry[:type]}" do
        with_test_state do |page:, server:, **|
          responses = {}
          page.on('response') do |response|
            next if favicon_request?(response.request)

            responses[response.url.split('/').last] = response
          end

          page.goto("#{server.prefix}/cached/#{entry[:html]}")
          page.reload

          expect(responses.size).to eq(2)
          expect(responses[entry[:resource]].status).to eq(200)
          expect(responses[entry[:resource]].from_cache?).to eq(true)
          expect(responses[entry[:html]].status).to eq(304)
          expect(responses[entry[:html]].from_cache?).to eq(false)
        end
      end
    end
  end

  describe 'Response.fromServiceWorker' do
    it 'should return |false| for non-service-worker content' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page)
        expect(response.from_service_worker?).to eq(false)
      end
    end

    it 'Response.fromServiceWorker' do
      with_test_state do |page:, server:, **|
        responses = {}
        page.on('response') do |response|
          next if favicon_request?(response)

          responses[response.url.split('/').last] = response
        end

        page.goto("#{server.prefix}/serviceworkers/fetch/sw.html", wait_until: 'networkidle2')
        page.evaluate('() => globalThis.activationPromise')
        page.reload

        expect(responses.size).to eq(2)
        expect(responses['sw.html'].status).to eq(200)
        expect(responses['sw.html'].from_service_worker?).to eq(true)
        expect(responses['style.css'].status).to eq(200)
        expect(responses['style.css'].from_service_worker?).to eq(true)
      end
    end
  end

  describe 'Request.fetchPostData' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        server.set_route('/post') do |_request, writer|
          writer.finish
        end

        request_promise = async_promise do
          wait_for_event(page, 'request', predicate: ->(request) { !favicon_request?(request) })
        end
        page.evaluate(<<~JAVASCRIPT)
          () => fetch('./post', {
            method: 'POST',
            body: JSON.stringify({foo: 'bar'}),
          })
        JAVASCRIPT
        request = request_promise.wait

        expect(request).to be_truthy
        expect(request.has_post_data?).to eq(true)
        expect(request.fetch_post_data).to eq('{"foo":"bar"}')
      end
    end

    it 'should be |undefined| when there is no post data' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page)
        expect(response.request.has_post_data?).to eq(false)
        expect(response.request.fetch_post_data).to be_nil
      end
    end

    it 'should work with blobs' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        server.set_route('/post') do |_request, writer|
          writer.finish
        end

        request_promise = async_promise do
          wait_for_event(page, 'request', predicate: ->(request) { !favicon_request?(request) })
        end
        page.evaluate(<<~JAVASCRIPT)
          () => fetch('./post', {
            method: 'POST',
            body: new Blob([JSON.stringify({foo: 'bar'})], {
              type: 'application/json',
            }),
          })
        JAVASCRIPT
        request = request_promise.wait

        expect(request).to be_truthy
        expect(request.has_post_data?).to eq(true)
        expect(request.fetch_post_data).to eq('{"foo":"bar"}')
      end
    end
  end

  describe 'Response.text' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        response = page.goto("#{server.prefix}/simple.json")
        response_text = response.text.rstrip
        expect(response_text).to eq('{"foo": "bar"}')
      end
    end

    it 'should return uncompressed text' do
      with_test_state do |page:, server:, **|
        server.enable_gzip('/simple.json')
        response = page.goto("#{server.prefix}/simple.json")
        expect(response.headers['content-encoding']).to eq('gzip')
        response_text = response.text.rstrip
        expect(response_text).to eq('{"foo": "bar"}')
      end
    end

    it 'should throw when requesting body of redirected response' do
      with_test_state do |page:, server:, **|
        server.set_redirect('/foo.html', '/empty.html')
        response = page.goto("#{server.prefix}/foo.html")
        redirect_chain = response.request.redirect_chain
        expect(redirect_chain.length).to eq(1)
        redirected = redirect_chain[0].response
        expect(redirected.status).to eq(302)
        expect { redirected.text }.to raise_error(/Response body is unavailable for redirect responses/)
      end
    end

    it 'should wait until response completes' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        response_body = nil
        server.set_route('/get') do |_request, _writer|
          headers = [['content-type', 'text/plain; charset=utf-8']]
          response_body = Async::HTTP::Body::Writable.new
          ::Protocol::HTTP::Response[200, headers, response_body]
        end

        request_finished = false
        page.on('requestfinished') do |request|
          request_finished ||= request.url.include?('/get')
        end

        response_promise = async_promise do
          page.wait_for_response(predicate: ->(response) { !favicon_request?(response) })
        end
        fetch_promise = async_promise do
          page.evaluate("() => fetch('./get', {method: 'GET'})")
        end
        request_promise = async_promise { server.wait_for_request('/get') }
        request_promise.wait
        response_body.write('hello ')

        page_response = response_promise.wait
        expect(page_response).to be_truthy
        expect(page_response.status).to eq(200)
        expect(request_finished).to eq(false)

        response_text_promise = async_promise { page_response.text }
        response_body.write('wor')
        response_body.write('ld!')
        response_body.close_write

        expect(response_text_promise.wait).to eq('hello world!')
        fetch_promise.wait
      end
    end
  end

  describe 'Response.json' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        response = page.goto("#{server.prefix}/simple.json")
        expect(response.json).to eq({ 'foo' => 'bar' })
      end
    end
  end

  describe 'Response.buffer' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        response = page.goto("#{server.prefix}/pptr.png")
        image_buffer = File.binread(File.join(__dir__, '..', 'assets', 'pptr.png'))
        response_buffer = response.buffer

        expect(response_buffer).to eq(image_buffer)
      end
    end

    it 'should work with compression' do
      with_test_state do |page:, server:, **|
        server.enable_gzip('/pptr.png')
        response = page.goto("#{server.prefix}/pptr.png")
        image_buffer = File.binread(File.join(__dir__, '..', 'assets', 'pptr.png'))
        response_buffer = response.buffer

        expect(response_buffer).to eq(image_buffer)
      end
    end

    it 'should throw if the response does not have a body' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/empty.html")

        server.set_route('/test.html') do |_req, writer|
          writer.add_header('Access-Control-Allow-Origin', '*')
          writer.add_header('Access-Control-Allow-Headers', 'x-ping')
          writer.write('Hello World')
          writer.finish
        end
        url = "#{server.cross_process_prefix}/test.html"
        response_promise = async_promise do
          page.wait_for_response(predicate: ->(response) {
            response.request.method == 'OPTIONS' && response.url == url
          })
        end

        page.evaluate(<<~JAVASCRIPT, url)
          async (src) => {
            const response = await fetch(src, {
              method: 'POST',
              headers: {'x-ping': 'pong'},
            });
            return response;
          }
        JAVASCRIPT

        response = response_promise.wait
        expect {
          response.buffer
        }.to raise_error(
          'Could not load response body for this request. This might happen if the request is a preflight request.',
        )
      end
    end
  end

  describe 'Response.statusText' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        server.set_route('/cool') do |_req, writer|
          writer.status = 200
          writer.add_header('status-text', 'cool!')
          writer.finish
        end
        response = page.goto("#{server.prefix}/cool")
        expect(response.status_text).to eq('cool!')
      end
    end

    it 'handles missing status text' do
      with_test_state do |page:, server:, **|
        server.set_route('/nostatus') do |_req, writer|
          writer.status = 200
          writer.add_header('status-text', '')
          writer.finish
        end
        response = page.goto("#{server.prefix}/nostatus")
        expect(response.status_text).to eq('')
      end
    end
  end

  describe 'Response.timing' do
    it 'returns timing information' do
      with_test_state do |page:, server:, **|
        responses = []
        page.on('response') do |response|
          next if favicon_request?(response)

          responses << response
        end
        page.goto(server.empty_page)
        expect(responses.length).to eq(1)
        expect(responses[0].timing['receiveHeadersEnd']).to be > 0
      end
    end
  end

  describe 'Network Events' do
    it 'Page.Events.Request' do
      with_test_state do |page:, server:, **|
        requests = []
        page.on('request') do |request|
          requests << request unless favicon_request?(request)
        end
        page.goto(server.empty_page)
        expect(requests.length).to eq(1)
        request = requests[0]
        expect(request.url).to eq(server.empty_page)
        expect(request.method).to eq('GET')
        expect(request.response).to be_truthy
        expect(request.frame == page.main_frame).to eq(true)
        expect(request.frame.url).to eq(server.empty_page)
      end
    end

    [
      { html: 'one-style.html', resource: 'one-style.css', type: 'stylesheet' },
      { html: 'one-script.html', resource: 'one-script.js', type: 'script' },
    ].each do |entry|
      it "Page.Events.RequestServedFromCache for #{entry[:type]}" do
        with_test_state do |page:, server:, **|
          cached = []
          page.on('requestservedfromcache') do |request|
            next if favicon_request?(request)

            cached << request.url.split('/').last
          end

          page.goto("#{server.prefix}/cached/#{entry[:html]}")
          expect(cached).to eq([])
          sleep 1
          page.reload
          expect(cached).to eq([entry[:resource]])
        end
      end
    end

    it 'Page.Events.Response' do
      with_test_state do |page:, server:, **|
        responses = []
        page.on('response') do |response|
          responses << response unless favicon_request?(response)
        end
        page.goto(server.empty_page)
        expect(responses.length).to eq(1)
        response = responses[0]
        expect(response.url).to eq(server.empty_page)
        expect(response.status).to eq(200)
        expect(response.ok?).to eq(true)
        expect(response.request).to be_truthy
      end
    end

    it 'Page.Events.RequestFailed' do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          if request.url.end_with?('css')
            request.abort
          else
            request.continue
          end
        end
        failed_requests = []
        page.on('requestfailed') do |request|
          failed_requests << request
        end
        page.goto("#{server.prefix}/one-style.html")
        expect(failed_requests.length).to eq(1)
        failed_request = failed_requests[0]
        expect(failed_request.url).to include('one-style.css')
        expect(failed_request.response).to be_nil
        expect(failed_request.frame).to be_truthy
        if Puppeteer.env.chrome?
          expect(failed_request.failure[:errorText]).to eq('net::ERR_FAILED')
        else
          expect(failed_request.failure[:errorText]).to eq('NS_ERROR_ABORT')
        end
      end
    end

    it 'Page.Events.RequestFinished' do
      with_test_state do |page:, server:, **|
        requests = []
        page.on('requestfinished') do |request|
          requests << request unless favicon_request?(request)
        end
        page.goto(server.empty_page)
        expect(requests.length).to eq(1)
        request = requests[0]
        expect(request.url).to eq(server.empty_page)
        expect(request.response).to be_truthy
        expect(request.frame == page.main_frame).to eq(true)
        expect(request.frame.url).to eq(server.empty_page)
      end
    end

    it 'should fire events in proper order' do
      with_test_state do |page:, server:, **|
        events = []
        page.on('request') { events << 'request' }
        page.on('response') { events << 'response' }
        page.on('requestfinished') { events << 'requestfinished' }
        page.goto(server.empty_page)
        expect(events.take(3)).to eq(['request', 'response', 'requestfinished'])
      end
    end

    it 'should support redirects' do
      with_test_state do |page:, server:, **|
        events = []
        page.on('request') do |request|
          next if favicon_request?(request)

          events << "#{request.method} #{request.url}"
        end
        page.on('response') do |response|
          next if favicon_request?(response)

          events << "#{response.status} #{response.url}"
        end
        page.on('requestfinished') do |request|
          next if favicon_request?(request)

          events << "DONE #{request.url}"
        end
        page.on('requestfailed') do |request|
          next if favicon_request?(request)

          events << "FAIL #{request.url}"
        end
        server.set_redirect('/foo.html', '/empty.html')
        foo_url = "#{server.prefix}/foo.html"
        response = page.goto(foo_url)
        expect(events).to eq([
          "GET #{foo_url}",
          "302 #{foo_url}",
          "DONE #{foo_url}",
          "GET #{server.empty_page}",
          "200 #{server.empty_page}",
          "DONE #{server.empty_page}",
        ])

        redirect_chain = response.request.redirect_chain
        expect(redirect_chain.length).to eq(1)
        expect(redirect_chain[0].url).to include('/foo.html')
      end
    end
  end

  describe 'Request.isNavigationRequest' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        requests = {}
        page.on('request') do |request|
          requests[request.url.split('/').last] = request
        end
        server.set_redirect('/rrredirect', '/frames/one-frame.html')
        page.goto("#{server.prefix}/rrredirect")
        expect(requests['rrredirect'].navigation_request?).to eq(true)
        expect(requests['one-frame.html'].navigation_request?).to eq(true)
        expect(requests['frame.html'].navigation_request?).to eq(true)
        expect(requests['script.js'].navigation_request?).to eq(false)
        expect(requests['style.css'].navigation_request?).to eq(false)
      end
    end

    it 'should work with request interception' do
      with_test_state do |page:, server:, **|
        requests = {}
        page.on('request') do |request|
          requests[request.url.split('/').last] = request
          request.continue
        end
        page.request_interception = true
        server.set_redirect('/rrredirect', '/frames/one-frame.html')
        page.goto("#{server.prefix}/rrredirect")
        expect(requests['rrredirect'].navigation_request?).to eq(true)
        expect(requests['one-frame.html'].navigation_request?).to eq(true)
        expect(requests['frame.html'].navigation_request?).to eq(true)
        expect(requests['script.js'].navigation_request?).to eq(false)
        expect(requests['style.css'].navigation_request?).to eq(false)
      end
    end

    it 'should work when navigating to image' do
      with_test_state do |page:, server:, **|
        request_promise = async_promise { wait_for_event(page, 'request') }
        page.goto("#{server.prefix}/pptr.png")
        request = request_promise.wait
        expect(request.navigation_request?).to eq(true)
      end
    end
  end

  describe 'Page.setExtraHTTPHeaders' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.extra_http_headers = { 'foo' => 'bar' }
        request_promise = async_promise { server.wait_for_request('/empty.html') }
        page.goto(server.empty_page)
        request = request_promise.wait
        expect(request.headers['foo']).to eq('bar')
      end
    end

    it 'should throw for non-string header values' do
      with_test_state do |page:, **|
        expect {
          page.extra_http_headers = { 'foo' => 1 }
        }.to raise_error('Expected value of header "foo" to be String, but "number" is found.')
      end
    end
  end

  describe 'Page.authenticate' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        server.set_auth('/empty.html', 'user', 'pass')
        page.authenticate(username: 'user', password: 'pass')
        response = page.goto(server.empty_page)
        expect(response.status).to eq(200)
      end
    end

    it 'should work with interception' do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') { |request| request.continue }
        server.set_auth('/empty.html', 'user', 'pass')
        page.authenticate(username: 'user', password: 'pass')
        response = page.goto(server.empty_page)
        expect(response.status).to eq(200)
      end
    end

    it 'should error if authentication is required but not enabled' do
      with_test_state do |page:, server:, **|
        server.set_auth('/empty.html', 'user', 'pass')
        response = nil
        begin
          response = page.goto(server.empty_page)
          expect(response.status).to eq(401)
        rescue StandardError => error
          if !error.message.include?('net::ERR_INVALID_AUTH_CREDENTIALS')
            raise
          end
        end
        page.authenticate(username: 'user', password: 'pass')
        response = page.reload
        expect(response.status).to eq(200)
      end
    end

    it 'should fail if wrong credentials' do
      with_test_state do |page:, server:, **|
        server.set_auth('/empty.html', 'user2', 'pass2')
        page.authenticate(username: 'foo', password: 'bar')
        response = page.goto(server.empty_page)
        expect(response.status).to eq(401)
      end
    end

    it 'should allow disable authentication' do
      with_test_state do |page:, server:, **|
        server.set_auth('/empty.html', 'user3', 'pass3')
        page.authenticate(username: 'user3', password: 'pass3')
        response = page.goto(server.empty_page)
        expect(response.status).to eq(200)
        page.authenticate(username: nil, password: nil)
        begin
          response = page.goto("#{server.cross_process_prefix}/empty.html")
          expect(response.status).to eq(401)
        rescue StandardError => error
          if !error.message.include?('net::ERR_INVALID_AUTH_CREDENTIALS')
            raise
          end
        end
      end
    end

    [
      { html: 'one-style.html', resource: 'one-style.css', type: 'stylesheet' },
      { html: 'one-script.html', resource: 'one-script.js', type: 'script' },
    ].each do |entry|
      it "should not disable caching for #{entry[:type]}" do
        with_test_state do |page:, server:, **|
          user = "user4-#{entry[:type]}"
          pass = "pass4-#{entry[:type]}"
          server.set_auth("/cached/#{entry[:resource]}", user, pass)
          server.set_auth("/cached/#{entry[:html]}", user, pass)
          page.authenticate(username: user, password: pass)

          responses = {}
          page.on('response') do |response|
            responses[response.url.split('/').last] = response
          end

          page.goto("#{server.prefix}/cached/#{entry[:html]}")
          page.reload

          expect(responses[entry[:resource]].status).to eq(200)
          expect(responses[entry[:resource]].from_cache?).to eq(true)
          expect(responses[entry[:html]].status).to eq(304)
          expect(responses[entry[:html]].from_cache?).to eq(false)
        end
      end
    end
  end

  describe 'raw network headers' do
    it 'Same-origin set-cookie navigation' do
      with_test_state do |page:, server:, **|
        set_cookie_string = 'foo=bar'
        server.set_route('/empty.html') do |_req, writer|
          writer.add_header('set-cookie', set_cookie_string)
          writer.write('hello world')
          writer.finish
        end
        response = page.goto(server.empty_page)
        expect(response.headers['set-cookie']).to eq(set_cookie_string)
      end
    end

    it 'Same-origin set-cookie subresource' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        set_cookie_string = 'foo=bar'
        server.set_route('/foo') do |_req, writer|
          writer.add_header('set-cookie', set_cookie_string)
          writer.write('hello world')
          writer.finish
        end

        response_promise = async_promise do
          wait_for_event(page, 'response', predicate: ->(response) { !favicon_request?(response) })
        end
        page.evaluate(<<~JAVASCRIPT)
          () => {
            const xhr = new XMLHttpRequest();
            xhr.open('GET', '/foo');
            xhr.send();
          }
        JAVASCRIPT
        response = response_promise.wait
        expect(response.headers['set-cookie']).to eq(set_cookie_string)
      end
    end

    it 'Cross-origin set-cookie' do
      with_test_state do |page:, https_server:, **|
        page.goto("#{https_server.prefix}/empty.html")

        set_cookie_string = 'hello=world'
        https_server.set_route('/setcookie.html') do |_req, writer|
          writer.add_header('Access-Control-Allow-Origin', '*')
          writer.add_header('set-cookie', set_cookie_string)
          writer.finish
        end
        page.goto("#{https_server.prefix}/setcookie.html")
        url = "#{https_server.cross_process_prefix}/setcookie.html"
        response_promise = async_promise do
          wait_for_event(page, 'response', predicate: ->(response) { response.url == url })
        end
        page.evaluate(<<~JAVASCRIPT, url)
          (src) => {
            const xhr = new XMLHttpRequest();
            xhr.open('GET', src);
            xhr.send();
          }
        JAVASCRIPT
        response = response_promise.wait
        expect(response.headers['set-cookie']).to eq(set_cookie_string)
      end
    end
  end

  describe 'Page.setBypassServiceWorker' do
    it 'bypass for network' do
      with_test_state do |page:, server:, **|
        responses = {}
        page.on('response') do |response|
          next if favicon_request?(response)

          responses[response.url.split('/').last] = response
        end

        page.goto("#{server.prefix}/serviceworkers/fetch/sw.html", wait_until: 'networkidle2')
        page.evaluate('() => globalThis.activationPromise')
        page.reload(wait_until: 'networkidle2')

        expect(page.service_worker_bypassed?).to eq(false)
        expect(responses.size).to eq(2)
        expect(responses['sw.html'].status).to eq(200)
        expect(responses['sw.html'].from_service_worker?).to eq(true)
        expect(responses['style.css'].status).to eq(200)
        expect(responses['style.css'].from_service_worker?).to eq(true)

        page.service_worker_bypassed = true
        page.reload(wait_until: 'networkidle2')

        expect(page.service_worker_bypassed?).to eq(true)
        expect(responses['sw.html'].status).to eq(200)
        expect(responses['sw.html'].from_service_worker?).to eq(false)
        expect(responses['style.css'].status).to eq(200)
        expect(responses['style.css'].from_service_worker?).to eq(false)
      end
    end
  end

  describe 'Request.resourceType' do
    it 'should work for document type' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page)
        request = response.request
        expect(request.resource_type).to eq('document')
      end
    end

    it 'should work for stylesheets' do
      with_test_state do |page:, server:, **|
        css_requests = []
        promise = Async::Promise.new
        page.on('request') do |request|
          if request.url.end_with?('css')
            css_requests << request
            promise.resolve(nil) unless promise.resolved?
          end
        end
        page.goto("#{server.prefix}/one-style.html")
        promise.wait
        expect(css_requests.length).to eq(1)
        request = css_requests[0]
        expect(request.url).to include('one-style.css')
        expect(request.resource_type).to eq('stylesheet')
      end
    end
  end

  describe 'Response.remoteAddress' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page)
        remote_address = response.remote_address
        expect(remote_address.ip.include?('::1') || remote_address.ip == '127.0.0.1').to eq(true)
        expect(remote_address.port).to eq(server.port)
      end
    end

    it 'should support redirects' do
      with_test_state do |page:, server:, **|
        server.set_redirect('/foo.html', '/empty.html')
        foo_url = "#{server.prefix}/foo.html"
        response = page.goto(foo_url)

        redirect_chain = response.request.redirect_chain
        expect(redirect_chain.length).to eq(1)
        expect(redirect_chain[0].url).to include('/foo.html')
        expect(redirect_chain[0].response.remote_address.port).to eq(server.port)
      end
    end
  end
end
