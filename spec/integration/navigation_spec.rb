require 'spec_helper'

RSpec.describe 'navigation' do
  include Utils::AttachFrame
  include Utils::Favicon
  include Utils::WaitEvent

  def with_https_error_state(&block)
    with_browser(ignore_https_errors: false) do |browser|
      with_test_state(browser: browser, &block)
    end
  end

  describe 'Page.goto' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        expect(page.url).to eq(server.empty_page)
      end
    end

    it 'should work with anchor navigation' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        expect(page.url).to eq(server.empty_page)
        page.goto("#{server.empty_page}#foo")
        expect(page.url).to eq("#{server.empty_page}#foo")
        page.goto("#{server.empty_page}#bar")
        expect(page.url).to eq("#{server.empty_page}#bar")
      end
    end

    it 'should work with redirects' do
      with_test_state do |page:, server:, **|
        server.set_redirect('/redirect/1.html', '/redirect/2.html')
        server.set_redirect('/redirect/2.html', '/empty.html')
        page.goto("#{server.prefix}/redirect/1.html")
        expect(page.url).to eq(server.empty_page)
      end
    end

    it 'should navigate to about:blank' do
      with_test_state do |page:, **|
        response = page.goto('about:blank')
        expect(response).to be_nil
      end
    end

    it 'should return response when page changes its URL after load' do
      with_test_state do |page:, server:, **|
        response = page.goto("#{server.prefix}/historyapi.html")
        expect(response.status).to eq(200)
      end
    end

    it 'should return response when page replaces its state during load' do
      with_test_state do |page:, server:, **|
        response = page.goto(
          "#{server.prefix}/historyapi-replaceState.html",
          wait_until: 'networkidle2',
        )
        expect(response.status).to eq(200)
        expect(page.url).to eq("#{server.prefix}/historyapi-replaceState.html")
      end
    end

    it 'should work with subframes return 204' do
      with_test_state do |page:, server:, **|
        server.set_route('/frames/frame.html') do |_req, writer|
          writer.status = 204
          writer.finish
        end

        error = nil
        begin
          page.goto("#{server.prefix}/frames/one-frame.html")
        rescue StandardError => e
          error = e
        end
        expect(error).to be_nil
      end
    end

    it 'should fail when server returns 204' do
      with_test_state do |page:, server:, **|
        server.set_route('/empty.html') do |_req, writer|
          writer.status = 204
          writer.finish
        end
        error = nil
        begin
          page.goto(server.empty_page)
        rescue StandardError => e
          error = e
        end
        expect(error).not_to be_nil
        if Puppeteer.env.chrome?
          expect(error.message).to include('net::ERR_ABORTED')
        else
          expect(error.message).to include('NS_BINDING_ABORTED')
        end
      end
    end

    it 'should navigate to empty page with domcontentloaded' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page, wait_until: 'domcontentloaded')
        expect(response.status).to eq(200)
      end
    end

    it 'should work when page calls history API in beforeunload' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.evaluate(<<~JAVASCRIPT)
          () => {
            window.addEventListener(
              'beforeunload',
              () => {
                return history.replaceState(null, 'initial', window.location.href);
              },
              false,
            );
          }
        JAVASCRIPT
        response = page.goto("#{server.prefix}/grid.html")
        expect(response.status).to eq(200)
      end
    end

    it 'should work when reload causes history API in beforeunload' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.evaluate(<<~JAVASCRIPT)
          () => {
            window.addEventListener(
              'beforeunload',
              () => {
                return history.replaceState(null, 'initial', window.location.href);
              },
              false,
            );
          }
        JAVASCRIPT
        page.reload
        expect(page.evaluate('() => 1')).to eq(1)
      end
    end

    it 'should navigate to empty page with networkidle0' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page, wait_until: 'networkidle0')
        expect(response.status).to eq(200)
      end
    end

    it 'should navigate to page with iframe and networkidle0' do
      with_test_state do |page:, server:, **|
        response = page.goto("#{server.prefix}/frames/one-frame.html", wait_until: 'networkidle0')
        expect(response.status).to eq(200)
      end
    end

    it 'should navigate to empty page with networkidle2' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page, wait_until: 'networkidle2')
        expect(response.status).to eq(200)
      end
    end

    it 'should fail when navigating to bad url' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.goto('asdfasdf')
        rescue StandardError => e
          error = e
        end

        expect(error.message).to match(/Cannot navigate to invalid URL|invalid argument/)
      end
    end

    expected_ssl_cert_message_regex = %r{
      net::ERR_CERT_INVALID|
      net::ERR_CERT_AUTHORITY_INVALID|
      MOZILLA_PKIX_ERROR_SELF_SIGNED_CERT|
      SSL_ERROR_UNKNOWN
    }x

    it 'should fail when navigating to bad SSL' do
      with_https_error_state do |page:, https_server:, **|
        requests = []
        page.on('request') { requests << 'request' }
        page.on('requestfinished') { requests << 'requestfinished' }
        page.on('requestfailed') { requests << 'requestfailed' }

        error = nil
        begin
          page.goto(https_server.empty_page)
        rescue StandardError => e
          error = e
        end
        expect(error.message).to match(expected_ssl_cert_message_regex)

        expect(requests.length).to eq(2)
        expect(requests[0]).to eq('request')
        expect(requests[1]).to eq('requestfailed')
      end
    end

    it 'should fail when navigating to bad SSL after redirects' do
      with_https_error_state do |page:, https_server:, **|
        https_server.set_redirect('/redirect/1.html', '/redirect/2.html')
        https_server.set_redirect('/redirect/2.html', '/empty.html')
        error = nil
        begin
          page.goto("#{https_server.prefix}/redirect/1.html")
        rescue StandardError => e
          error = e
        end
        expect(error.message).to match(expected_ssl_cert_message_regex)
      end
    end

    it 'should fail when main resources failed to load' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.goto('http://localhost:44123/non-existing-url')
        rescue StandardError => e
          error = e
        end
        expect(error.message).to match(/net::ERR_CONNECTION_REFUSED|NS_ERROR_CONNECTION_REFUSED/)
      end
    end

    it 'should fail when exceeding maximum navigation timeout' do
      with_test_state do |page:, server:, **|
        server.set_route('/empty.html') do |_req, _writer|
        end
        error = nil
        begin
          page.goto("#{server.prefix}/empty.html", timeout: 1)
        rescue StandardError => e
          error = e
        end
        expect(error.message).to include('Navigation timeout of 1 ms exceeded')
        expect(error).to be_a(Puppeteer::TimeoutError)
      end
    end

    it 'should fail when exceeding default maximum navigation timeout' do
      with_test_state do |page:, server:, **|
        server.set_route('/empty.html') do |_req, _writer|
        end
        error = nil
        page.default_navigation_timeout = 1
        begin
          page.goto("#{server.prefix}/empty.html")
        rescue StandardError => e
          error = e
        end
        expect(error.message).to include('Navigation timeout of 1 ms exceeded')
        expect(error).to be_a(Puppeteer::TimeoutError)
      end
    end

    it 'should fail when exceeding default maximum timeout' do
      with_test_state do |page:, server:, **|
        server.set_route('/empty.html') do |_req, _writer|
        end
        error = nil
        page.default_timeout = 1
        begin
          page.goto("#{server.prefix}/empty.html")
        rescue StandardError => e
          error = e
        end
        expect(error.message).to include('Navigation timeout of 1 ms exceeded')
        expect(error).to be_a(Puppeteer::TimeoutError)
      end
    end

    it 'should prioritize default navigation timeout over default timeout' do
      with_test_state do |page:, server:, **|
        server.set_route('/empty.html') do |_req, _writer|
        end
        error = nil
        page.default_timeout = 0
        page.default_navigation_timeout = 1
        begin
          page.goto("#{server.prefix}/empty.html")
        rescue StandardError => e
          error = e
        end
        expect(error.message).to include('Navigation timeout of 1 ms exceeded')
        expect(error).to be_a(Puppeteer::TimeoutError)
      end
    end

    it 'should disable timeout when its set to 0' do
      with_test_state do |page:, server:, **|
        error = nil
        loaded = false
        page.once('load') { loaded = true }
        begin
          page.goto("#{server.prefix}/grid.html", timeout: 0, wait_until: ['load'])
        rescue StandardError => e
          error = e
        end
        expect(error).to be_nil
        expect(loaded).to eq(true)
      end
    end

    it 'should work when navigating to valid url' do
      with_test_state do |page:, server:, **|
        response = page.goto(server.empty_page)
        expect(response.ok?).to eq(true)
      end
    end

    it 'should work when navigating to a URL with a client redirect' do
      with_test_state do |page:, server:, **|
        response = page.goto("#{server.prefix}/client-redirect.html")
        expect(response.ok?).to eq(true)
        expect(response.url).to eq("#{server.prefix}/client-redirect.html")
      end
    end

    it 'should work when a page redirects on DOMContentLoaded' do
      with_test_state do |page:, server:, **|
        response = page.goto("#{server.prefix}/client-redirect-DOMContentLoaded.html")
        expect(response.ok?).to eq(true)
      end
    end

    it 'should work when navigating to data url' do
      with_test_state do |page:, **|
        response = page.goto('data:text/html,hello')
        expect(response.ok?).to eq(true)
      end
    end

    it 'should work when navigating to 404' do
      with_test_state do |page:, server:, **|
        response = page.goto("#{server.prefix}/not-found")
        expect(response.ok?).to eq(false)
        expect(response.status).to eq(404)
      end
    end

    it 'should not throw an error for a 404 response with an empty body' do
      with_test_state do |page:, server:, **|
        server.set_route('/404-error') do |_req, writer|
          writer.status = 404
          writer.finish
        end

        response = page.goto("#{server.prefix}/404-error")
        expect(response.ok?).to eq(false)
        expect(response.status).to eq(404)
      end
    end

    it 'should not throw an error for a 500 response with an empty body' do
      with_test_state do |page:, server:, **|
        server.set_route('/500-error') do |_req, writer|
          writer.status = 500
          writer.finish
        end

        response = page.goto("#{server.prefix}/500-error")
        expect(response.ok?).to eq(false)
        expect(response.status).to eq(500)
      end
    end

    it 'should return last response in redirect chain' do
      with_test_state do |page:, server:, **|
        server.set_redirect('/redirect/1.html', '/redirect/2.html')
        server.set_redirect('/redirect/2.html', '/redirect/3.html')
        server.set_redirect('/redirect/3.html', server.empty_page)
        response = page.goto("#{server.prefix}/redirect/1.html")
        expect(response.ok?).to eq(true)
        expect(response.url).to eq(server.empty_page)
      end
    end

    it 'should wait for network idle to succeed navigation' do
      with_test_state do |page:, server:, **|
        responses = []
        server.set_route('/fetch-request-a.js') do |_req, writer|
          responses << writer
        end
        server.set_route('/fetch-request-b.js') do |_req, writer|
          responses << writer
        end
        server.set_route('/fetch-request-c.js') do |_req, writer|
          responses << writer
        end
        server.set_route('/fetch-request-d.js') do |_req, writer|
          responses << writer
        end

        initial_requests = [
          async_promise { server.wait_for_request('/fetch-request-a.js') },
          async_promise { server.wait_for_request('/fetch-request-b.js') },
          async_promise { server.wait_for_request('/fetch-request-c.js') },
        ]
        second_request = async_promise { server.wait_for_request('/fetch-request-d.js') }

        navigation_finished = false
        navigation_promise = async_promise do
          response = page.goto("#{server.prefix}/networkidle.html", wait_until: 'networkidle0')
          navigation_finished = true
          response
        end

        after_navigation_promise = async_promise do
          wait_for_event(page, 'load')
          expect(navigation_finished).to eq(false)

          await_promises(*initial_requests)
          expect(navigation_finished).to eq(false)

          responses.each do |writer|
            writer.status = 404
            writer.write('File not found')
            writer.finish
          end
          responses.clear

          second_request.wait
          expect(navigation_finished).to eq(false)

          responses.each do |writer|
            writer.status = 404
            writer.write('File not found')
            writer.finish
          end
        end

        navigation_error = nil
        after_navigation_error = nil
        navigation_response = nil
        begin
          navigation_response = navigation_promise.wait
        rescue StandardError => e
          navigation_error = e
        end
        begin
          after_navigation_promise.wait
        rescue StandardError => e
          after_navigation_error = e
        end
        raise navigation_error if navigation_error
        raise after_navigation_error if after_navigation_error

        expect(navigation_finished).to eq(true)
        expect(navigation_response.ok?).to eq(true)
      end
    end

    it 'should not leak listeners during navigation' do
      with_test_state do |page:, server:, **|
        20.times do
          page.goto(server.empty_page)
        end
      end
    end

    it 'should not leak listeners during bad navigation' do
      with_test_state do |page:, **|
        20.times do
          begin
            page.goto('asdf')
          rescue StandardError
          end
        end
      end
    end

    it 'should not leak listeners during navigation of 11 pages' do
      with_test_state do |context:, server:, **|
        20.times do
          new_page = context.new_page
          new_page.goto(server.empty_page)
          new_page.close
        end
      end
    end

    it 'should navigate to dataURL and fire dataURL requests' do
      with_test_state do |page:, **|
        requests = []
        page.on('request') do |request|
          requests << request unless favicon_request?(request)
        end
        data_url = 'data:text/html,<div>yo</div>'
        response = page.goto(data_url)
        expect(response.status).to eq(200)
        expect(requests.length).to eq(1)
        expect(requests[0].url).to eq(data_url)
      end
    end

    it 'should navigate to URL with hash and fire requests without hash' do
      with_test_state do |page:, server:, **|
        requests = []
        page.on('request') do |request|
          requests << request unless favicon_request?(request)
        end
        response = page.goto("#{server.empty_page}#hash")
        expect(response.status).to eq(200)
        expect(response.url).to eq("#{server.empty_page}#hash")
        expect(requests.length).to eq(1)
        expect(requests[0].url).to eq("#{server.empty_page}#hash")
      end
    end

    it 'should work with self requesting page' do
      with_test_state do |page:, server:, **|
        response = page.goto("#{server.prefix}/self-request.html")
        expect(response.status).to eq(200)
        expect(response.url).to include('self-request.html')
      end
    end

    it 'should fail when navigating and show the url at the error message' do
      with_https_error_state do |page:, https_server:, **|
        url = "#{https_server.prefix}/redirect/1.html"
        error = nil
        begin
          page.goto(url)
        rescue StandardError => e
          error = e
        end
        expect(error.message).to include(url)
      end
    end

    it 'should send referer' do
      with_test_state do |page:, server:, **|
        request1_promise = async_promise { server.wait_for_request('/grid.html') }
        request2_promise = async_promise { server.wait_for_request('/digits/1.png') }
        page.goto("#{server.prefix}/grid.html", referer: 'http://google.com/')
        request1, request2 = await_promises(request1_promise, request2_promise)
        expect(request1.headers['referer']).to eq('http://google.com/')
        expect(request2.headers['referer']).to eq("#{server.prefix}/grid.html")
      end
    end

    it 'should send referer policy' do
      with_test_state do |page:, server:, **|
        request_promise = async_promise { server.wait_for_request('/empty.html') }
        page.goto("#{server.prefix}/empty.html", referrer_policy: 'origin')
        request1 = request_promise.wait
        expect(request1.headers['referer']).to be_nil
      end
    end
  end

  describe 'Page.waitForNavigation' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        response = page.wait_for_navigation do
          page.evaluate('(url) => { window.location.href = url; }', "#{server.prefix}/grid.html")
        end
        expect(response.ok?).to eq(true)
        expect(response.url).to include('grid.html')
      end
    end

    it 'should work with both domcontentloaded and load' do
      with_test_state do |page:, server:, **|
        response_writer = nil
        server.set_route('/one-style.css') do |_req, writer|
          response_writer = writer
        end

        error = nil
        both_fired = false
        navigation_promise = async_promise do
          page.goto("#{server.prefix}/one-style.html")
        end
        dom_content_loaded_promise = async_promise do
          page.wait_for_navigation(wait_until: 'domcontentloaded')
        end
        load_fired_promise = async_promise do
          page.wait_for_navigation(wait_until: 'load')
          both_fired = true
        end

        server.wait_for_request('/one-style.css')
        dom_content_loaded_promise.wait
        expect(both_fired).to eq(false)
        response_writer.finish
        load_fired_promise.wait
        navigation_promise.wait
        expect(error).to be_nil
      end
    end

    it 'should work with clicking on anchor links' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content('<a href="#foobar">foobar</a>')
        response = page.wait_for_navigation do
          page.click('a')
        end
        expect(response).to be_nil
        expect(page.url).to eq("#{server.empty_page}#foobar")
      end
    end

    it 'should work with history.pushState()' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content(<<~HTML)
          <a onclick="javascript:pushState()">SPA</a>
          <script>
            function pushState() {
              history.pushState({}, '', 'wow.html');
            }
          </script>
        HTML
        response = page.wait_for_navigation do
          page.click('a')
        end
        expect(response).to be_nil
        expect(page.url).to eq("#{server.prefix}/wow.html")
      end
    end

    it 'should work with history.replaceState()' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content(<<~HTML)
          <a onclick="javascript:replaceState()">SPA</a>
          <script>
            function replaceState() {
              history.replaceState({}, '', '/replaced.html');
            }
          </script>
        HTML
        response = page.wait_for_navigation do
          page.click('a')
        end
        expect(response).to be_nil
        expect(page.url).to eq("#{server.prefix}/replaced.html")
      end
    end

    it 'should work with DOM history.back()/history.forward()' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.set_content(<<~HTML)
          <a id="back" onclick="javascript:goBack()">back</a>
          <a id="forward" onclick="javascript:goForward()">forward</a>
          <script>
            function goBack() {
              history.back();
            }
            function goForward() {
              history.forward();
            }
            history.pushState({}, '', '/first.html');
            history.pushState({}, '', '/second.html');
          </script>
        HTML
        expect(page.url).to eq("#{server.prefix}/second.html")
        back_response = page.wait_for_navigation do
          page.click('a#back')
        end
        expect(back_response).to be_nil
        expect(page.url).to eq("#{server.prefix}/first.html")
        forward_response = page.wait_for_navigation do
          page.click('a#forward')
        end
        expect(forward_response).to be_nil
        expect(page.url).to eq("#{server.prefix}/second.html")
      end
    end

    it 'should work when subframe issues window.stop()' do
      with_test_state do |page:, server:, **|
        server.set_route('/frames/style.css') do |_req, _writer|
        end
        frame_promise = async_promise do
          wait_for_event(page, 'frameattached')
        end
        navigation_promise = async_promise do
          page.goto("#{server.prefix}/frames/one-frame.html")
        end

        frame = frame_promise.wait
        frame.evaluate('() => window.stop()')
        navigation_promise.wait
      end
    end

    it 'should be cancellable' do
      skip('AbortSignal is not supported in puppeteer-ruby.')
    end
  end

  describe 'Page.goBack' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.goto("#{server.prefix}/grid.html")

        response = page.go_back
        expect(response.ok?).to eq(true)
        expect(response.url).to include(server.empty_page)

        response = page.go_forward
        expect(response.ok?).to eq(true)
        expect(response.url).to include('/grid.html')
      end
    end

    it 'should error if no history is found' do
      with_test_state do |page:, **|
        expect { page.go_back }.to raise_error(/History entry to navigate to not found|no such history entry/)
      end
    end

    it 'should work with HistoryAPI' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.evaluate(<<~JAVASCRIPT)
          () => {
            history.pushState({}, '', '/first.html');
            history.pushState({}, '', '/second.html');
          }
        JAVASCRIPT
        expect(page.url).to eq("#{server.prefix}/second.html")

        response = page.go_back
        expect(response).to be_nil
        expect(page.url).to eq("#{server.prefix}/first.html")
        page.go_back
        expect(page.url).to eq(server.empty_page)
        response = page.go_forward
        expect(response).to be_nil
        expect(page.url).to eq("#{server.prefix}/first.html")
      end
    end
  end

  describe 'Frame.goto' do
    it 'should navigate subframes' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/frames/one-frame.html")
        expect(page.frames[0].url).to include('/frames/one-frame.html')
        expect(page.frames[1].url).to include('/frames/frame.html')

        response = page.frames[1].goto(server.empty_page)
        expect(response.ok?).to eq(true)
        expect(response.frame).to eq(page.frames[1])
      end
    end

    it 'should reject when frame detaches' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/frames/one-frame.html")
        frame = page.frames[1]

        server.set_route('/empty.html') do |_req, _writer|
        end
        navigation_promise = async_promise do
          begin
            frame.goto(server.empty_page)
          rescue StandardError => e
            e
          end
        end
        server.wait_for_request('/empty.html')

        page.eval_on_selector('iframe', 'frame => frame.remove()')
        error = navigation_promise.wait
        expect(error.message).to match(/Navigating frame was detached|Frame detached|Error: NS_BINDING_ABORTED|net::ERR_ABORTED/)
      end
    end

    it 'should return matching responses' do
      with_test_state do |page:, server:, **|
        page.cache_enabled = false
        page.goto(server.empty_page)
        frames = [
          attach_frame(page, 'frame1', server.empty_page),
          attach_frame(page, 'frame2', server.empty_page),
          attach_frame(page, 'frame3', server.empty_page),
        ]

        server_responses = []
        server.set_route('/one-style.html') do |_req, writer|
          server_responses << writer
        end
        navigations = []
        3.times do |i|
          navigations << async_promise { frames[i].goto("#{server.prefix}/one-style.html") }
          server.wait_for_request('/one-style.html')
        end

        response_texts = ['AAA', 'BBB', 'CCC']
        [1, 2, 0].each do |index|
          writer = server_responses[index]
          writer.write(response_texts[index])
          writer.finish
          response = navigations[index].wait
          expect(response.frame).to eq(frames[index])
          expect(response.text).to eq(response_texts[index])
        end
      end
    end
  end

  describe 'Frame.waitForNavigation' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/frames/one-frame.html")
        frame = page.frames[1]
        response = frame.wait_for_navigation do
          frame.evaluate('(url) => { window.location.href = url; }', "#{server.prefix}/grid.html")
        end
        expect(response.ok?).to eq(true)
        expect(response.url).to include('grid.html')
        expect(response.frame).to eq(frame)
        expect(page.url).to include('/frames/one-frame.html')
      end
    end

    it 'should fail when frame detaches' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/frames/one-frame.html")
        frame = page.frames[1]

        server.set_route('/empty.html') do |_req, _writer|
        end
        navigation_promise = async_promise do
          begin
            frame.wait_for_navigation
          rescue StandardError => e
            e
          end
        end

        await_promises(
          async_promise { server.wait_for_request('/empty.html') },
          async_promise do
            frame.evaluate("() => { window.location = '/empty.html'; }")
          end,
        )
        page.eval_on_selector('iframe', 'frame => frame.remove()')

        error = navigation_promise.wait
        expect(error.message).to match(/Navigating frame was detached|Frame detached/)
      end
    end
  end

  describe 'Page.reload' do
    it 'should work' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.evaluate('() => { globalThis._foo = 10; }')
        page.reload
        expect(page.evaluate('() => globalThis._foo')).to be_nil
      end
    end
  end
end

RSpec.describe 'with network events disabled' do
  it 'should work' do
    with_browser(network_enabled: false) do |browser|
      with_test_state(browser: browser) do |page:, server:, **|
        response = page.goto(server.empty_page)
        expect(response).to be_nil
        expect(page.url).to eq(server.empty_page)
        expect(page.evaluate('() => window.location.href')).to eq(server.empty_page)
      end
    end
  end
end
