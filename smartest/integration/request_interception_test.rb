require 'test_helper'

describe 'request interception' do
  def skip_favicon?(request)
    request.url.include?('favicon.ico')
  end

  def path_to_file_url(path)
    path_name = path.tr('\\', '/')
    path_name = "/#{path_name}" unless path_name.start_with?('/')
    "file://#{path_name}"
  end

  describe 'Page.setRequestInterception' do
    it 'should intercept', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        request_error = nil
        page.on('request') do |request|
          if skip_favicon?(request)
            request.continue
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
            request.continue
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
          request.continue
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

    it 'should work with keep alive redirects', sinatra: true do
      with_test_state do |page:, server:, **|
        server.set_route('/rredirect') do |_request, writer|
          writer.status = 302
          writer.add_header('location', '/target')
          writer.finish
        end
        server.set_route('/target') do |_request, writer|
          writer.write('Hello World')
          writer.finish
        end
        page.goto(server.empty_page)
        page.on('request') do |request|
          request.continue
        end
        page.request_interception = true
        redirect_request_promise = async_promise do
          page.wait_for_request(predicate: ->(request) { request.url.end_with?('/rredirect') }, timeout: 1000)
        end
        target_response_promise = async_promise do
          page.wait_for_response(predicate: ->(response) { response.request.url.end_with?('/target') }, timeout: 1000)
        end
        page.evaluate(<<~JAVASCRIPT, "#{server.prefix}/rredirect")
          async (url) => {
            void fetch(url, {
              method: 'POST',
              body: JSON.stringify({ test: 'test' }),
              mode: 'no-cors',
              keepalive: true,
            }).then(async (res) => {
              console.log(await res.text());
            });
          }
        JAVASCRIPT
        redirect_request_promise.wait
        target_response_promise.wait
      end
    end

    it 'should work when header manipulation headers with redirect', sinatra: true do
      with_test_state do |page:, server:, **|
        server.set_redirect('/rrredirect', '/empty.html')
        page.request_interception = true
        page.on('request') do |request|
          headers = request.headers.merge('foo' => 'bar')
          request.continue(headers: headers)
        end
        server_request, = await_promises(
          async_promise { server.wait_for_request('/empty.html') },
          async_promise { page.goto("#{server.prefix}/rrredirect") },
        )
        expect(server_request.headers['foo']).to eq('bar')
      end
    end

    it 'should be able to remove headers', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          headers = request.headers.merge(
            'foo' => 'bar',
            'origin' => nil,
          )
          request.continue(headers: headers)
        end

        server_request, = await_promises(
          async_promise { server.wait_for_request('/empty.html') },
          async_promise { page.goto("#{server.prefix}/empty.html") },
        )

        expect(server_request.headers['origin']).to be_nil
      end
    end

    it 'should contain referer header', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        requests = []
        page.on('request') do |request|
          requests << request unless skip_favicon?(request)
          request.continue
        end
        page.goto("#{server.prefix}/one-style.html")
        expect(requests[1].url).to include('/one-style.css')
        expect(requests[1].headers['referer']).to include('/one-style.html')
      end
    end

    it 'should not allow mutating request headers', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        requests = []
        page.on('request') do |request|
          requests << request unless skip_favicon?(request)
          headers = request.headers
          headers['test'] = 'test'
          request.continue(headers: request.headers)
        end
        page.goto(server.empty_page)
        expect(requests[0].headers.keys).not_to include('test')
      end
    end

    it 'should work with requests without networkId', sinatra: true do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.request_interception = true

        cdp = page.target.create_cdp_session
        cdp.send_message('DOM.enable')
        urls = []
        page.on('request') do |request|
          request.continue
          next if skip_favicon?(request)

          urls << request.url
        end
        cdp.send_message('CSS.enable')
        expect(urls).to eq([server.empty_page])
      end
    end

    it 'should properly return navigation response when URL has cookies', sinatra: true do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_cookie({ name: 'foo', value: 'bar' })

        page.request_interception = true
        page.on('request') do |request|
          request.continue
        end
        response = page.reload
        expect(response.status).to eq(200)
      end
    end

    it 'should stop intercepting', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.once('request') do |request|
          request.continue
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
            request.continue
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
          request.continue
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
        request = nil
        page.on('request') do |req|
          request = req
          request.continue
        end
        response = page.goto(server.empty_page)
        expect(request.headers['referer']).to eq(server.empty_page)
        expect(response.ok?).to eq(true)
      end
    end

    it 'should be abortable', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          if request.url.end_with?('.css')
            request.abort
          else
            request.continue
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

    it 'should be abortable with custom error codes', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.abort(error_code: 'internetdisconnected')
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
          request.continue
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
          request.abort
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
          request.continue
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
          request.continue
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
            request.abort
          else
            request.continue
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
            request.continue
            next
          end
          if spinner
            request.abort
          else
            request.continue
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
          request.continue
          requests << request unless skip_favicon?(request)
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
          request.continue
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
          request.continue
          requests << request unless skip_favicon?(request)
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
          request.continue
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
          request.continue
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
          request.continue
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
          request.continue
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
            request.continue
          rescue => err
            error = err
          end
        end
        page.goto(server.empty_page)
        expect(error).not_to be_nil
        expect(error.message).to include('Request Interception is not enabled')
      end
    end

    it 'should work with file URLs' do
      with_test_state do |page:, **|
        page.request_interception = true
        urls = []
        page.on('request') do |request|
          urls << request.url.split('/').last
          request.continue
        end
        file_url = path_to_file_url(File.expand_path('../assets/one-style.html', __dir__))
        page.goto(file_url)
        expect(urls.uniq.length).to eq(2)
        expect(urls).to include('one-style.html')
        expect(urls).to include('one-style.css')
      end
    end

    [
      {
        url: '/cached/one-style.html',
        cached_resource_url: '/cached/one-style.css',
        resource_type: 'stylesheet',
      },
      {
        url: '/cached/one-script.html',
        cached_resource_url: '/cached/one-script.js',
        resource_type: 'script',
      },
    ].each do |options|
      it "should not cache #{options[:resource_type]} if cache disabled", sinatra: true do
        with_test_state do |page:, server:, **|
          page.goto("#{server.prefix}#{options[:url]}")

          page.request_interception = true
          page.cache_enabled = false
          page.on('request') do |request|
            request.continue
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
          error = nil
          page.on('request') do |request|
            begin
              request.continue
            rescue => err
              error = err
            end
          end

          cached = []
          page.on('requestservedfromcache') do |request|
            next if skip_favicon?(request)

            cached << request
          end

          page.reload
          expect(error).to be_nil
          expect(cached.length).to eq(1)
          expect(cached[0].url).to eq("#{server.prefix}#{options[:cached_resource_url]}")
        end
      end
    end

    it 'should load fonts if cache enabled', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.cache_enabled = true
        page.on('request') do |request|
          request.continue
        end

        response_promise = async_promise do
          page.wait_for_response(predicate: ->(response) { response.url.end_with?('/one-style.woff') })
        end
        page.goto("#{server.prefix}/cached/one-style-font.html")
        response_promise.wait
      end
    end

    it 'should work with worker', sinatra: true do
      with_test_state do |page:, server:, **|
        worker_promise = Async::Promise.new
        page.once('workercreated') do |worker|
          worker_promise.resolve(worker)
        end
        goto_promise = async_promise do
          page.goto("#{server.prefix}/worker/worker.html")
        end
        worker_promise.wait
        goto_promise.wait

        page.request_interception = true
      end
    end
  end

  describe 'Request.continue' do
    it 'should work', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.continue
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
          request.continue(headers: headers)
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
          request.continue(url: redirect_url)
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
          request.continue(method: 'POST')
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
          request.continue(post_data: '🐶')
        end
        server_request, = await_promises(
          async_promise { server.wait_for_request('/sleep.zzz') },
          async_promise { page.evaluate("() => fetch('/sleep.zzz', { method: 'POST', body: '🐦' })") },
        )
        expect(server_request.post_body).to eq('🐶')
      end
    end

    it 'should amend both post data and method on navigation', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.continue(method: 'POST', post_data: '🐶')
        end
        server_request, = await_promises(
          async_promise { server.wait_for_request('/empty.html') },
          async_promise { page.goto(server.empty_page) },
        )
        expect(server_request.method).to eq('POST')
        expect(server_request.post_body).to eq('🐶')
      end
    end

    it 'should fail if the header value is invalid', sinatra: true do
      with_test_state do |page:, server:, **|
        error = nil
        page.request_interception = true
        page.on('request') do |request|
          begin
            request.continue(headers: { 'X-Invalid-Header' => "a\nb" })
          rescue => err
            error = err
          end
          request.continue
        end
        page.goto("#{server.prefix}/empty.html")
        expect(error.message).to match(/Invalid header|Expected "header"|invalid argument/i)
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
            body: 'Yo, page!'
          )
        end
        response = page.goto(server.empty_page)
        expect(response.status).to eq(201)
        expect(response.headers['foo']).to eq('bar')
        expect(page.evaluate('() => document.body.textContent')).to eq('Yo, page!')
      end
    end

    it 'should work with status code 422', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.respond(
            status: 422,
            body: 'Yo, page!'
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
            request.continue
            next
          end
          request.respond(
            status: 302,
            headers: {
              location: server.empty_page,
            }
          )
        end
        response = page.goto("#{server.prefix}/rrredirect")
        expect(response.request.redirect_chain.length).to eq(1)
        expect(response.request.redirect_chain[0].url).to eq("#{server.prefix}/rrredirect")
        expect(response.url).to eq(server.empty_page)
      end
    end

    it 'should allow mocking multiple headers with same key', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.respond(
            status: 200,
            headers: {
              foo: 'bar',
              arr: ['1', '2'],
              'set-cookie': ['first=1', 'second=2'],
            },
            body: 'Hello 🌐'
          )
        end
        response = page.goto(server.empty_page)
        cookies = page.cookies
        first_cookie = cookies.find { |cookie| cookie['name'] == 'first' }
        second_cookie = cookies.find { |cookie| cookie['name'] == 'second' }

        expect(response.status).to eq(200)
        expect(response.headers['foo']).to eq('bar')
        expect(response.headers['arr']).to eq("1\n2")
        expect(first_cookie['value']).to eq('1')
        expect(second_cookie['value']).to eq('2')
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
            body: 'Yo, page!'
          )
        end
        response = page.goto(server.empty_page)
        expect(response.status).to eq(200)
        expect(response.headers['foo']).to eq('true')
        expect(page.evaluate('() => document.body.textContent')).to eq('Yo, page!')
      end
    end

    it 'should fail if the header value is invalid', sinatra: true do
      with_test_state do |page:, server:, **|
        error = nil
        page.request_interception = true
        page.on('request') do |request|
          begin
            request.respond(headers: { 'X-Invalid-Header' => "a\nb" })
          rescue => err
            error = err
          end
          request.respond(status: 200, body: 'Hello 🌐')
        end
        page.goto("#{server.prefix}/empty.html")
        expect(error.message).to match(/Invalid header|Expected "header"|invalid argument/i)
      end
    end

    it 'should report correct content-length header with string', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.respond(
            status: 200,
            body: 'Correct length 📏?'
          )
        end
        response = page.goto(server.empty_page)
        expect(response.headers['content-length']).to eq('20')
      end
    end

    it 'should report correct content-length header with buffer', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.respond(
            status: 200,
            body: 'Correct length 📏?'.b
          )
        end
        response = page.goto(server.empty_page)
        expect(response.headers['content-length']).to eq('20')
      end
    end

    it 'should report correct encoding from page when content-type is set', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.respond(
            status: 200,
            body: 'Correct length 📏?'.b,
            headers: {
              'Content-Type' => 'text/plain; charset=utf-8',
            }
          )
        end
        page.goto(server.empty_page)

        content = page.evaluate('() => document.documentElement.innerText')
        expect(content).to eq('Correct length 📏?')
      end
    end
  end

  describe 'Request.resourceType' do
    it 'should work for document type', sinatra: true do
      with_test_state do |page:, server:, **|
        page.request_interception = true
        page.on('request') do |request|
          request.continue
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
          request.continue
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
