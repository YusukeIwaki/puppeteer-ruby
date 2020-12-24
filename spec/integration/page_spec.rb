require 'spec_helper'

RSpec.describe Puppeteer::Page do
  describe 'goto' do
    sinatra do
      get('/') {
        <<~HTML
        <html>
          <head>
            <title>Hello World</title>
          </head>
          <body>My Sinatra</body>
        </html>
        HTML
      }
    end

    it "can browser html page" do
      page.goto("http://127.0.0.1:4567/")
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

    context 'with beforeunload page' do
      sinatra do
        get('/beforeunload.html') {
          <<~HTML
          <div>beforeunload demo.</div>
          <script>
          window.addEventListener('beforeunload', event => {
            // Chrome way.
            event.returnValue = 'Leave?';
            // Firefox way.
            event.preventDefault();
          });
          </script>
          HTML
        }
      end

      it_fails_firefox 'should run beforeunload if asked for' do
        context = page.browser_context

        new_page = context.new_page
        new_page.goto('http://127.0.0.1:4567/beforeunload.html')
        # We have to interact with a page so that 'beforeunload' handlers
        # fire.
        new_page.click('body')
        dialog_promise = resolvable_future { |f| new_page.once('dialog') { |d| f.fulfill(d) } }
        new_page.close(run_before_unload: true)
        sleep 0.2
        expect(dialog_promise).to be_fulfilled
        dialog = await dialog_promise
        expect(dialog.type).to eq("beforeunload")
        expect(dialog.default_value).to eq("")
        if Puppeteer.env.firefox?
          expect(dialog.message).to eq('This page is asking you to confirm that you want to leave - data you have entered may not be saved.')
        else
          expect(dialog.message).to eq("")
        end
        dialog.accept
      end

      it_fails_firefox 'should *not* run beforeunload by default' do
        context = page.browser_context

        new_page = context.new_page
        new_page.goto('http://127.0.0.1:4567/beforeunload.html')
        # We have to interact with a page so that 'beforeunload' handlers
        # fire.
        new_page.click('body')
        dialog_promise = resolvable_future { |f| new_page.once('dialog') { |d| f.fulfill(d) } }
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
    end

    it_fails_firefox 'should terminate network waiters' do
      context = page.browser_context

      new_page = context.new_page
      req_promise = new_page.async_wait_for_request(url: "http://127.0.0.1:4567/empty")
      res_promise = new_page.async_wait_for_response(url: "http://127.0.0.1:4567/empty")
      new_page.close

      expect { await req_promise }.to raise_error(/Target Closed/)
      expect { await res_promise }.to raise_error(/Target Closed/)
    end
  end

  describe 'Page.Events.Load' do
    it 'should fire when expected' do
      Timeout.timeout(5) do
        await_all(
          future { page.goto("about:blank") },
          resolvable_future { |f| page.once('load') { f.fulfill(nil) } },
        )
      end
    end
  end

  # This test fails on Firefox on CI consistently but cannot be replicated
  # locally. Skipping for now to unblock the Mitt release and given FF support
  # isn't fully done yet but raising an issue to ask the FF folks to have a
  # look at this.
  describe 'removing and adding event handlers' do
    sinatra do
      get ('/') { '' }
    end

    it 'should correctly fire event handlers as they are added and then removed', pending: 'Page#off is not implemented' do
      handler = double('ResponseHandler')
      allow(handler).to receive(:on_response)

      page.on('response') { handler.on_response }
      page.goto('http://127.0.0.1:4567/')
      expect(handler).to have_received(:on_response).once

      page.off('response') { handler.on_response }
      page.goto('http://127.0.0.1:4567/')
      # Still one because we removed the handler.
      expect(handler).to have_received(:on_response).once

      page.on('response') { handler.on_response }
      page.goto('http://127.0.0.1:4567/')
      # Two now because we added the handler back.
      expect(handler).to have_received(:on_response).twice
    end
  end

  describe 'Page.Events.error' do
    it_fails_firefox 'should throw when page crashes' do
      error_promise = resolvable_future { |f| page.once('error') { |err| f.fulfill(err) } }
      future { page.goto("chrome://crash") }
      expect((await error_promise).message).to eq("Page crashed!")
    end
  end

  describe 'Page.Events.Popup' do
    it_fails_firefox 'should work' do
      popup_promise = resolvable_future { |f| page.once('popup') { |popup| f.fulfill(popup) } }
      page.evaluate("() => { window.open('about:blank') }")
      popup = await popup_promise

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(true)
    end

    it_fails_firefox 'should work with noopener' do
      popup_promise = resolvable_future { |f| page.once('popup') { |popup| f.fulfill(popup) } }
      page.evaluate("() => { window.open('about:blank', null, 'noopener') }")
      popup = await popup_promise

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(false)
    end

    context 'with hello page' do
      sinatra do
        get("/") { '<a target=_blank href="/hello.html">yo</a>' }
        get("/hello.html") { "hello" }
      end

      it_fails_firefox 'should work with clicking target=_blank' do
        page.goto('http://127.0.0.1:4567/')

        popup_promise = resolvable_future { |f| page.once('popup') { |popup| f.fulfill(popup) } }
        page.click("a")
        popup = await popup_promise

        expect(page.evaluate("() => !!window.opener")).to eq(false)
        expect(popup.evaluate("() => !!window.opener")).to eq(true)
      end

      it_fails_firefox 'should work with fake-clicking target=_blank and rel=noopener' do
        page.goto('http://127.0.0.1:4567/')
        page.content = '<a target=_blank rel=noopener href="/hello.html">yo</a>'

        popup_promise = resolvable_future { |f| page.once('popup') { |popup| f.fulfill(popup) } }
        page.Seval("a", "(a) => a.click()")
        popup = await popup_promise

        expect(page.evaluate("() => !!window.opener")).to eq(false)
        expect(popup.evaluate("() => !!window.opener")).to eq(false)
      end

      it_fails_firefox 'should work with clicking target=_blank and rel=noopener' do
        page.goto('http://127.0.0.1:4567/')
        page.content = '<a target=_blank rel=noopener href="/hello.html">yo</a>'

        popup_promise = resolvable_future { |f| page.once('popup') { |popup| f.fulfill(popup) } }
        page.click("a")
        popup = await popup_promise

        expect(page.evaluate("() => !!window.opener")).to eq(false)
        expect(popup.evaluate("() => !!window.opener")).to eq(false)
      end
    end
  end

  describe 'BrowserContext#override_permissions', browser_context: :incognito do
    sinatra do
      get("/empty.html") { "" }
    end

    def get_permission_for(page, name)
      page.evaluate(
        "(name) => navigator.permissions.query({ name }).then((result) => result.state)",
        name)
    end

    it 'should be prompt by default' do
      page.goto("http://127.0.0.1:4567/empty.html")
      expect(get_permission_for(page, "geolocation")).to eq("prompt")
    end

    it_fails_firefox 'should deny permission when not listed' do
      page.goto("http://127.0.0.1:4567/empty.html")
      page.browser_context.override_permissions("http://127.0.0.1:4567/", [])
      expect(get_permission_for(page, "geolocation")).to eq("denied")
    end

    it 'should fail when bad permission is given' do
      page.goto("http://127.0.0.1:4567/empty.html")
      expect { page.browser_context.override_permissions("http://127.0.0.1:4567/", ['foo']) }.
        to raise_error(/Unknown permission: foo/)
    end

    it_fails_firefox 'should grant permission when listed' do
      page.goto("http://127.0.0.1:4567/empty.html")
      page.browser_context.override_permissions("http://127.0.0.1:4567/", ['geolocation'])
      expect(get_permission_for(page, "geolocation")).to eq("granted")
    end

    it_fails_firefox 'should reset permissions' do
      page.goto("http://127.0.0.1:4567/empty.html")
      page.browser_context.override_permissions("http://127.0.0.1:4567/", ['geolocation'])

      expect {
        page.browser_context.clear_permission_overrides
      }.to change { get_permission_for(page, "geolocation") }.from("granted").to("prompt")
    end

    it_fails_firefox 'should trigger permission onchange' do
      page.goto("http://127.0.0.1:4567/empty.html")
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
      page.browser_context.override_permissions("http://127.0.0.1:4567/", [])
      expect(page.evaluate("() => globalThis.events")).to eq(%w(prompt denied))
      page.browser_context.override_permissions("http://127.0.0.1:4567/", ['geolocation'])
      expect(page.evaluate("() => globalThis.events")).to eq(%w(prompt denied granted))
      page.browser_context.clear_permission_overrides
      expect(page.evaluate("() => globalThis.events")).to eq(%w(prompt denied granted prompt))
    end

    it_fails_firefox 'should isolate permissions between browser contexs' do
      page.goto("http://127.0.0.1:4567/empty.html")

      other_context = page.browser.create_incognito_browser_context
      other_page = other_context.new_page
      other_page.goto("http://127.0.0.1:4567/empty.html")

      expect(get_permission_for(page, 'geolocation')).to eq("prompt")
      expect(get_permission_for(other_page, 'geolocation')).to eq("prompt")

      page.browser_context.override_permissions("http://127.0.0.1:4567/", [])
      other_context.override_permissions("http://127.0.0.1:4567/", ['geolocation'])

      expect(get_permission_for(page, 'geolocation')).to eq("denied")
      expect(get_permission_for(other_page, 'geolocation')).to eq("granted")

      page.browser_context.clear_permission_overrides

      expect(get_permission_for(page, 'geolocation')).to eq("prompt")
      expect(get_permission_for(other_page, 'geolocation')).to eq("granted")

      other_context.close
    end
  end

  describe '#geolocation=' do
    context 'with empty page' do
      sinatra do
        get('/empty.html') { "" }
      end

      it_fails_firefox 'should work', browser_context: :incognito do
        page.browser_context.override_permissions('http://127.0.0.1:4567/', ['geolocation'])
        page.goto('http://127.0.0.1:4567/empty.html')
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
  end

  describe '#offline_mode=' do
    sinatra do
      get("/empty.html") { "" }
    end

    it_fails_firefox 'should work' do
      page.offline_mode = true
      expect { page.goto('http://127.0.0.1:4567/empty.html') }.to raise_error(/net::ERR_INTERNET_DISCONNECTED/)

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
  #   it('should work for different console API calls', async () => {
  #     const { page } = getTestState();

  #     const messages = [];
  #     page.on('console', (msg) => messages.push(msg));
  #     // All console events will be reported before `page.evaluate` is finished.
  #     await page.evaluate(() => {
  #       // A pair of time/timeEnd generates only one Console API call.
  #       console.time('calling console.time');
  #       console.timeEnd('calling console.time');
  #       console.trace('calling console.trace');
  #       console.dir('calling console.dir');
  #       console.warn('calling console.warn');
  #       console.error('calling console.error');
  #       console.log(Promise.resolve('should not wait until resolved!'));
  #     });
  #     expect(messages.map((msg) => msg.type())).toEqual([
  #       'timeEnd',
  #       'trace',
  #       'dir',
  #       'warning',
  #       'error',
  #       'log',
  #     ]);
  #     expect(messages[0].text()).toContain('calling console.time');
  #     expect(messages.slice(1).map((msg) => msg.text())).toEqual([
  #       'calling console.trace',
  #       'calling console.dir',
  #       'calling console.warn',
  #       'calling console.error',
  #       'JSHandle@promise',
  #     ]);
  #   });
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
  #   it('should have location and stack trace for console API calls', async () => {
  #     const { page, server, isChrome } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const [message] = await Promise.all([
  #       waitEvent(page, 'console'),
  #       page.goto(server.PREFIX + '/consolelog.html'),
  #     ]);
  #     expect(message.text()).toBe('yellow');
  #     expect(message.type()).toBe('log');
  #     expect(message.location()).toEqual({
  #       url: server.PREFIX + '/consolelog.html',
  #       lineNumber: 8,
  #       columnNumber: isChrome ? 16 : 8, // console.|log vs |console.log
  #     });
  #     expect(message.stackTrace()).toEqual([
  #       {
  #         url: server.PREFIX + '/consolelog.html',
  #         lineNumber: 8,
  #         columnNumber: isChrome ? 16 : 8, // console.|log vs |console.log
  #       },
  #       {
  #         url: server.PREFIX + '/consolelog.html',
  #         lineNumber: 11,
  #         columnNumber: 8,
  #       },
  #       {
  #         url: server.PREFIX + '/consolelog.html',
  #         lineNumber: 13,
  #         columnNumber: 6,
  #       },
  #     ]);
  #   });
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
        promise = resolvable_future { |f| page.once('domcontentloaded') { f.fulfill(nil) } }
        page.goto('about:blank')
        await promise
      end
    end
  end

  # describeFailsFirefox('Page.metrics', function () {
  #   it('should get metrics from a page', async () => {
  #     const { page } = getTestState();

  #     await page.goto('about:blank');
  #     const metrics = await page.metrics();
  #     checkMetrics(metrics);
  #   });
  #   it('metrics event fired on console.timeStamp', async () => {
  #     const { page } = getTestState();

  #     const metricsPromise = new Promise<{ metrics: Metrics; title: string }>(
  #       (fulfill) => page.once('metrics', fulfill)
  #     );
  #     await page.evaluate(() => console.timeStamp('test42'));
  #     const metrics = await metricsPromise;
  #     expect(metrics.title).toBe('test42');
  #     checkMetrics(metrics.metrics);
  #   });
  #   function checkMetrics(metrics) {
  #     const metricsToCheck = new Set([
  #       'Timestamp',
  #       'Documents',
  #       'Frames',
  #       'JSEventListeners',
  #       'Nodes',
  #       'LayoutCount',
  #       'RecalcStyleCount',
  #       'LayoutDuration',
  #       'RecalcStyleDuration',
  #       'ScriptDuration',
  #       'TaskDuration',
  #       'JSHeapUsedSize',
  #       'JSHeapTotalSize',
  #     ]);
  #     for (const name in metrics) {
  #       expect(metricsToCheck.has(name)).toBeTruthy();
  #       expect(metrics[name]).toBeGreaterThanOrEqual(0);
  #       metricsToCheck.delete(name);
  #     }
  #     expect(metricsToCheck.size).toBe(0);
  #   }
  # });

  # describe('Page.waitForRequest', function () {
  #   it('should work', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const [request] = await Promise.all([
  #       page.waitForRequest(server.PREFIX + '/digits/2.png'),
  #       page.evaluate(() => {
  #         fetch('/digits/1.png');
  #         fetch('/digits/2.png');
  #         fetch('/digits/3.png');
  #       }),
  #     ]);
  #     expect(request.url()).toBe(server.PREFIX + '/digits/2.png');
  #   });
  #   it('should work with predicate', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const [request] = await Promise.all([
  #       page.waitForRequest(
  #         (request) => request.url() === server.PREFIX + '/digits/2.png'
  #       ),
  #       page.evaluate(() => {
  #         fetch('/digits/1.png');
  #         fetch('/digits/2.png');
  #         fetch('/digits/3.png');
  #       }),
  #     ]);
  #     expect(request.url()).toBe(server.PREFIX + '/digits/2.png');
  #   });
  #   it('should respect timeout', async () => {
  #     const { page, puppeteer } = getTestState();

  #     let error = null;
  #     await page
  #       .waitForRequest(() => false, { timeout: 1 })
  #       .catch((error_) => (error = error_));
  #     expect(error).toBeInstanceOf(puppeteer.errors.TimeoutError);
  #   });
  #   it('should respect default timeout', async () => {
  #     const { page, puppeteer } = getTestState();

  #     let error = null;
  #     page.setDefaultTimeout(1);
  #     await page
  #       .waitForRequest(() => false)
  #       .catch((error_) => (error = error_));
  #     expect(error).toBeInstanceOf(puppeteer.errors.TimeoutError);
  #   });
  #   it('should work with no timeout', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const [request] = await Promise.all([
  #       page.waitForRequest(server.PREFIX + '/digits/2.png', { timeout: 0 }),
  #       page.evaluate(() =>
  #         setTimeout(() => {
  #           fetch('/digits/1.png');
  #           fetch('/digits/2.png');
  #           fetch('/digits/3.png');
  #         }, 50)
  #       ),
  #     ]);
  #     expect(request.url()).toBe(server.PREFIX + '/digits/2.png');
  #   });
  # });

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

  # describeFailsFirefox('Page.exposeFunction', function () {
  #   it('should work', async () => {
  #     const { page } = getTestState();

  #     await page.exposeFunction('compute', function (a, b) {
  #       return a * b;
  #     });
  #     const result = await page.evaluate(async function () {
  #       return await globalThis.compute(9, 4);
  #     });
  #     expect(result).toBe(36);
  #   });
  #   it('should throw exception in page context', async () => {
  #     const { page } = getTestState();

  #     await page.exposeFunction('woof', function () {
  #       throw new Error('WOOF WOOF');
  #     });
  #     const { message, stack } = await page.evaluate(async () => {
  #       try {
  #         await globalThis.woof();
  #       } catch (error) {
  #         return { message: error.message, stack: error.stack };
  #       }
  #     });
  #     expect(message).toBe('WOOF WOOF');
  #     expect(stack).toContain(__filename);
  #   });
  #   it('should support throwing "null"', async () => {
  #     const { page } = getTestState();

  #     await page.exposeFunction('woof', function () {
  #       throw null;
  #     });
  #     const thrown = await page.evaluate(async () => {
  #       try {
  #         await globalThis.woof();
  #       } catch (error) {
  #         return error;
  #       }
  #     });
  #     expect(thrown).toBe(null);
  #   });
  #   it('should be callable from-inside evaluateOnNewDocument', async () => {
  #     const { page } = getTestState();

  #     let called = false;
  #     await page.exposeFunction('woof', function () {
  #       called = true;
  #     });
  #     await page.evaluateOnNewDocument(() => globalThis.woof());
  #     await page.reload();
  #     expect(called).toBe(true);
  #   });
  #   it('should survive navigation', async () => {
  #     const { page, server } = getTestState();

  #     await page.exposeFunction('compute', function (a, b) {
  #       return a * b;
  #     });

  #     await page.goto(server.EMPTY_PAGE);
  #     const result = await page.evaluate(async function () {
  #       return await globalThis.compute(9, 4);
  #     });
  #     expect(result).toBe(36);
  #   });
  #   it('should await returned promise', async () => {
  #     const { page } = getTestState();

  #     await page.exposeFunction('compute', function (a, b) {
  #       return Promise.resolve(a * b);
  #     });

  #     const result = await page.evaluate(async function () {
  #       return await globalThis.compute(3, 5);
  #     });
  #     expect(result).toBe(15);
  #   });
  #   it('should work on frames', async () => {
  #     const { page, server } = getTestState();

  #     await page.exposeFunction('compute', function (a, b) {
  #       return Promise.resolve(a * b);
  #     });

  #     await page.goto(server.PREFIX + '/frames/nested-frames.html');
  #     const frame = page.frames()[1];
  #     const result = await frame.evaluate(async function () {
  #       return await globalThis.compute(3, 5);
  #     });
  #     expect(result).toBe(15);
  #   });
  #   it('should work on frames before navigation', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/frames/nested-frames.html');
  #     await page.exposeFunction('compute', function (a, b) {
  #       return Promise.resolve(a * b);
  #     });

  #     const frame = page.frames()[1];
  #     const result = await frame.evaluate(async function () {
  #       return await globalThis.compute(3, 5);
  #     });
  #     expect(result).toBe(15);
  #   });
  #   it('should work with complex objects', async () => {
  #     const { page } = getTestState();

  #     await page.exposeFunction('complexObject', function (a, b) {
  #       return { x: a.x + b.x };
  #     });
  #     const result = await page.evaluate<() => Promise<{ x: number }>>(
  #       async () => globalThis.complexObject({ x: 5 }, { x: 2 })
  #     );
  #     expect(result.x).toBe(7);
  #   });
  # });

  describe 'Page.Events.PageError' do
    sinatra do
      get('/error.html') do
        <<~HTML
        <script>
        a();

        function a() {
            b();
        }

        function b() {
            c();
        }

        function c() {
            throw new Error('Fancy error!');
        }
        </script>
        HTML
      end
    end

    it 'should fire' do
      Timeout.timeout(5) do
        error_promise = resolvable_future { |f| page.once('pageerror') { |err| f.fulfill(err) } }
        page.goto('http://127.0.0.1:4567/error.html')
        expect((await error_promise).message).to include("Fancy error!")
      end
    end
  end

  describe '#user_agent=' do
    include Utils::AttachFrame
    sinatra do
      get('/mobile.html') {
        '<meta name = "viewport" content = "initial-scale = 1, user-scalable = no">'
      }
    end

    it 'should work' do
      expect(page.evaluate('() => navigator.userAgent')).to include('Mozilla')
      page.user_agent = 'foobar'
      async_wait_for_request = resolvable_future do |f|
        sinatra.get('/empty.html') do
          f.fulfill(request)
          "EMPTY"
        end
      end
      page.goto('http://127.0.0.1:4567/empty.html')
      request = await async_wait_for_request
      expect(request.env['HTTP_USER_AGENT']).to eq('foobar')
    end

    it 'should work for subframes' do
      expect(page.evaluate('() => navigator.userAgent')).to include('Mozilla')
      page.goto('http://127.0.0.1:4567/xx')
      page.user_agent = 'foobar'
      async_wait_for_request = resolvable_future do |f|
        sinatra.get('/empty2.html') do
          f.fulfill(request)
          "EMPTY"
        end
      end
      attach_frame(page, 'frame1', '/empty2.html')
      request = await async_wait_for_request
      expect(request.env['HTTP_USER_AGENT']).to eq('foobar')
    end

    it 'should emulate device user-agent' do
      page.goto('http://127.0.0.1:4567/mobile.html')
      expect(page.evaluate('() => navigator.userAgent')).not_to include('iPhone')
      page.user_agent = Puppeteer::Devices.iPhone_6.user_agent
      expect(page.evaluate('() => navigator.userAgent')).to include('iPhone')
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

    context 'with stall for image page' do
      sinatra do
        get('/img.png') { sleep 1000 ; "" }
      end

      it 'should respect timeout' do
        Timeout.timeout(5) do
          expect { page.set_content('<img src="http://127.0.0.1:4567/img.png" />', timeout: 1) }.to raise_error(Puppeteer::TimeoutError)
        end
      end

      it 'should respect default navigation timeout' do
        page.default_navigation_timeout = 1
        Timeout.timeout(5) do
          expect { page.content = '<img src="http://127.0.0.1:4567/img.png" />' }.to raise_error(Puppeteer::TimeoutError)
        end
      end

      it 'should await resources to load' do
        async_wait_for_request = resolvable_future do |f|
          sinatra.get('/img2.png') do
            f.fulfill(request)

            sleep 0.3 # emulate image to load
            ""
          end
        end

        content_promise = future do
          page.content = '<img src="http://127.0.0.1:4567/img2.png" />'
        end

        await async_wait_for_request
        expect(content_promise).not_to be_fulfilled

        sleep 1 # wait for image loaded completely

        expect(content_promise).to be_fulfilled
      end
    end

    it 'should work fast enough' do
      Timeout.timeout(5) do
        50.times { |i| page.content = "<div>yo - #{i}</div>" }
      end
    end

    it 'should work with tricky content' do
      page.content = "<div>hello world</div>\x7F"
      expect(page.Seval("div", "(div) => div.textContent")).to eq("hello world")
    end

    it 'should work with accents' do
      page.content = '<div>aberración</div>'
      expect(page.Seval("div", "(div) => div.textContent")).to eq("aberración")
    end

    it 'should work with emojis' do
      page.content = '<div>🐥</div>'
      expect(page.Seval("div", "(div) => div.textContent")).to eq("🐥")
    end

    it 'should work with newline' do
      page.content = "<div>\n</div>"
      expect(page.Seval("div", "(div) => div.textContent")).to eq("\n")
    end
  end

  # describeFailsFirefox('Page.setBypassCSP', function () {
  #   it('should bypass CSP meta tag', async () => {
  #     const { page, server } = getTestState();

  #     // Make sure CSP prohibits addScriptTag.
  #     await page.goto(server.PREFIX + '/csp.html');
  #     await page
  #       .addScriptTag({ content: 'window.__injected = 42;' })
  #       .catch((error) => void error);
  #     expect(await page.evaluate(() => globalThis.__injected)).toBe(undefined);

  #     // By-pass CSP and try one more time.
  #     await page.setBypassCSP(true);
  #     await page.reload();
  #     await page.addScriptTag({ content: 'window.__injected = 42;' });
  #     expect(await page.evaluate(() => globalThis.__injected)).toBe(42);
  #   });

  #   it('should bypass CSP header', async () => {
  #     const { page, server } = getTestState();

  #     // Make sure CSP prohibits addScriptTag.
  #     server.setCSP('/empty.html', 'default-src "self"');
  #     await page.goto(server.EMPTY_PAGE);
  #     await page
  #       .addScriptTag({ content: 'window.__injected = 42;' })
  #       .catch((error) => void error);
  #     expect(await page.evaluate(() => globalThis.__injected)).toBe(undefined);

  #     // By-pass CSP and try one more time.
  #     await page.setBypassCSP(true);
  #     await page.reload();
  #     await page.addScriptTag({ content: 'window.__injected = 42;' });
  #     expect(await page.evaluate(() => globalThis.__injected)).toBe(42);
  #   });

  #   it('should bypass after cross-process navigation', async () => {
  #     const { page, server } = getTestState();

  #     await page.setBypassCSP(true);
  #     await page.goto(server.PREFIX + '/csp.html');
  #     await page.addScriptTag({ content: 'window.__injected = 42;' });
  #     expect(await page.evaluate(() => globalThis.__injected)).toBe(42);

  #     await page.goto(server.CROSS_PROCESS_PREFIX + '/csp.html');
  #     await page.addScriptTag({ content: 'window.__injected = 42;' });
  #     expect(await page.evaluate(() => globalThis.__injected)).toBe(42);
  #   });
  #   it('should bypass CSP in iframes as well', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     {
  #       // Make sure CSP prohibits addScriptTag in an iframe.
  #       const frame = await utils.attachFrame(
  #         page,
  #         'frame1',
  #         server.PREFIX + '/csp.html'
  #       );
  #       await frame
  #         .addScriptTag({ content: 'window.__injected = 42;' })
  #         .catch((error) => void error);
  #       expect(await frame.evaluate(() => globalThis.__injected)).toBe(
  #         undefined
  #       );
  #     }

  #     // By-pass CSP and try one more time.
  #     await page.setBypassCSP(true);
  #     await page.reload();

  #     {
  #       const frame = await utils.attachFrame(
  #         page,
  #         'frame1',
  #         server.PREFIX + '/csp.html'
  #       );
  #       await frame
  #         .addScriptTag({ content: 'window.__injected = 42;' })
  #         .catch((error) => void error);
  #       expect(await frame.evaluate(() => globalThis.__injected)).toBe(42);
  #     }
  #   });
  # });

  # describe('Page.addScriptTag', function () {
  #   it('should throw an error if no options are provided', async () => {
  #     const { page } = getTestState();

  #     let error = null;
  #     try {
  #       // @ts-expect-error purposefully passing bad options
  #       await page.addScriptTag('/injectedfile.js');
  #     } catch (error_) {
  #       error = error_;
  #     }
  #     expect(error.message).toBe(
  #       'Provide an object with a `url`, `path` or `content` property'
  #     );
  #   });

  #   it('should work with a url', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const scriptHandle = await page.addScriptTag({ url: '/injectedfile.js' });
  #     expect(scriptHandle.asElement()).not.toBeNull();
  #     expect(await page.evaluate(() => globalThis.__injected)).toBe(42);
  #   });

  #   it('should work with a url and type=module', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     await page.addScriptTag({ url: '/es6/es6import.js', type: 'module' });
  #     expect(await page.evaluate(() => globalThis.__es6injected)).toBe(42);
  #   });

  #   it('should work with a path and type=module', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     await page.addScriptTag({
  #       path: path.join(__dirname, 'assets/es6/es6pathimport.js'),
  #       type: 'module',
  #     });
  #     await page.waitForFunction('window.__es6injected');
  #     expect(await page.evaluate(() => globalThis.__es6injected)).toBe(42);
  #   });

  #   it('should work with a content and type=module', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     await page.addScriptTag({
  #       content: `import num from '/es6/es6module.js';window.__es6injected = num;`,
  #       type: 'module',
  #     });
  #     await page.waitForFunction('window.__es6injected');
  #     expect(await page.evaluate(() => globalThis.__es6injected)).toBe(42);
  #   });

  #   it('should throw an error if loading from url fail', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     let error = null;
  #     try {
  #       await page.addScriptTag({ url: '/nonexistfile.js' });
  #     } catch (error_) {
  #       error = error_;
  #     }
  #     expect(error.message).toBe('Loading script from /nonexistfile.js failed');
  #   });

  #   it('should work with a path', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const scriptHandle = await page.addScriptTag({
  #       path: path.join(__dirname, 'assets/injectedfile.js'),
  #     });
  #     expect(scriptHandle.asElement()).not.toBeNull();
  #     expect(await page.evaluate(() => globalThis.__injected)).toBe(42);
  #   });

  #   it('should include sourcemap when path is provided', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     await page.addScriptTag({
  #       path: path.join(__dirname, 'assets/injectedfile.js'),
  #     });
  #     const result = await page.evaluate(
  #       () => globalThis.__injectedError.stack
  #     );
  #     expect(result).toContain(path.join('assets', 'injectedfile.js'));
  #   });

  #   it('should work with content', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const scriptHandle = await page.addScriptTag({
  #       content: 'window.__injected = 35;',
  #     });
  #     expect(scriptHandle.asElement()).not.toBeNull();
  #     expect(await page.evaluate(() => globalThis.__injected)).toBe(35);
  #   });

  #   // @see https://github.com/puppeteer/puppeteer/issues/4840
  #   xit('should throw when added with content to the CSP page', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/csp.html');
  #     let error = null;
  #     await page
  #       .addScriptTag({ content: 'window.__injected = 35;' })
  #       .catch((error_) => (error = error_));
  #     expect(error).toBeTruthy();
  #   });

  #   it('should throw when added with URL to the CSP page', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/csp.html');
  #     let error = null;
  #     await page
  #       .addScriptTag({ url: server.CROSS_PROCESS_PREFIX + '/injectedfile.js' })
  #       .catch((error_) => (error = error_));
  #     expect(error).toBeTruthy();
  #   });
  # });

  # describe('Page.addStyleTag', function () {
  #   it('should throw an error if no options are provided', async () => {
  #     const { page } = getTestState();

  #     let error = null;
  #     try {
  #       // @ts-expect-error purposefully passing bad input
  #       await page.addStyleTag('/injectedstyle.css');
  #     } catch (error_) {
  #       error = error_;
  #     }
  #     expect(error.message).toBe(
  #       'Provide an object with a `url`, `path` or `content` property'
  #     );
  #   });

  #   it('should work with a url', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const styleHandle = await page.addStyleTag({ url: '/injectedstyle.css' });
  #     expect(styleHandle.asElement()).not.toBeNull();
  #     expect(
  #       await page.evaluate(
  #         `window.getComputedStyle(document.querySelector('body')).getPropertyValue('background-color')`
  #       )
  #     ).toBe('rgb(255, 0, 0)');
  #   });

  #   it('should throw an error if loading from url fail', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     let error = null;
  #     try {
  #       await page.addStyleTag({ url: '/nonexistfile.js' });
  #     } catch (error_) {
  #       error = error_;
  #     }
  #     expect(error.message).toBe('Loading style from /nonexistfile.js failed');
  #   });

  #   it('should work with a path', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const styleHandle = await page.addStyleTag({
  #       path: path.join(__dirname, 'assets/injectedstyle.css'),
  #     });
  #     expect(styleHandle.asElement()).not.toBeNull();
  #     expect(
  #       await page.evaluate(
  #         `window.getComputedStyle(document.querySelector('body')).getPropertyValue('background-color')`
  #       )
  #     ).toBe('rgb(255, 0, 0)');
  #   });

  #   it('should include sourcemap when path is provided', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     await page.addStyleTag({
  #       path: path.join(__dirname, 'assets/injectedstyle.css'),
  #     });
  #     const styleHandle = await page.$('style');
  #     const styleContent = await page.evaluate(
  #       (style: HTMLStyleElement) => style.innerHTML,
  #       styleHandle
  #     );
  #     expect(styleContent).toContain(path.join('assets', 'injectedstyle.css'));
  #   });

  #   it('should work with content', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.EMPTY_PAGE);
  #     const styleHandle = await page.addStyleTag({
  #       content: 'body { background-color: green; }',
  #     });
  #     expect(styleHandle.asElement()).not.toBeNull();
  #     expect(
  #       await page.evaluate(
  #         `window.getComputedStyle(document.querySelector('body')).getPropertyValue('background-color')`
  #       )
  #     ).toBe('rgb(0, 128, 0)');
  #   });

  #   itFailsFirefox(
  #     'should throw when added with content to the CSP page',
  #     async () => {
  #       const { page, server } = getTestState();

  #       await page.goto(server.PREFIX + '/csp.html');
  #       let error = null;
  #       await page
  #         .addStyleTag({ content: 'body { background-color: green; }' })
  #         .catch((error_) => (error = error_));
  #       expect(error).toBeTruthy();
  #     }
  #   );

  #   it('should throw when added with URL to the CSP page', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/csp.html');
  #     let error = null;
  #     await page
  #       .addStyleTag({
  #         url: server.CROSS_PROCESS_PREFIX + '/injectedstyle.css',
  #       })
  #       .catch((error_) => (error = error_));
  #     expect(error).toBeTruthy();
  #   });
  # });

  describe '#url' do
    sinatra do
      get("/empty.html") { "" }
    end

    it 'should work' do
      expect { page.goto("http://127.0.0.1:4567/empty.html") }.to change { page.url }.
        from("about:blank").to("http://127.0.0.1:4567/empty.html")
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

  describe '#cache_enabled', browser_context: :incognito do
    sinatra do
      get("/cached/one-style.css") {
        "body { background-color: pink; }"
      }
    end

    it 'should enable or disable the cache based on the state passed' do
      request_count = 0
      response_count = 0
      sinatra.get('/cached/one-style.html') do
        request_count += 1

        # ref: https://github.com/puppeteer/puppeteer/blob/main/utils/testserver/index.js
        cache_control :public, max_age: 31536000
        last_modified Time.now.iso8601

        response_count += 1
        "<link rel='stylesheet' href='./one-style.css'><div>hello, world!</div>"
      end

      page.goto('http://127.0.0.1:4567/cached/one-style.html')
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
      sinatra.get('/cached/one-style2.html') do
        request_count += 1

        # ref: https://github.com/puppeteer/puppeteer/blob/main/utils/testserver/index.js
        cache_control :public, max_age: 31536000
        last_modified Time.now.iso8601

        response_count += 1
        "<link rel='stylesheet' href='./one-style.css'><div>hello, world!</div>"
      end

      page.goto('http://127.0.0.1:4567/cached/one-style2.html')
      page.reload

      page.cache_enabled = false
      page.request_interception = true
      page.request_interception = false

      page.reload

      expect(request_count).to eq(3)
      expect(response_count).to eq(2)
    end
  end

  describe 'printing to PDF' do
    sinatra do
      get("/") { "<h1>It Works!</h1>" }
    end

    it 'can print to PDF and save to file' do
      skip('Printing to pdf is currently only supported in headless') unless headless?

      page.goto('http://127.0.0.1:4567/')

      Dir.mktmpdir do |tempdir|
        output_filepath = File.join(tempdir, "output.pdf")
        page.pdf(path: output_filepath)
        puts output_filepath
        expect(File.read(output_filepath).size).to be > 0
      end
    end
  end

  describe '#title' do
    sinatra do
      get("/title") { "<title>Woof-Woof</title>" }
    end

    it 'should return the page title' do
      page.goto("http://127.0.0.1:4567/title")
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
  #   it('should return [] on no values', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/input/select.html');
  #     const result = await page.select('select');
  #     expect(result).toEqual([]);
  #   });
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
  #   it('should deselect all options when passed no values for a select without multiple', async () => {
  #     const { page, server } = getTestState();

  #     await page.goto(server.PREFIX + '/input/select.html');
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
      new_page_promise = resolvable_future { |f| page.browser_context.once('targetcreated') { |target| f.fulfill(target.page) } }
      page.evaluate("() => { (window['newPage'] = window.open('about:blank')) }")
      new_page = await new_page_promise

      closed_promise = resolvable_future { |f| new_page.once('close') { f.fulfill(nil) } }
      page.evaluate("() => { window['newPage'].close() }")
      await closed_promise
    end

    it 'should work with page.close', puppeteer: :browser do
      new_page = browser.new_page
      closed_promise = resolvable_future { |f| new_page.once('close') { f.fulfill(nil) } }
      new_page.close
      await closed_promise
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
