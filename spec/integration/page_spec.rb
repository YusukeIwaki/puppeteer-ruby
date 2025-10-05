require 'spec_helper'

RSpec.describe Puppeteer::Page do
  describe 'goto', sinatra: true do
    before {
      sinatra.get('/hello') do
        <<~HTML
        <html>
          <head>
            <title>Hello World</title>
          </head>
          <body>My Sinatra</body>
        </html>
        HTML
      end
    }

    it "can browser html page" do
      page.goto("#{server_prefix}/hello")
      expect(page.title).to include("Hello World")
      expect(page.evaluate('() => document.body.innerText')).to eq("My Sinatra")
    end
  end

  describe '#close' do
    it 'should reject all promises when page is closed' do
      context = page.browser_context

      new_page = context.new_page
      promise = new_page.async_evaluate("() => new Promise(() => {})")
      new_page.close
      expect { await promise }.to raise_error(/Protocol error/)
    end

    it 'should not be visible in browser.pages', puppeteer: :browser do
      new_page = browser.new_page
      expect(browser.pages).to include(new_page)
      new_page.close
      expect(browser.pages).not_to include(new_page)
    end

    it_fails_firefox 'should run beforeunload if asked for', sinatra: true do
      context = page.browser_context

      new_page = context.new_page
      new_page.goto("#{server_prefix}/beforeunload.html")
      # We have to interact with a page so that 'beforeunload' handlers
      # fire.
      new_page.click('body')
      dialog_promise = Concurrent::Promises.resolvable_future.tap do |future|
        new_page.once('dialog') { |d| future.fulfill(d) }
      end
      new_page.close(run_before_unload: true)
      sleep 0.2
      expect(dialog_promise).to be_fulfilled
      dialog = Puppeteer::ConcurrentRubyUtils.await(dialog_promise)
      expect(dialog.type).to eq("beforeunload")
      expect(dialog.default_value).to eq("")
      if Puppeteer.env.firefox?
        expect(dialog.message).to eq('This page is asking you to confirm that you want to leave - data you have entered may not be saved.')
      else
        expect(dialog.message).to eq("")
      end
      dialog.accept
    end

    it_fails_firefox 'should *not* run beforeunload by default', sinatra: true do
      context = page.browser_context

      new_page = context.new_page
      new_page.goto("#{server_prefix}/beforeunload.html")
      # We have to interact with a page so that 'beforeunload' handlers
      # fire.
      new_page.click('body')
      dialog_promise = Concurrent::Promises.resolvable_future.tap do |future|
        new_page.once('dialog') { |d| future.fulfill(d) }
      end
      new_page.close
      sleep 0.2
      expect(dialog_promise).not_to be_fulfilled
    end

    it 'should set the page close state' do
      context = page.browser_context

      new_page = context.new_page
      expect(new_page).not_to be_closed
      expect { new_page.close }.to change { new_page.closed? }.from(false).to(true)
    end

    it_fails_firefox 'should terminate network waiters', sinatra: true do
      context = page.browser_context

      new_page = context.new_page
      req_promise = new_page.async_wait_for_request(url: server_empty_page)
      res_promise = new_page.async_wait_for_response(url: server_empty_page)
      new_page.close

      expect { Puppeteer::ConcurrentRubyUtils.await(req_promise) }.to raise_error(/Target Closed/)
      expect { Puppeteer::ConcurrentRubyUtils.await(res_promise) }.to raise_error(/Target Closed/)
    end
  end

  describe 'Page.Events.Load' do
    it 'should fire when expected' do
      Timeout.timeout(5) do
        load_promise = Concurrent::Promises.resolvable_future.tap do |future|
          page.once('load') { future.fulfill(nil) }
        end
        Puppeteer::ConcurrentRubyUtils.with_waiting_for_complete(load_promise) do
          page.goto("about:blank")
        end
      end
    end
  end

  describe 'removing and adding event handlers' do
    it 'should correctly fire event handlers as they are added and then removed', pending: 'Page#off is not implemented', sinatra: true do
      handler = double('ResponseHandler')
      allow(handler).to receive(:on_response)

      page.on('response') { handler.on_response }
      page.goto(server_empty_page)
      expect(handler).to have_received(:on_response).once

      page.off('response') { handler.on_response }
      page.goto(server_empty_page)
      # Still one because we removed the handler.
      expect(handler).to have_received(:on_response).once

      page.on('response') { handler.on_response }
      page.goto(server_empty_page)
      # Two now because we added the handler back.
      expect(handler).to have_received(:on_response).twice
    end
  end

  describe 'Page.Events.error' do
    it_fails_firefox 'should throw when page crashes' do
      error_promise = Concurrent::Promises.resolvable_future.tap do |future|
        page.once('error') { |err| future.fulfill(err) }
      end
      Concurrent::Promises.future(&Puppeteer::ConcurrentRubyUtils.future_with_logging { page.goto("chrome://crash") })
      expect(Puppeteer::ConcurrentRubyUtils.await(error_promise).message).to eq("Page crashed!")
    end
  end

  describe 'Page.Events.Popup' do
    it_fails_firefox 'should work' do
      popup_promise = Concurrent::Promises.resolvable_future.tap do |future|
        page.once('popup') { |popup| future.fulfill(popup) }
      end
      page.evaluate("() => { window.open('about:blank') }")
      popup = Puppeteer::ConcurrentRubyUtils.await(popup_promise)

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(true)
    end

    it_fails_firefox 'should work with noopener' do
      popup_promise = Concurrent::Promises.resolvable_future.tap do |future|
        page.once('popup') { |popup| future.fulfill(popup) }
      end
      page.evaluate("() => { window.open('about:blank', null, 'noopener') }")
      popup = Puppeteer::ConcurrentRubyUtils.await(popup_promise)

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(false)
    end

    it_fails_firefox 'should work with clicking target=_blank', sinatra: true do
      page.goto(server_empty_page)
      page.content = '<a target=_blank href="/one-style.html">yo</a>'

      popup_promise = Concurrent::Promises.resolvable_future.tap do |future|
        page.once('popup') { |popup| future.fulfill(popup) }
      end
      page.click("a")
      popup = Puppeteer::ConcurrentRubyUtils.await(popup_promise)

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(false) # was true in Chrome < 88.
    end

    it_fails_firefox 'should work with clicking target=_blank and rel=opener', sinatra: true do
      page.goto(server_empty_page)
      page.content = '<a target=_blank rel=opener href="/one-style.html">yo</a>'

      popup_promise = Concurrent::Promises.resolvable_future.tap do |future|
        page.once('popup') { |popup| future.fulfill(popup) }
      end
      page.click("a")
      popup = Puppeteer::ConcurrentRubyUtils.await(popup_promise)

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(true)
    end

    it_fails_firefox 'should work with fake-clicking target=_blank and rel=noopener', sinatra: true do
      page.goto(server_empty_page)
      page.content = '<a target=_blank rel=noopener href="/one-style.html">yo</a>'

      popup_promise = Concurrent::Promises.resolvable_future.tap do |future|
        page.once('popup') { |popup| future.fulfill(popup) }
      end
      page.eval_on_selector("a", "(a) => a.click()")
      popup = Puppeteer::ConcurrentRubyUtils.await(popup_promise)

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(false)
    end

    it_fails_firefox 'should work with clicking target=_blank and rel=noopener', sinatra: true do
      page.goto(server_empty_page)
      page.content = '<a target=_blank rel=noopener href="/one-style.html">yo</a>'

      popup_promise = Concurrent::Promises.resolvable_future.tap do |future|
        page.once('popup') { |popup| future.fulfill(popup) }
      end
      page.click("a")
      popup = Puppeteer::ConcurrentRubyUtils.await(popup_promise)

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(false)
    end
  end

  describe 'BrowserContext#override_permissions', browser_context: :incognito, sinatra: true do
    def get_permission_for(page, name)
      page.evaluate(
        "(name) => navigator.permissions.query({ name }).then((result) => result.state)",
        name)
    end

    before {
      page.goto(server_empty_page)
    }

    it 'should be prompt by default' do
      expect(get_permission_for(page, "geolocation")).to eq("prompt")
    end

    it_fails_firefox 'should deny permission when not listed' do
      page.browser_context.override_permissions(server_empty_page, [])
      expect(get_permission_for(page, "geolocation")).to eq("denied")
    end

    it 'should fail when bad permission is given' do
      expect { page.browser_context.override_permissions(server_empty_page, ['foo']) }.
        to raise_error(/Unknown permission: foo/)
    end

    it_fails_firefox 'should grant permission when listed' do
      page.browser_context.override_permissions(server_empty_page, ['geolocation'])
      expect(get_permission_for(page, "geolocation")).to eq("granted")
    end

    it_fails_firefox 'should reset permissions' do
      page.browser_context.override_permissions(server_empty_page, ['geolocation'])

      expect {
        page.browser_context.clear_permission_overrides
      }.to change { get_permission_for(page, "geolocation") }.from("granted").to("prompt")
    end

    it_fails_firefox 'should trigger permission onchange' do
      js = <<~JAVASCRIPT
      () => {
        globalThis.events = [];
        return navigator.permissions
          .query({ name: 'geolocation' })
          .then(function (result) {
            globalThis.events.push(result.state);
            result.onchange = function () {
              globalThis.events.push(result.state);
            };
          });
      }
      JAVASCRIPT
      page.evaluate(js)
      expect(page.evaluate("() => globalThis.events")).to eq(%w(prompt))
      page.browser_context.override_permissions(server_empty_page, [])
      expect(page.evaluate("() => globalThis.events")).to eq(%w(prompt denied))
      page.browser_context.override_permissions(server_empty_page, ['geolocation'])
      expect(page.evaluate("() => globalThis.events")).to eq(%w(prompt denied granted))
      page.browser_context.clear_permission_overrides
      expect(page.evaluate("() => globalThis.events")).to eq(%w(prompt denied granted prompt))
    end

    it_fails_firefox 'should isolate permissions between browser contexs' do
      other_context = page.browser.create_incognito_browser_context
      other_page = other_context.new_page
      other_page.goto(server_empty_page)

      expect(get_permission_for(page, 'geolocation')).to eq("prompt")
      expect(get_permission_for(other_page, 'geolocation')).to eq("prompt")

      page.browser_context.override_permissions(server_empty_page, [])
      other_context.override_permissions(server_empty_page, ['geolocation'])

      expect(get_permission_for(page, 'geolocation')).to eq("denied")
      expect(get_permission_for(other_page, 'geolocation')).to eq("granted")

      page.browser_context.clear_permission_overrides

      expect(get_permission_for(page, 'geolocation')).to eq("prompt")
      expect(get_permission_for(other_page, 'geolocation')).to eq("granted")

      other_context.close
    end

    it_fails_firefox 'should grant persistent-storage' do
      expect(get_permission_for(page, 'persistent-storage')).to eq('prompt')
      page.browser_context.override_permissions(server_empty_page, ['persistent-storage'])
      expect(get_permission_for(page, "persistent-storage")).to eq("granted")
    end
  end

  describe '#geolocation=' do
    it_fails_firefox 'should work', browser_context: :incognito, sinatra: true do
      page.browser_context.override_permissions(server_empty_page, ['geolocation'])
      page.goto(server_empty_page)
      page.geolocation = Puppeteer::Geolocation.new(latitude: 10, longitude: 20)

      js = <<~JAVASCRIPT
      () =>
      new Promise((resolve) =>
        navigator.geolocation.getCurrentPosition((position) => {
          resolve({
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
          });
        })
      )
      JAVASCRIPT

      geolocation = page.evaluate(js)
      expect(geolocation).to eq({ "latitude" => 10, "longitude" => 20 })
    end

    it 'should throw when invalid longitude' do
      expect { page.geolocation = Puppeteer::Geolocation.new(latitude: 10, longitude: 200) }.to raise_error(/Invalid longitude "200"/)
    end
  end

  describe '#offline_mode=' do
    it_fails_firefox 'should work', sinatra: true do
      page.offline_mode = true
      expect { page.goto(server_empty_page) }.to raise_error(/net::ERR_INTERNET_DISCONNECTED/)

      page.offline_mode = false
      response = page.reload
      expect(response.status).to eq(200)
    end

    it 'should emulate navigator.onLine' do
      expect(page.evaluate('() => window.navigator.onLine')).to eq(true)
      page.offline_mode = true
      expect(page.evaluate('() => window.navigator.onLine')).to eq(false)
      page.offline_mode = false
      expect(page.evaluate('() => window.navigator.onLine')).to eq(true)
    end
  end

  # describe('ExecutionContext.queryObjects', function () {
  #   itFailsFirefox('should work', async () => {
  #     const { page } = getTestState();

  #     // Instantiate an object
  #     await page.evaluate(() => (globalThis.set = new Set(['hello', 'world'])));
  #     const prototypeHandle = await page.evaluateHandle(() => Set.prototype);
  #     const objectsHandle = await page.queryObjects(prototypeHandle);
  #     const count = await page.evaluate(
  #       (objects: JSHandle[]) => objects.length,
  #       objectsHandle
  #     );
  #     expect(count).toBe(1);
  #     const values = await page.evaluate(
  #       (objects) => Array.from(objects[0].values()),
  #       objectsHandle
  #     );
  #     expect(values).toEqual(['hello', 'world']);
  #   });
  #   itFailsFirefox('should work for non-blank page', async () => {
  #     const { page, server } = getTestState();

  #     // Instantiate an object
  #     await page.goto(server.EMPTY_PAGE);
  #     await page.evaluate(() => (globalThis.set = new Set(['hello', 'world'])));
  #     const prototypeHandle = await page.evaluateHandle(() => Set.prototype);
  #     const objectsHandle = await page.queryObjects(prototypeHandle);
  #     const count = await page.evaluate(
  #       (objects: JSHandle[]) => objects.length,
  #       objectsHandle
  #     );
  #     expect(count).toBe(1);
  #   });
  #   it('should fail for disposed handles', async () => {
  #     const { page } = getTestState();

  #     const prototypeHandle = await page.evaluateHandle(
  #       () => HTMLBodyElement.prototype
  #     );
  #     await prototypeHandle.dispose();
  #     let error = null;
  #     await page
  #       .queryObjects(prototypeHandle)
  #       .catch((error_) => (error = error_));
  #     expect(error.message).toBe('Prototype JSHandle is disposed!');
  #   });
  #   it('should fail primitive values as prototypes', async () => {
  #     const { page } = getTestState();

  #     const prototypeHandle = await page.evaluateHandle(() => 42);
  #     let error = null;
  #     await page
  #       .queryObjects(prototypeHandle)
  #       .catch((error_) => (error = error_));
  #     expect(error.message).toBe(
  #       'Prototype JSHandle must not be referencing primitive value'
  #     );
  #   });
  # });

  # describeFailsFirefox('Page.Events.Console', function () {
  #   it('should work', async () => {
  #     const { page } = getTestState();

  #     let message = null;
  #     page.once('console', (m) => (message = m));
  #     await Promise.all([
  #       page.evaluate(() => console.log('hello', 5, { foo: 'bar' })),
  #       waitEvent(page, 'console'),
  #     ]);
  #     expect(message.text()).toEqual('hello 5 JSHandle@object');
  #     expect(message.type()).toEqual('log');
  #     expect(message.args()).toHaveLength(3);
  #     expect(message.location()).toEqual({
  #       url: expect.any(String),
  #       lineNumber: expect.any(Number),
  #       columnNumber: expect.any(Number),
  #     });

  #     expect(await message.args()[0].jsonValue()).toEqual('hello');
  #     expect(await message.args()[1].jsonValue()).toEqual(5);
  #     expect(await message.args()[2].jsonValue()).toEqual({ foo: 'bar' });
  #   });
  it 'should work for different console API calls' do
    messages = []
    page.on('console') do |m|
      messages << m
    end
    # All console events will be reported before `page.evaluate` is finished.
    page.evaluate(<<~JAVASCRIPT)
    () => {
      // A pair of time/timeEnd generates only one Console API call.
      console.time('calling console.time');
      console.timeEnd('calling console.time');
      console.trace('calling console.trace');
      console.dir('calling console.dir');
      console.warn('calling console.warn');
      console.error('calling console.error');
      console.log(Promise.resolve('should not wait until resolved!'));
    }
    JAVASCRIPT
    expect(messages.map(&:log_type)).to eq(%w[timeEnd trace dir warning error log])
    #     expect(messages[0].text()).toContain('calling console.time');
    #     expect(messages.slice(1).map((msg) => msg.text())).toEqual([
    #       'calling console.trace',
    #       'calling console.dir',
    #       'calling console.warn',
    #       'calling console.error',
    #       'JSHandle@promise',
    #     ]);
    #   });
  end
  #   it('should not fail for window object', async () => {
  #     const { page } = getTestState();

  #     let message = null;
  #     page.once('console', (msg) => (message = msg));
  #     await Promise.all([
  #       page.evaluate(() => console.error(window)),
  #       waitEvent(page, 'console'),
  #     ]);
  #     expect(message.text()).toBe('JSHandle@object');
  #   });
  #   it('should trigger correct Log', async () => {
  #     const { page, server, isChrome } = getTestState();

  #     await page.goto('about:blank');
  #     const [message] = await Promise.all([
  #       waitEvent(page, 'console'),
  #       page.evaluate(
  #         async (url: string) => fetch(url).catch(() => {}),
  #         server.EMPTY_PAGE
  #       ),
  #     ]);
  #     expect(message.text()).toContain('Access-Control-Allow-Origin');
  #     if (isChrome) expect(message.type()).toEqual('error');
  #     else expect(message.type()).toEqual('warn');
  #   });
  #   it('should have location when fetch fails', async () => {
  #     const { page, server } = getTestState();

  #     // The point of this test is to make sure that we report console messages from
  #     // Log domain: https://vanilla.aslushnikov.com/?Log.entryAdded
  #     await page.goto(server.EMPTY_PAGE);
  #     const [message] = await Promise.all([
  #       waitEvent(page, 'console'),
  #       page.setContent(`<script>fetch('http://wat');</script>`),
  #     ]);
  #     expect(message.text()).toContain(`ERR_NAME_NOT_RESOLVED`);
  #     expect(message.type()).toEqual('error');
  #     expect(message.location()).toEqual({
  #       url: 'http://wat/',
  #       lineNumber: undefined,
  #     });
  #   });
  it 'should have location and stack trace for console API calls', sinatra: true do
    page.goto(server_empty_page)

    message = Concurrent::Promises
      .zip(
        Concurrent::Promises.resolvable_future.tap { |future| page.once('console') { |m| future.fulfill(m) } },
        Concurrent::Promises.future(&Puppeteer::ConcurrentRubyUtils.future_with_logging { page.goto("#{server_prefix}/consolelog.html") }),
      ).value!
      .first
    expect(message.log_type).to eq('log')
    #   expect(message.location()).toEqual({
    #     url: server.PREFIX + '/consolelog.html',
    #     lineNumber: 8,
    #     columnNumber: isChrome ? 16 : 8, // console.|log vs |console.log
    #   });
    #   expect(message.stackTrace()).toEqual([
    #     {
    #       url: server.PREFIX + '/consolelog.html',
    #       lineNumber: 8,
    #       columnNumber: isChrome ? 16 : 8, // console.|log vs |console.log
    #     },
    #     {
    #       url: server.PREFIX + '/consolelog.html',
    #       lineNumber: 11,
    #       columnNumber: 8,
    #     },
    #     {
    #       url: server.PREFIX + '/consolelog.html',
    #       lineNumber: 13,
    #       columnNumber: 6,
    #     },
    #   ]);
  end
  #   // @see https://github.com/puppeteer/puppeteer/issues/3865
  #   it('should not throw when there are console messages in detached iframes', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     await page.evaluate(async () => {
  #       // 1. Create a popup that Puppeteer is not connected to.
  #       const win = window.open(
  #         window.location.href,
  #         'Title',
  #         'toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes,width=780,height=200,top=0,left=0'
  #       );
  #       await new Promise((x) => (win.onload = x));
  #       // 2. In this popup, create an iframe that console.logs a message.
  #       win.document.body.innerHTML = `<iframe src='/consolelog.html'></iframe>`;
  #       const frame = win.document.querySelector('iframe');
  #       await new Promise((x) => (frame.onload = x));
  #       // 3. After that, remove the iframe.
  #       frame.remove();
  #     });
  #     const popupTarget = page
  #       .browserContext()
  #       .targets()
  #       .find((target) => target !== page.target());
  #     // 4. Connect to the popup and make sure it doesn't throw.
  #     await popupTarget.page();
  #   });
  # });

  describe 'Page.Events.DOMContentLoaded' do
    it 'should fire when expected' do
      Timeout.timeout(5) do
        promise = Concurrent::Promises.resolvable_future.tap do |future|
          page.once('domcontentloaded') { future.fulfill(nil) }
        end
        page.goto('about:blank')
        Puppeteer::ConcurrentRubyUtils.await(promise)
      end
    end
  end

  describe 'Page#metrics', skip: Puppeteer.env.firefox? do
    def check_metrics(page_metrics)
      aggregate_failures do
        [
          'Timestamp',
          'Documents',
          'Frames',
          'JSEventListeners',
          'Nodes',
          'LayoutCount',
          'RecalcStyleCount',
          'LayoutDuration',
          'RecalcStyleDuration',
          'ScriptDuration',
          'TaskDuration',
          'JSHeapUsedSize',
          'JSHeapTotalSize',
        ].each do |name|
          expect(page_metrics[name]).to be >= 0
        end
      end
    end

    it 'should get metrics from a page' do
      page.goto('about:blank')
      check_metrics(page.metrics)
    end

    it 'metrics event fired on console.timeStamp' do
      metrics_promise = Concurrent::Promises.resolvable_future.tap do |future|
        page.once('metrics') { |event| future.fulfill(event) }
      end

      page.evaluate('() => console.timeStamp("test42")')
      metrics_event = Puppeteer::ConcurrentRubyUtils.await(metrics_promise)
      expect(metrics_event.title).to eq('test42')
      check_metrics(metrics_event.metrics)
    end
  end

  describe 'Page.waitForRequest', sinatra: true do
    it 'should work' do
      page.goto(server_empty_page)
      request = page.wait_for_request(url: "#{server_prefix}/digits/2.png") do
        page.evaluate(<<~JAVASCRIPT)
        () => {
          fetch('/digits/1.png');
          fetch('/digits/2.png');
          fetch('/digits/3.png');
        }
        JAVASCRIPT
      end
      expect(request.url).to eq("#{server_prefix}/digits/2.png")
    end

    it 'should work with predicate' do
      page.goto(server_empty_page)
      predicate = ->(req) { req.url == "#{server_prefix}/digits/2.png" }
      request = page.wait_for_request(predicate: predicate) do
        page.evaluate(<<~JAVASCRIPT)
        () => {
          fetch('/digits/1.png');
          fetch('/digits/2.png');
          fetch('/digits/3.png');
        }
        JAVASCRIPT
      end
      expect(request.url).to eq("#{server_prefix}/digits/2.png")
    end

    it 'should work even if nested' do
      page.goto(server_empty_page)
      promises = [
        page.async_wait_for_request(url: "#{server_prefix}/digits/2.png"),
        page.async_wait_for_request(url: "#{server_prefix}/digits/3.png"),
      ]
      page.evaluate(<<~JAVASCRIPT)
      () => {
        fetch('/digits/1.png');
        fetch('/digits/2.png');
        fetch('/digits/3.png');
      }
      JAVASCRIPT
      requests = Concurrent::Promises.zip(*promises).value!
      expect(requests.map(&:url)).to contain_exactly(
        "#{server_prefix}/digits/2.png",
        "#{server_prefix}/digits/3.png",
      )
    end

    it 'should respect timeout' do
      page.goto(server_empty_page)
      expect { page.wait_for_request(predicate: ->(_) { false }, timeout: 1) }.
        to raise_error(Puppeteer::TimeoutError)
    end

    it 'should respect default timeout' do
      page.goto(server_empty_page)
      page.default_timeout = 1
      expect { page.wait_for_request(predicate: ->(_) { false }) }.
        to raise_error(Puppeteer::TimeoutError)
    end

    it 'should work with no timeout' do
      page.goto(server_empty_page)
      request = page.wait_for_request(url: "#{server_prefix}/digits/2.png", timeout: 0) do
        page.evaluate(<<~JAVASCRIPT)
        () => {
          fetch('/digits/1.png');
          fetch('/digits/2.png');
          fetch('/digits/3.png');
        }
        JAVASCRIPT
      end
      expect(request.url).to eq("#{server_prefix}/digits/2.png")
    end
  end

  # describe('Page.waitForResponse', function () {
  #   it('should work', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const [response] = await Promise.all([
  #       page.waitForResponse(server.PREFIX + '/digits/2.png'),
  #       page.evaluate(() => {
  #         fetch('/digits/1.png');
  #         fetch('/digits/2.png');
  #         fetch('/digits/3.png');
  #       }),
  #     ]);
  #     expect(response.url()).toBe(server.PREFIX + '/digits/2.png');
  #   });
  #   it('should respect timeout', async () => {
  #     const { page, puppeteer } = getTestState();

  #     let error = null;
  #     await page
  #       .waitForResponse(() => false, { timeout: 1 })
  #       .catch((error_) => (error = error_));
  #     expect(error).toBeInstanceOf(puppeteer.errors.TimeoutError);
  #   });
  #   it('should respect default timeout', async () => {
  #     const { page, puppeteer } = getTestState();

  #     let error = null;
  #     page.setDefaultTimeout(1);
  #     await page
  #       .waitForResponse(() => false)
  #       .catch((error_) => (error = error_));
  #     expect(error).toBeInstanceOf(puppeteer.errors.TimeoutError);
  #   });
  #   it('should work with predicate', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const [response] = await Promise.all([
  #       page.waitForResponse(
  #         (response) => response.url() === server.PREFIX + '/digits/2.png'
  #       ),
  #       page.evaluate(() => {
  #         fetch('/digits/1.png');
  #         fetch('/digits/2.png');
  #         fetch('/digits/3.png');
  #       }),
  #     ]);
  #     expect(response.url()).toBe(server.PREFIX + '/digits/2.png');
  #   });
  #   it('should work with no timeout', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const [response] = await Promise.all([
  #       page.waitForResponse(server.PREFIX + '/digits/2.png', { timeout: 0 }),
  #       page.evaluate(() =>
  #         setTimeout(() => {
  #           fetch('/digits/1.png');
  #           fetch('/digits/2.png');
  #           fetch('/digits/3.png');
  #         }, 50)
  #       ),
  #     ]);
  #     expect(response.url()).toBe(server.PREFIX + '/digits/2.png');
  #   });
  # });

  describe 'Page#expose_function', skip: Puppeteer.env.firefox? do
    it 'should work' do
      page.expose_function('compute', ->(a, b) { a * b })
      result = page.evaluate('async function() { return await globalThis.compute(9, 4) }')
      expect(result).to eq(36)
    end

    it 'should throw exception in page context' do
      page.expose_function('woof', -> { raise 'WOOF WOOF' })
      message = page.evaluate(<<~JAVASCRIPT)
      async () => {
        try {
          await globalThis.woof()
          return null
        } catch (error) {
          return error.message
        }
      }
      JAVASCRIPT
      expect(message).to eq('WOOF WOOF')
    end

    it 'should support throwing "null"' do
      skip 'raise nil causes TypeError in Ruby'

      page.expose_function('woof', -> { raise nil })
      thrown = page.evaluate(<<~JAVASCRIPT)
      async () => {
        try {
          await globalThis.woof()
          return "GOOD"
        } catch (error) {
          return error
        }
      }
      JAVASCRIPT
      expect(thrown).to be_nil
    end

    it 'should be callable from-inside evaluateOnNewDocument' do
      called = false
      page.expose_function('woof', -> { called = true })
      page.evaluate_on_new_document('() => globalThis.woof()')
      page.reload
      expect(called).to eq(true)
    end

    it 'should survive navigation', sinatra: true do
      page.expose_function('compute', ->(a, b) { a * b })
      page.goto(server_empty_page)
      result = page.evaluate('async () => { return await globalThis.compute(9, 4) }')
      expect(result).to eq(36)
      page.reload
      result = page.evaluate('async () => { return await globalThis.compute(9, 4) }')
      expect(result).to eq(36)
    end

    it 'should await returned promise' do
      skip "Ruby don't have async function"
    end

    it 'should work on frames', sinatra: true do
      page.expose_function('compute', ->(a, b) { a * b })

      page.goto("#{server_prefix}/frames/nested-frames.html")
      result = page.frames[1].evaluate('async () => { return await globalThis.compute(3, 5) }')
      expect(result).to eq(15)
    end

    it 'should work on frames before navigation', sinatra: true do
      page.goto("#{server_prefix}/frames/nested-frames.html")
      page.expose_function('compute', ->(a, b) { a * b })
      result = page.frames[1].evaluate('async () => { return await globalThis.compute(3, 5) }')
      expect(result).to eq(15)
    end

    it 'should work with complex objects' do
      page.expose_function('complexObject', ->(a, b) {
        { x: a['x'] + b['x'] }
      })

      result = page.evaluate('async () => { return await globalThis.complexObject({x:5}, {x:2}) }')
      expect(result).to eq({ 'x' => 7 })
    end
  end

  describe 'Page.Events.PageError' do
    it 'should fire', sinatra: true do
      Timeout.timeout(5) do
        error_promise = Concurrent::Promises.resolvable_future.tap do |future|
          page.once('pageerror') { |err| future.fulfill(err) }
        end
        page.goto("#{server_prefix}/error.html")
        expect(Puppeteer::ConcurrentRubyUtils.await(error_promise).message).to include("Fancy error!")
      end
    end
  end

  describe '#user_agent=', sinatra: true do
    include Utils::AttachFrame

    it 'should work' do
      expect(page.evaluate('() => navigator.userAgent')).to include('Mozilla')
      page.user_agent = 'foobar'
      async_wait_for_request = Concurrent::Promises.resolvable_future.tap do |future|
        sinatra.get('/_empty.html') do
          future.fulfill(request)
          "EMPTY"
        end
      end
      page.goto("#{server_prefix}/_empty.html")
      request = Puppeteer::ConcurrentRubyUtils.await(async_wait_for_request)
      expect(request.env['HTTP_USER_AGENT']).to eq('foobar')
    end

    it 'should work for subframes' do
      expect(page.evaluate('() => navigator.userAgent')).to include('Mozilla')
      page.goto(server_empty_page)
      page.user_agent = 'foobar'
      async_wait_for_request = Concurrent::Promises.resolvable_future.tap do |future|
        sinatra.get('/empty2.html') do
          future.fulfill(request)
          "EMPTY"
        end
      end
      attach_frame(page, 'frame1', '/empty2.html')
      request = Puppeteer::ConcurrentRubyUtils.await(async_wait_for_request)
      expect(request.env['HTTP_USER_AGENT']).to eq('foobar')
    end

    it 'should emulate device user-agent' do
      page.goto("#{server_prefix}/mobile.html")
      expect(page.evaluate('() => navigator.userAgent')).not_to include('iPhone')
      page.user_agent = Puppeteer::Devices.iPhone_6.user_agent
      expect(page.evaluate('() => navigator.userAgent')).to include('iPhone')
    end

    it_fails_firefox 'should work with additional userAgentMetdata' do
      page.set_user_agent('MockBrowser',
        architecture: 'Mock1',
        mobile: false,
        model: 'Mockbook',
        platform: 'MockOS',
        platformVersion: '3.1',
      )

      async_wait_for_request = Concurrent::Promises.resolvable_future.tap do |future|
        sinatra.get('/_empty.html') do
          future.fulfill(request)
          "EMPTY"
        end
      end
      page.goto("#{server_prefix}/_empty.html")
      request = Puppeteer::ConcurrentRubyUtils.await(async_wait_for_request)
      expect(request.env['HTTP_USER_AGENT']).to eq('MockBrowser')

      expect(page.evaluate('() => navigator.userAgentData.mobile')).to eq(false)
      ua_data = page.evaluate(<<~JAVASCRIPT)
      () => navigator.userAgentData.getHighEntropyValues([
        'architecture',
        'model',
        'platform',
        'platformVersion',
      ])
      JAVASCRIPT
      expect(ua_data['architecture']).to eq('Mock1')
      expect(ua_data['model']).to eq('Mockbook')
      expect(ua_data['platform']).to eq('MockOS')
      expect(ua_data['platformVersion']).to eq('3.1')
    end
  end

  describe '#content=, set_content' do
    it 'should work' do
      page.content = '<div>hello</div>'
      expect(page.content).to eq('<html><head></head><body><div>hello</div></body></html>')
    end

    it 'should work with doctype' do
      page.content = '<!DOCTYPE html><div>hello</div>'
      expect(page.content).to eq('<!DOCTYPE html><html><head></head><body><div>hello</div></body></html>')
    end

    it 'should work with HTML4 doctype' do
      html4doctype = '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">'
      page.content = "#{html4doctype}<div>hello</div>"
      expect(page.content).to eq("#{html4doctype}<html><head></head><body><div>hello</div></body></html>")
    end

    context 'with stall for image page', sinatra: true do
      before {
        sinatra.get('/img.png') { sleep 1000 ; "" }
      }

      it 'should respect timeout' do
        Timeout.timeout(5) do
          expect { page.set_content("<img src=\"#{server_prefix}/img.png\" />", timeout: 1) }.to raise_error(Puppeteer::TimeoutError)
        end
      end

      it 'should respect default navigation timeout' do
        page.default_navigation_timeout = 1
        Timeout.timeout(5) do
          expect { page.content = "<img src=\"#{server_prefix}/img.png\" />" }.to raise_error(Puppeteer::TimeoutError)
        end
      end
    end

    it 'should await resources to load', sinatra: true do
      async_wait_for_request = Concurrent::Promises.resolvable_future.tap do |future|
        sinatra.get('/img2.png') do
          future.fulfill(request)

          sleep 0.3 # emulate image to load
          ""
        end
      end

      content_promise = Concurrent::Promises.future(
        &Puppeteer::ConcurrentRubyUtils.future_with_logging do
          page.content = "<img src=\"#{server_prefix}/img2.png\" />"
        end
      )

      Puppeteer::ConcurrentRubyUtils.await(async_wait_for_request)
      expect(content_promise).not_to be_fulfilled

      sleep 1 # wait for image loaded completely

      expect(content_promise).to be_fulfilled
    end

    it 'should work fast enough' do
      Timeout.timeout(5) do
        25.times { |i| page.content = "<div>yo - #{i}</div>" }
      end
    end

    it 'should work with tricky content' do
      page.content = "<div>hello world</div>\x7F"
      expect(page.eval_on_selector("div", "(div) => div.textContent")).to eq("hello world")
    end

    it 'should work with accents' do
      page.content = '<div>aberración</div>'
      expect(page.eval_on_selector("div", "(div) => div.textContent")).to eq("aberración")
    end

    it 'should work with emojis' do
      page.content = '<div>🐥</div>'
      expect(page.eval_on_selector("div", "(div) => div.textContent")).to eq("🐥")
    end

    it 'should work with newline' do
      page.content = "<div>\n</div>"
      expect(page.eval_on_selector("div", "(div) => div.textContent")).to eq("\n")
    end
  end

  describe '#bypass_csp=', skip: Puppeteer.env.firefox? do
    include Utils::AttachFrame

    it 'should bypass CSP meta tag', sinatra: true do
      # Make sure CSP prohibits addScriptTag.
      page.goto("#{server_prefix}/csp.html")
      page.add_script_tag(content: 'window.__injected = 42;')
      expect(page.evaluate('() => globalThis.__injected')).to be_nil

      # By-pass CSP and try one more time.
      page.bypass_csp = true
      page.reload
      page.add_script_tag(content: 'window.__injected = 42;')
      expect(page.evaluate('() => globalThis.__injected')).to eq(42)
    end

    it 'should bypass CSP header', sinatra: true do
      sinatra.get('/empty_csp.html') do
        headers('Content-Security-Policy' => 'default-src "self"')
        body('EMPTY')
      end

      # Make sure CSP prohibits addScriptTag.
      page.goto("#{server_prefix}/empty_csp.html")
      page.add_script_tag(content: 'window.__injected = 42;')
      expect(page.evaluate('() => globalThis.__injected')).to be_nil

      # By-pass CSP and try one more time.
      page.bypass_csp = true
      page.reload
      page.add_script_tag(content: 'window.__injected = 42;')
      expect(page.evaluate('() => globalThis.__injected')).to eq(42)
    end

    it 'should bypass after cross-process navigation', sinatra: true do
      page.bypass_csp = true
      page.goto("#{server_prefix}/csp.html")
      page.add_script_tag(content: 'window.__injected = 42;')
      expect(page.evaluate('() => globalThis.__injected')).to eq(42)

      page.goto("#{server_cross_process_prefix}/csp.html")
      page.add_script_tag(content: 'window.__injected = 42;')
      expect(page.evaluate('() => globalThis.__injected')).to eq(42)
    end

    it 'should bypass CSP in iframes as well', sinatra: true do
      page.goto(server_empty_page)

      # Make sure CSP prohibits addScriptTag in an iframe.
      frame = attach_frame(page, 'frame1', "#{server_prefix}/csp.html")
      frame.add_script_tag(content: 'window.__injected = 42;')
      expect(frame.evaluate('() => globalThis.__injected')).to be_nil

      # By-pass CSP and try one more time.
      page.bypass_csp = true
      page.reload

      frame = attach_frame(page, 'frame1', "#{server_prefix}/csp.html")
      frame.add_script_tag(content: 'window.__injected = 42;')
      expect(frame.evaluate('() => globalThis.__injected')).to eq(42)
    end
  end

  describe '#add_script_tag' do
    it 'should throw an error if no options are provided' do
      expect { page.add_script_tag }.to raise_error(/Provide an object with a `url`, `path` or `content` property/)
    end

    it 'should work with a url', sinatra: true do
      page.goto(server_empty_page)
      script_handle = page.add_script_tag(url: '/injectedfile.js')
      expect(script_handle.as_element).to be_a(Puppeteer::ElementHandle)
      expect(page.evaluate('() => globalThis.__injected')).to eq(42)
    end

    it 'should work with a url and type=module', sinatra: true do
      page.goto(server_empty_page)
      page.add_script_tag(url: '/es6/es6import.js', type: 'module')
      expect(page.evaluate('() => globalThis.__es6injected')).to eq(42)
    end

    it 'should work with a path and type=module', sinatra: true do
      page.goto(server_empty_page)
      page.add_script_tag(path: 'spec/assets/es6/es6pathimport.js', type: 'module')
      page.wait_for_function('() => window.__es6injected')
      expect(page.evaluate('() => globalThis.__es6injected')).to eq(42)
    end

    it 'should work with a content and type=module', sinatra: true do
      page.goto(server_empty_page)
      page.add_script_tag(
        content: "import num from '/es6/es6module.js';window.__es6injected = num;",
        type: 'module',
      )
      page.wait_for_function('() => window.__es6injected')
      expect(page.evaluate('() => globalThis.__es6injected')).to eq(42)
    end

    it 'should throw an error if loading from url fail', sinatra: true do
      page.goto(server_empty_page)
      expect {
        page.add_script_tag(url: '/nonexistfile.js')
      }.to raise_error(/Loading script from \/nonexistfile.js failed/)
    end

    it 'should work with a path', sinatra: true do
      page.goto(server_empty_page)
      script_handle = page.add_script_tag(path: 'spec/assets/injectedfile.js')
      expect(script_handle.as_element).to be_a(Puppeteer::ElementHandle)
      expect(page.evaluate('() => globalThis.__injected')).to eq(42)
    end

    it 'should include sourcemap when path is provided', sinatra: true do
      page.goto(server_empty_page)
      page.add_script_tag(path: 'spec/assets/injectedfile.js')
      result = page.evaluate('() => globalThis.__injectedError.stack')
      expect(result).to include('spec/assets/injectedfile.js')
    end

    it 'should work with content', sinatra: true do
      page.goto(server_empty_page)
      script_handle = page.add_script_tag(content: 'window.__injected = 35;')
      expect(script_handle.as_element).to be_a(Puppeteer::ElementHandle)
      expect(page.evaluate('() => globalThis.__injected')).to eq(35)
    end

    it 'should add id when provided', sinatra: true do
      page.goto(server_empty_page)
      page.add_script_tag(content: 'window.__injected = 1;', id: 'one')
      page.add_script_tag(url: '/injectedfile.js', id: 'two')
      expect(page.query_selector('#one')).to be_a(Puppeteer::ElementHandle)
      expect(page.query_selector('#two')).to be_a(Puppeteer::ElementHandle)
    end

    #  @see https://github.com/puppeteer/puppeteer/issues/4840
    it 'should throw when added with content to the CSP page', sinatra: true, pending: true do
      page.goto("#{server_prefix}/csp.html")
      expect { page.add_script_tag(content: 'window.__injected = 35;') }.to raise_error
    end

    it 'should throw when added with URL to the CSP page', sinatra: true do
      page.goto("#{server_prefix}/csp.html")
      expect { page.add_script_tag(url: "#{server_cross_process_prefix}/injectedfile.js") }.to raise_error(/Loading script from http.* failed/)
    end
  end

  describe '#add_style_tag' do
    it 'should throw an error if no options are provided' do
      expect { page.add_style_tag }.to raise_error(/Provide an object with a `url`, `path` or `content` property/)
    end

    it 'should work with a url', sinatra: true do
      page.goto(server_empty_page)
      style_handle = page.add_style_tag(url: '/injectedstyle.css')
      expect(style_handle.as_element).to be_a(Puppeteer::ElementHandle)
      bg_color = page.evaluate("window.getComputedStyle(document.querySelector('body')).getPropertyValue('background-color')")
      expect(bg_color).to eq('rgb(255, 0, 0)')
    end

    it 'should throw an error if loading from url fail', sinatra: true do
      page.goto(server_empty_page)
      expect { page.add_style_tag(url: '/nonexistfile.js') }.to raise_error(/Loading style from \/nonexistfile.js failed/)
    end

    it 'should work with a path', sinatra: true do
      page.goto(server_empty_page)
      style_handle = page.add_style_tag(path: 'spec/assets/injectedstyle.css')
      expect(style_handle.as_element).to be_a(Puppeteer::ElementHandle)
      bg_color = page.evaluate("window.getComputedStyle(document.querySelector('body')).getPropertyValue('background-color')")
      expect(bg_color).to eq('rgb(255, 0, 0)')
    end

    it 'should include sourcemap when path is provided', sinatra: true do
      page.goto(server_empty_page)
      style_handle = page.add_style_tag(path: 'spec/assets/injectedstyle.css')
      style_content = style_handle.evaluate('style => style.innerHTML')
      expect(style_content).to include('assets/injectedstyle.css')
    end

    it 'should work with content', sinatra: true do
      page.goto(server_empty_page)
      style_handle = page.add_style_tag(content: 'body { background-color: green; }')
      expect(style_handle).to be_a(Puppeteer::ElementHandle)
      bg_color = page.evaluate("window.getComputedStyle(document.querySelector('body')).getPropertyValue('background-color')")
      expect(bg_color).to eq('rgb(0, 128, 0)')
    end

    it_fails_firefox 'should throw when added with content to the CSP page', sinatra: true do
      page.goto("#{server_prefix}/csp.html")
      expect { page.add_style_tag(content: 'body { background-color: green; }') }.to raise_error
    end

    it 'should throw when added with URL to the CSP page', sinatra: true do
      page.goto("#{server_prefix}/csp.html")
      expect { page.add_style_tag(url: "#{server_cross_process_prefix}/injectedstyle.css") }.to raise_error(/Loading style from http.* failed/)
    end
  end

  describe '#url' do
    it 'should work', sinatra: true do
      expect { page.goto(server_empty_page) }.to change { page.url }.
        from("about:blank").to(server_empty_page)
    end
  end

  describe '#javascript_enabled=' do
    it_fails_firefox 'should work' do
      page.javascript_enabled = false
      page.goto('data:text/html, <script>var something = "forbidden"</script>')
      expect { page.evaluate("something") }.to raise_error(/something is not defined/)

      page.javascript_enabled = true
      page.goto('data:text/html, <script>var something = "forbidden"</script>')
      expect(page.evaluate("something")).to eq("forbidden")
    end
  end

  describe '#cache_enabled', browser_context: :incognito, sinatra: true do
    before {
      sinatra.get("/cached/_one-style.css") {
        "body { background-color: pink; }"
      }
    }

    it 'should enable or disable the cache based on the state passed' do
      request_count = 0
      response_count = 0
      last_modified_timestamp = Time.now.iso8601
      sleep 1

      sinatra.get('/cached/_one-style.html') do
        request_count += 1

        # ref: https://github.com/puppeteer/puppeteer/blob/main/utils/testserver/index.js
        cache_control :public, max_age: 31536000
        last_modified last_modified_timestamp

        response_count += 1
        "<link rel='stylesheet' href='./_one-style.css'><div>hello, world!</div>"
      end

      page.goto("#{server_prefix}/cached/_one-style.html")
      sleep 0.5
      page.reload

      expect(request_count).to eq(2)
      expect(response_count).to eq(1)

      page.cache_enabled = false

      page.reload

      expect(request_count).to eq(3)
      expect(response_count).to eq(2)
    end

    it_fails_firefox 'should stay disabled when toggling request interception on/off' do
      request_count = 0
      response_count = 0
      last_modified_timestamp = Time.now.iso8601
      sleep 1

      sinatra.get('/cached/_one-style2.html') do
        request_count += 1

        # ref: https://github.com/puppeteer/puppeteer/blob/main/utils/testserver/index.js
        cache_control :public, max_age: 31536000
        last_modified last_modified_timestamp

        response_count += 1
        "<link rel='stylesheet' href='./_one-style.css'><div>hello, world!</div>"
      end

      page.goto("#{server_prefix}/cached/_one-style2.html")
      page.reload

      page.cache_enabled = false
      page.request_interception = true
      page.request_interception = false

      page.reload

      expect(request_count).to eq(3)
      expect(response_count).to eq(2)
    end
  end

  describe 'printing to PDF', sinatra: true do
    before {
      skip('Printing to pdf is currently only supported in headless') unless headless?
    }

    it 'can print to PDF and save to file' do
      sinatra.get("/") { "<h1>It Works!</h1>" }
      page.goto("#{server_prefix}/")

      Dir.mktmpdir do |tempdir|
        output_filepath = File.join(tempdir, "output.pdf")
        page.pdf(path: output_filepath)
        expect(File.read(output_filepath).size).to be > 0
      end
    end

    it 'can print to PDF without file' do
      sinatra.get("/") { "<h1>It Works!</h1>" }
      page.goto("#{server_prefix}/")

      data = page.pdf
      expect(data.size).to be > 0
    end

    it 'can print to PDF and stream the result' do
      sinatra.get("/") { "<h1>It Works!</h1>" }
      page.goto("#{server_prefix}/")

      data_length = page.create_pdf_stream.inject(0) do |size, chunk|
        size + chunk.size
      end
      expect(data_length).to be > 0
    end

    it 'should respect timeout' do
      page.goto("#{server_prefix}/pdf.html")

      expect {
        page.pdf(timeout: 1)
      }.to raise_error(Puppeteer::TimeoutError)
    end
  end

  describe '#title' do
    it 'should return the page title', sinatra: true do
      page.goto("#{server_prefix}/title.html")
      expect(page.title).to eq("Woof-Woof")
    end
  end

  # describe('Page.select', function () {
  #   it('should select single option', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/input/select.html');
  #     await page.select('select', 'blue');
  #     expect(await page.evaluate(() => globalThis.result.onInput)).toEqual([
  #       'blue',
  #     ]);
  #     expect(await page.evaluate(() => globalThis.result.onChange)).toEqual([
  #       'blue',
  #     ]);
  #   });
  #   it('should select only first option', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/input/select.html');
  #     await page.select('select', 'blue', 'green', 'red');
  #     expect(await page.evaluate(() => globalThis.result.onInput)).toEqual([
  #       'blue',
  #     ]);
  #     expect(await page.evaluate(() => globalThis.result.onChange)).toEqual([
  #       'blue',
  #     ]);
  #   });
  #   it('should not throw when select causes navigation', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/input/select.html');
  #     await page.$eval('select', (select) =>
  #       select.addEventListener(
  #         'input',
  #         () => ((window as any).location = '/empty.html')
  #       )
  #     );
  #     await Promise.all([
  #       page.select('select', 'blue'),
  #       page.waitForNavigation(),
  #     ]);
  #     expect(page.url()).toContain('empty.html');
  #   });
  #   it('should select multiple options', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/input/select.html');
  #     await page.evaluate(() => globalThis.makeMultiple());
  #     await page.select('select', 'blue', 'green', 'red');
  #     expect(await page.evaluate(() => globalThis.result.onInput)).toEqual([
  #       'blue',
  #       'green',
  #       'red',
  #     ]);
  #     expect(await page.evaluate(() => globalThis.result.onChange)).toEqual([
  #       'blue',
  #       'green',
  #       'red',
  #     ]);
  #   });
  #   it('should respect event bubbling', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/input/select.html');
  #     await page.select('select', 'blue');
  #     expect(
  #       await page.evaluate(() => globalThis.result.onBubblingInput)
  #     ).toEqual(['blue']);
  #     expect(
  #       await page.evaluate(() => globalThis.result.onBubblingChange)
  #     ).toEqual(['blue']);
  #   });
  #   it('should throw when element is not a <select>', async () => {
  #     const { page, server } = getTestState();

  #     let error = null;
  #     await page.goto(server.PREFIX + '/input/select.html');
  #     await page.select('body', '').catch((error_) => (error = error_));
  #     expect(error.message).toContain('Element is not a <select> element.');
  #   });
  #   it('should return [] on no matched values', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/input/select.html');
  #     const result = await page.select('select', '42', 'abc');
  #     expect(result).toEqual([]);
  #   });
  #   it('should return an array of matched values', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/input/select.html');
  #     await page.evaluate(() => globalThis.makeMultiple());
  #     const result = await page.select('select', 'blue', 'black', 'magenta');
  #     expect(
  #       result.reduce(
  #         (accumulator, current) =>
  #           ['blue', 'black', 'magenta'].includes(current) && accumulator,
  #         true
  #       )
  #     ).toEqual(true);
  #   });
  #   it('should return an array of one element when multiple is not set', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/input/select.html');
  #     const result = await page.select(
  #       'select',
  #       '42',
  #       'blue',
  #       'black',
  #       'magenta'
  #     );
  #     expect(result.length).toEqual(1);
  #   });
  it 'should return [] on no values', sinatra: true do
    page.goto("#{server_prefix}/input/select.html")
    result = page.select('select')
    expect(result).to eq([])
  end
  #   it('should deselect all options when passed no values for a multiple select', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/input/select.html');
  #     await page.evaluate(() => globalThis.makeMultiple());
  #     await page.select('select', 'blue', 'black', 'magenta');
  #     await page.select('select');
  #     expect(
  #       await page.$eval('select', (select: HTMLSelectElement) =>
  #         Array.from(select.options).every(
  #           (option: HTMLOptionElement) => !option.selected
  #         )
  #       )
  #     ).toEqual(true);
  #   });
  it 'should deselect all options when passed no values for a select without multiple', sinatra: true do
    page.goto("#{server_prefix}/input/select.html")
    page.select('select', 'blue', 'black', 'magenta')
    page.select('select')
    first_selected = page.eval_on_selector('select', <<~JAVASCRIPT)
    (select) => Array.from(select.options).filter((option) => option.selected)[0].value
    JAVASCRIPT
    expect(first_selected).to eq('')
  end
  #   it('should throw if passed in non-strings', async () => {
  #     const { page } = getTestState();

  #     await page.setContent('<select><option value="12"/></select>');
  #     let error = null;
  #     try {
  #       // @ts-expect-error purposefully passing bad input
  #       await page.select('select', 12);
  #     } catch (error_) {
  #       error = error_;
  #     }
  #     expect(error.message).toContain('Values must be strings');
  #   });
  #   // @see https://github.com/puppeteer/puppeteer/issues/3327
  #   itFailsFirefox(
  #     'should work when re-defining top-level Event class',
  #     async () => {
  #       const { page, server } = getTestState();

  #       await page.goto(server.PREFIX + '/input/select.html');
  #       await page.evaluate(() => (window.Event = null));
  #       await page.select('select', 'blue');
  #       expect(await page.evaluate(() => globalThis.result.onInput)).toEqual([
  #         'blue',
  #       ]);
  #       expect(await page.evaluate(() => globalThis.result.onChange)).toEqual([
  #         'blue',
  #       ]);
  #     }
  #   );
  # });

  describe 'Page.Events.Close' do
    it 'should work with window.close' do
      new_page_promise = Concurrent::Promises.resolvable_future.tap do |future|
        page.browser_context.once('targetcreated') { |target| future.fulfill(target.page) }
      end
      page.evaluate("() => { (window['newPage'] = window.open('about:blank')) }")
      new_page = Puppeteer::ConcurrentRubyUtils.await(new_page_promise)

      closed_promise = Concurrent::Promises.resolvable_future.tap do |future|
        new_page.once('close') { future.fulfill(nil) }
      end
      page.evaluate("() => { window['newPage'].close() }")
      Puppeteer::ConcurrentRubyUtils.await(closed_promise)
    end

    it 'should work with page.close', puppeteer: :browser do
      new_page = browser.new_page
      closed_promise = Concurrent::Promises.resolvable_future.tap do |future|
        new_page.once('close') { future.fulfill(nil) }
      end
      new_page.close
      Puppeteer::ConcurrentRubyUtils.await(closed_promise)
    end
  end

  describe '#browser' do
    it 'should return the correct browser instance' do
      expect(page.browser).to be_a(Puppeteer::Browser)
      expect(page.browser.pages.last).to eq(page)
    end
  end

  describe '#browser_context', browser_context: :incognito do
    it 'should return the correct browser context instance' do
      expect(page.browser_context).to be_a(Puppeteer::BrowserContext)
      expect(page.browser_context.pages.last).to eq(page)
    end
  end
end
