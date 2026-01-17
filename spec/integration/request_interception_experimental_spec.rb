require 'spec_helper'

RSpec.describe 'cooperative request interception' do
  def skip_favicon?(request)
    request.url.include?('favicon.ico')
  end

  def path_to_file_url(path)
    path_name = path.tr('\\', '/')
    path_name = "/#{path_name}" unless path_name.start_with?('/')
    "file://#{path_name}"
  end

  describe 'Page.setRequestInterception' do
    expected_actions = %w[abort continue respond]
    expected_actions.each do |expected_action|
      it "should cooperatively #{expected_action} by priority", sinatra: true do
        with_test_state do |page:, server:, **|
          action_results = []
          page.request_interception = true
          page.on('request') do |request|
            if request.url.end_with?('.css')
              headers = request.headers.merge('xaction' => 'continue')
              request.continue(headers: headers, priority: expected_action == 'continue' ? 1 : 0)
            else
              request.continue(priority: 0)
            end
          end
          page.on('request') do |request|
            if request.url.end_with?('.css')
              request.respond(headers: { 'xaction' => 'respond' }, priority: expected_action == 'respond' ? 1 : 0)
            else
              request.continue(priority: 0)
            end
          end
          page.on('request') do |request|
            if request.url.end_with?('.css')
              request.abort(error_code: 'aborted', priority: expected_action == 'abort' ? 1 : 0)
            else
              request.continue(priority: 0)
            end
          end
          page.on('response') do |response|
            xaction = response.headers['xaction']
            if response.url.end_with?('.css') && xaction
              action_results << xaction
            end
          end
          page.on('requestfailed') do |request|
            action_results << 'abort' if request.url.end_with?('.css')
          end

          response =
            if expected_action == 'continue'
              server_request, response = await_promises(
                async_promise { server.wait_for_request('/one-style.css') },
                async_promise { page.goto("#{server.prefix}/one-style.html") },
              )
              action_results << server_request.headers['xaction']
              response
            else
              page.goto("#{server.prefix}/one-style.html")
            end

          expect(action_results.length).to eq(1)
          expect(action_results[0]).to eq(expected_action)
          expect(response.ok?).to eq(true)
        end
      end
    end

    it 'should intercept', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        request_error = nil
        page.on('request') do |request|
          if skip_favicon?(request)
            request.continue(priority: 0)
            next
          end
          begin
            expect(request).not_to be_nil
            expect(request.url).to include('empty.html')
            expect(request.headers['user-agent']).not_to be_nil
            expect(request.method).to eq('GET')
            expect(request.navigation_request?).to eq(true)
            expect(request.frame == page.main_frame).to eq(true)
            expect(request.frame.url).to eq('about:blank')
          rescue => error
            request_error = error
          ensure
            request.continue(priority: 0)
          end
        end

        response = page.goto(server.empty_page)
        raise request_error if request_error
        expect(response.ok?).to eq(true)
      end
    end

    it 'should work when POST is redirected with 302', sinatra: true do
      with_test_state do |page:, server:, **|
        server.set_redirect('/rredirect', '/empty.html')
        page.goto(server.empty_page)
        page.request_interception = true
        page.on('request') do |request|
          request.continue(priority: 0)
        end
        page.set_content(<<~HTML)
          <form
            action="/rredirect"
            method="post"
          >
            <input
              type="hidden"
              id="foo"
              name="foo"
              value="FOOBAR"
            />
          </form>
        HTML

        navigation_promise = async_promise { page.wait_for_navigation }
        await_with_trigger(navigation_promise) do
          page.eval_on_selector('form', 'form => form.submit()')
        end
      end
    end

    it 'should work when header manipulation headers with redirect', sinatra: true do
      with_test_state do |page:, server:, **|
        server.set_redirect('/rrredirect', '/empty.html')
        page.request_interception = true
        request_error = nil
        page.on('request') do |request|
          headers = request.headers.merge('foo' => 'bar')
          request.continue(headers: headers, priority: 0)
          begin
            expect(request.continue_request_overrides).to eq({ headers: headers })
          rescue => error
            request_error = error
          end
        end

        page.goto("#{server.prefix}/rrredirect")
        raise request_error if request_error
      end
    end

    it 'should be able to remove headers', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          headers = request.headers.merge(
            'foo' => 'bar',
            'accept' => nil,
          )
          request.continue(headers: headers, priority: 0)
        end

        server_request, = await_promises(
          async_promise { server.wait_for_request('/empty.html') },
          async_promise { page.goto("#{server.prefix}/empty.html") },
        )

        expect(server_request.headers['accept']).to be_nil
      end
    end

    it 'should contain referer header', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        requests = []
        page.on('request') do |request|
          request.continue(priority: 0)
          requests << request unless skip_favicon?(request)
        end
        page.goto("#{server.prefix}/one-style.html")
        expect(requests[1].url).to include('/one-style.css')
        expect(requests[1].headers['referer']).to include('/one-style.html')
      end
    end

    it 'should properly return navigation response when URL has cookies', sinatra: true do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_cookie({ name: 'foo', value: 'bar' })

        page.request_interception = true
        page.on('request') do |request|
          request.continue(priority: 0)
        end
        response = page.reload
        expect(response.status).to eq(200)
      end
    end

    it 'should stop intercepting', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.once('request') do |request|
          request.continue(priority: 0)
        end
        page.goto(server.empty_page)
        page.request_interception = false
        page.goto(server.empty_page)
      end
    end

    it 'should show custom HTTP headers', sinatra: true do
      with_test_state do |page:, server:, **|
        page.extra_http_headers = { 'foo' => 'bar' }
        page.request_interception = true
        request_error = nil
        page.on('request') do |request|
          begin
            expect(request.headers['foo']).to eq('bar')
          rescue => error
            request_error = error
          ensure
            request.continue(priority: 0)
          end
        end
        response = page.goto(server.empty_page)
        raise request_error if request_error
        expect(response.ok?).to eq(true)
      end
    end

    it 'should work with redirect inside sync XHR', sinatra: true do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        server.set_redirect('/logo.png', '/pptr.png')
        page.request_interception = true
        page.on('request') do |request|
          request.continue(priority: 0)
        end
        status = page.evaluate(<<~JAVASCRIPT)
          () => {
            const request = new XMLHttpRequest();
            request.open('GET', '/logo.png', false);
            request.send(null);
            return request.status;
          }
        JAVASCRIPT
        expect(status).to eq(200)
      end
    end

    it 'should work with custom referer headers', sinatra: true do
      with_test_state do |page:, server:, **|
        page.extra_http_headers = { 'referer' => server.empty_page }
        page.request_interception = true
        request_error = nil
        page.on('request') do |request|
          begin
            expect(request.headers['referer']).to eq(server.empty_page)
          rescue => error
            request_error = error
          ensure
            request.continue(priority: 0)
          end
        end
        response = page.goto(server.empty_page)
        raise request_error if request_error
        expect(response.ok?).to eq(true)
      end
    end

    it 'should be abortable', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          if request.url.end_with?('.css')
            request.abort(error_code: 'failed', priority: 0)
          else
            request.continue(priority: 0)
          end
        end
        failed_requests = 0
        page.on('requestfailed') do
          failed_requests += 1
        end
        response = page.goto("#{server.prefix}/one-style.html")
        expect(response.ok?).to eq(true)
        expect(response.request.failure).to be_nil
        expect(failed_requests).to eq(1)
      end
    end

    it 'should be able to access the error reason', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.abort(error_code: 'failed', priority: 0)
        end
        abort_reason = nil
        page.on('request') do |request|
          abort_reason = request.abort_error_reason
          request.continue(priority: 0)
        end
        page.goto(server.empty_page) rescue nil
        expect(abort_reason).to eq('Failed')
      end
    end

    it 'should be abortable with custom error codes', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.abort(error_code: 'internetdisconnected', priority: 0)
        end

        failed_request_promise = Async::Promise.new
        page.once('requestfailed') do |request|
          failed_request_promise.resolve(request)
        end
        page.goto(server.empty_page) rescue nil
        failed_request = failed_request_promise.wait

        expect(failed_request).not_to be_nil
        expect(failed_request.failure[:errorText]).to eq('net::ERR_INTERNET_DISCONNECTED')
      end
    end

    it 'should send referer', sinatra: true do
      with_test_state do |page:, server:, **|
        page.extra_http_headers = { 'referer' => 'http://google.com/' }
        page.request_interception = true
        page.on('request') do |request|
          request.continue(priority: 0)
        end
        server_request, = await_promises(
          async_promise { server.wait_for_request('/grid.html') },
          async_promise { page.goto("#{server.prefix}/grid.html") },
        )
        expect(server_request.headers['referer']).to eq('http://google.com/')
      end
    end

    it 'should fail navigation when aborting main resource', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.abort(error_code: 'failed', priority: 0)
        end
        error = nil
        begin
          page.goto(server.empty_page)
        rescue => err
          error = err
        end
        expect(error).not_to be_nil
        expect(error.message).to include('net::ERR_FAILED')
      end
    end

    it 'should work with redirects', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        requests = []
        page.on('request') do |request|
          request.continue(priority: 0)
          requests << request unless skip_favicon?(request)
        end
        server.set_redirect('/non-existing-page.html', '/non-existing-page-2.html')
        server.set_redirect('/non-existing-page-2.html', '/non-existing-page-3.html')
        server.set_redirect('/non-existing-page-3.html', '/non-existing-page-4.html')
        server.set_redirect('/non-existing-page-4.html', '/empty.html')
        response = page.goto("#{server.prefix}/non-existing-page.html")
        expect(response.status).to eq(200)
        expect(response.url).to include('empty.html')
        expect(requests.length).to eq(5)
        redirect_chain = response.request.redirect_chain
        expect(redirect_chain.length).to eq(4)
        expect(redirect_chain[0].url).to include('/non-existing-page.html')
        expect(redirect_chain[2].url).to include('/non-existing-page-3.html')
        redirect_chain.each_with_index do |request, index|
          expect(request.navigation_request?).to eq(true)
          expect(request.redirect_chain.index(request)).to eq(index)
        end
      end
    end

    it 'should work with redirects for subresources', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        requests = []
        page.on('request') do |request|
          request.continue(priority: 0)
          requests << request unless skip_favicon?(request)
        end
        server.set_redirect('/one-style.css', '/two-style.css')
        server.set_redirect('/two-style.css', '/three-style.css')
        server.set_redirect('/three-style.css', '/four-style.css')
        server.set_route('/four-style.css') do |_request, writer|
          writer.write('body {box-sizing: border-box; }')
          writer.finish
        end

        response = page.goto("#{server.prefix}/one-style.html")
        expect(response.status).to eq(200)
        expect(response.url).to include('one-style.html')
        expect(requests.length).to eq(5)
        redirect_chain = requests[1].redirect_chain
        expect(redirect_chain.length).to eq(3)
        expect(redirect_chain[0].url).to include('/one-style.css')
        expect(redirect_chain[2].url).to include('/three-style.css')
      end
    end

    it 'should be able to abort redirects', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        server.set_redirect('/non-existing.json', '/non-existing-2.json')
        server.set_redirect('/non-existing-2.json', '/simple.html')
        page.on('request') do |request|
          if request.url.include?('non-existing-2')
            request.abort(error_code: 'failed', priority: 0)
          else
            request.continue(priority: 0)
          end
        end
        page.goto(server.empty_page)
        result = page.evaluate(<<~JAVASCRIPT)
          async () => {
            try {
              return await fetch('/non-existing.json');
            } catch (error) {
              return error.message;
            }
          }
        JAVASCRIPT
        expect(result).to include('Failed to fetch')
      end
    end

    it 'should work with equal requests', sinatra: true do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        response_count = 1
        server.set_route('/zzz') do |_request, writer|
          writer.write((response_count * 11).to_s)
          response_count += 1
          writer.finish
        end
        page.request_interception = true

        spinner = false
        page.on('request') do |request|
          if skip_favicon?(request)
            request.continue(priority: 0)
            next
          end
          if spinner
            request.abort(error_code: 'failed', priority: 0)
          else
            request.continue(priority: 0)
          end
          spinner = !spinner
        end
        results = page.evaluate(<<~JAVASCRIPT)
          () => {
            return Promise.all([
              fetch('/zzz')
                .then((response) => response.text())
                .catch(() => 'FAILED'),
              fetch('/zzz')
                .then((response) => response.text())
                .catch(() => 'FAILED'),
              fetch('/zzz')
                .then((response) => response.text())
                .catch(() => 'FAILED'),
            ]);
          }
        JAVASCRIPT
        expect(results).to eq(['11', 'FAILED', '22'])
      end
    end

    it 'should navigate to dataURL and fire dataURL requests' do
      with_test_state do |page:, **|
        page.request_interception = true
        requests = []
        page.on('request') do |request|
          requests << request unless skip_favicon?(request)
          request.continue(priority: 0)
        end
        data_url = 'data:text/html,<div>yo</div>'
        response = page.goto(data_url)
        expect(response.status).to eq(200)
        expect(requests.length).to eq(1)
        expect(requests[0].url).to eq(data_url)
      end
    end

    it 'should be able to fetch dataURL and fire dataURL requests', sinatra: true do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.request_interception = true
        requests = []
        page.on('request') do |request|
          request.continue(priority: 0)
          requests << request unless skip_favicon?(request)
        end
        data_url = 'data:text/html,<div>yo</div>'
        text = page.evaluate(<<~JAVASCRIPT, data_url)
          (url) => {
            return fetch(url).then((response) => response.text());
          }
        JAVASCRIPT
        expect(text).to eq('<div>yo</div>')
        expect(requests.length).to eq(1)
        expect(requests[0].url).to eq(data_url)
      end
    end

    it 'should navigate to URL with hash and fire requests without hash', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        requests = []
        page.on('request') do |request|
          requests << request unless skip_favicon?(request)
          request.continue(priority: 0)
        end
        response = page.goto("#{server.empty_page}#hash")
        expect(response.status).to eq(200)
        expect(response.url).to eq("#{server.empty_page}#hash")
        expect(requests.length).to eq(1)
        expect(requests[0].url).to eq("#{server.empty_page}#hash")
      end
    end

    it 'should work with encoded server', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.continue(priority: 0)
        end
        response = page.goto("#{server.prefix}/some nonexisting page")
        expect(response.status).to eq(404)
      end
    end

    it 'should work with badly encoded server', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        server.set_route('/malformed') do |_request, writer|
          writer.finish
        end
        page.on('request') do |request|
          request.continue(priority: 0)
        end
        response = page.goto("#{server.prefix}/malformed?rnd=%911")
        expect(response.status).to eq(200)
      end
    end

    it 'should work with missing stylesheets', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        requests = []
        page.on('request') do |request|
          request.continue(priority: 0)
          requests << request unless skip_favicon?(request)
        end
        response = page.goto("#{server.prefix}/style-404.html")
        expect(response.status).to eq(200)
        expect(requests.length).to eq(2)
        expect(requests[1].response.status).to eq(404)
      end
    end

    it 'should not throw "Invalid Interception Id" if the request was cancelled', sinatra: true do
      with_test_state do |page:, server:, **|
        page.set_content('<iframe></iframe>')
        page.request_interception = true
        request = nil
        request_promise = Async::Promise.new
        page.once('request') do |req|
          request = req
          request_promise.resolve(req)
        end
        page.eval_on_selector('iframe', '(frame, url) => (frame.src = url)', server.empty_page)
        request_promise.wait
        page.eval_on_selector('iframe', 'frame => frame.remove()')
        error = nil
        begin
          request.continue(priority: 0)
        rescue => err
          error = err
        end
        expect(error).to be_nil
      end
    end

    it 'should throw if interception is not enabled', sinatra: true do
      with_test_state do |page:, server:, **|
        error = nil
        page.on('request') do |request|
          begin
            request.continue(priority: 0)
          rescue => err
            error = err
          end
        end
        page.goto(server.empty_page)
        expect(error.message).to include('Request Interception is not enabled')
      end
    end

    it 'should work with file URLs' do
      with_test_state do |page:, **|
        page.request_interception = true
        urls = []
        page.on('request') do |request|
          urls << request.url.split('/').last
          request.continue(priority: 0)
        end
        file_url = path_to_file_url(File.expand_path('../assets/one-style.html', __dir__))
        page.goto(file_url)
        expect(urls.uniq.length).to eq(2)
        expect(urls).to include('one-style.html')
        expect(urls).to include('one-style.css')
      end
    end

    [
      { url: '/cached/one-style.html', resource_type: 'stylesheet' },
      { url: '/cached/one-script.html', resource_type: 'script' },
    ].each do |options|
      it "should not cache #{options[:resource_type]} if cache disabled", sinatra: true do
        with_test_state do |page:, server:, **|
          page.goto("#{server.prefix}#{options[:url]}")

          page.request_interception = true
          page.cache_enabled = false
          page.on('request') do |request|
            request.continue(priority: 0)
          end

          cached = []
          page.on('requestservedfromcache') do |request|
            cached << request
          end

          page.reload
          expect(cached.length).to eq(0)
        end
      end

      it "should cache #{options[:resource_type]} if cache enabled", sinatra: true do
        with_test_state do |page:, server:, **|
          page.goto("#{server.prefix}#{options[:url]}")

          page.request_interception = true
          page.cache_enabled = true
          page.on('request') do |request|
            request.continue(priority: 0)
          end

          cached = []
          page.on('requestservedfromcache') do |request|
            cached << request
          end

          page.reload
          expect(cached.length).to eq(1)
        end
      end
    end

    it 'should load fonts if cache enabled', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.cache_enabled = true
        page.on('request') do |request|
          request.continue(priority: 0)
        end

        response_promise = async_promise do
          page.wait_for_response(predicate: ->(response) { response.url.end_with?('/one-style.woff') })
        end
        page.goto("#{server.prefix}/cached/one-style-font.html")
        response_promise.wait
      end
    end
  end

  describe 'Request.continue' do
    it 'should work', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.continue(priority: 0)
        end
        page.goto(server.empty_page)
      end
    end

    it 'should amend HTTP headers', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          headers = request.headers
          headers['FOO'] = 'bar'
          request.continue(headers: headers, priority: 0)
        end
        page.goto(server.empty_page)
        server_request, = await_promises(
          async_promise { server.wait_for_request('/sleep.zzz') },
          async_promise { page.evaluate('() => fetch(\'/sleep.zzz\')') },
        )
        expect(server_request.headers['foo']).to eq('bar')
      end
    end

    it 'should redirect in a way non-observable to page', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          redirect_url = request.url.include?('/empty.html') ? "#{server.prefix}/consolelog.html" : nil
          request.continue(url: redirect_url, priority: 0)
        end
        console_promise = Async::Promise.new
        page.once('console') do |message|
          console_promise.resolve(message)
        end
        page.goto(server.empty_page)
        console_message = console_promise.wait
        expect(page.url).to eq(server.empty_page)
        expect(console_message.text).to eq('yellow')
      end
    end

    it 'should amend method', sinatra: true do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        page.request_interception = true
        page.on('request') do |request|
          request.continue(method: 'POST', priority: 0)
        end
        server_request, = await_promises(
          async_promise { server.wait_for_request('/sleep.zzz') },
          async_promise { page.evaluate('() => fetch(\'/sleep.zzz\')') },
        )
        expect(server_request.method).to eq('POST')
      end
    end

    it 'should amend post data', sinatra: true do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)

        page.request_interception = true
        page.on('request') do |request|
          request.continue(post_data: 'doggo', priority: 0)
        end
        server_request, = await_promises(
          async_promise { server.wait_for_request('/sleep.zzz') },
          async_promise { page.evaluate("() => fetch('/sleep.zzz', { method: 'POST', body: 'birdy' })") },
        )
        expect(server_request.post_body).to eq('doggo')
      end
    end

    it 'should amend both post data and method on navigation', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.continue(method: 'POST', post_data: 'doggo', priority: 0)
        end
        server_request, = await_promises(
          async_promise { server.wait_for_request('/empty.html') },
          async_promise { page.goto(server.empty_page) },
        )
        expect(server_request.method).to eq('POST')
        expect(server_request.post_body).to eq('doggo')
      end
    end
  end

  describe 'Request.respond' do
    it 'should work', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.respond(
            status: 201,
            headers: {
              foo: 'bar',
            },
            body: 'Yo, page!',
            priority: 0,
          )
        end
        response = page.goto(server.empty_page)
        expect(response.status).to eq(201)
        expect(response.headers['foo']).to eq('bar')
        expect(page.evaluate('() => document.body.textContent')).to eq('Yo, page!')
      end
    end

    it 'should be able to access the response', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.respond(
            status: 200,
            body: 'Yo, page!',
            priority: 0,
          )
        end
        response = nil
        page.on('request') do |request|
          response = request.response_for_request
          request.continue(priority: 0)
        end
        page.goto(server.empty_page)
        expect(response).to eq({ status: 200, body: 'Yo, page!' })
      end
    end

    it 'should work with status code 422', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.respond(
            status: 422,
            body: 'Yo, page!',
            priority: 0,
          )
        end
        response = page.goto(server.empty_page)
        expect(response.status).to eq(422)
        expect(response.status_text).to eq('Unprocessable Entity')
        expect(page.evaluate('() => document.body.textContent')).to eq('Yo, page!')
      end
    end

    it 'should redirect', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          if !request.url.include?('rrredirect')
            request.continue(priority: 0)
            next
          end
          request.respond(
            status: 302,
            headers: {
              location: server.empty_page,
            },
            priority: 0,
          )
        end
        response = page.goto("#{server.prefix}/rrredirect")
        expect(response.request.redirect_chain.length).to eq(1)
        expect(response.request.redirect_chain[0].url).to eq("#{server.prefix}/rrredirect")
        expect(response.url).to eq(server.empty_page)
      end
    end

    it 'should allow mocking binary responses', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          image_buffer = File.binread(File.expand_path('../assets/pptr.png', __dir__))
          request.respond(
            content_type: 'image/png',
            body: image_buffer,
            priority: 0,
          )
        end
        page.evaluate(<<~JAVASCRIPT, server.prefix)
          (prefix) => {
            const img = document.createElement('img');
            img.src = prefix + '/does-not-exist.png';
            document.body.appendChild(img);
            return new Promise((fulfill) => {
              img.onload = fulfill;
            });
          }
        JAVASCRIPT
        img = page.query_selector('img')
        expect(img.screenshot).to match_golden('mock-binary-response.png')
      end
    end

    it 'should stringify intercepted request response headers', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.respond(
            status: 200,
            headers: {
              foo: true,
            },
            body: 'Yo, page!',
            priority: 0,
          )
        end
        response = page.goto(server.empty_page)
        expect(response.status).to eq(200)
        expect(response.headers['foo']).to eq('true')
        expect(page.evaluate('() => document.body.textContent')).to eq('Yo, page!')
      end
    end

    it 'should indicate already-handled if an intercept has been handled', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.continue
        end
        request_error = nil
        page.on('request') do |request|
          begin
            expect(request.intercept_resolution_handled?).to eq(true)
          rescue => error
            request_error = error
          end
        end
        page.on('request') do |request|
          begin
            expect(request.intercept_resolution_state.action).to eq('already-handled')
          rescue => error
            request_error = error
          end
        end
        page.goto(server.empty_page)
        raise request_error if request_error
      end
    end
  end

  describe 'Request.resourceType' do
    it 'should work for document type', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.continue(priority: 0)
        end
        response = page.goto(server.empty_page)
        request = response.request
        expect(request.resource_type).to eq('document')
      end
    end

    it 'should work for stylesheets', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        css_requests = []
        page.on('request') do |request|
          css_requests << request if request.url.end_with?('css')
          request.continue(priority: 0)
        end
        page.goto("#{server.prefix}/one-style.html")
        expect(css_requests.length).to eq(1)
        request = css_requests[0]
        expect(request.url).to include('one-style.css')
        expect(request.resource_type).to eq('stylesheet')
      end
    end
  end
end
