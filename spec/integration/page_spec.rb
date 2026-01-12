require 'spec_helper'
require 'thread'

RSpec.describe Puppeteer::Page do
  include_context 'with test state'
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
      expect { promise.wait }.to raise_error(/Protocol error/)
    end

    it 'should not be visible in browser.pages', puppeteer: :browser do
      new_page = browser.new_page
      expect(browser.pages).to include(new_page)
      new_page.close
      expect(browser.pages).not_to include(new_page)
    end

    it 'should run beforeunload if asked for', sinatra: true do
      context = page.browser_context

      new_page = context.new_page
      new_page.goto("#{server_prefix}/beforeunload.html")
      # We have to interact with a page so that 'beforeunload' handlers
      # fire.
      new_page.click('body')
      dialog_promise = Async::Promise.new.tap do |promise|
        new_page.once('dialog') { |d| promise.resolve(d) }
      end
      new_page.close(run_before_unload: true)
      sleep 0.2
      expect(dialog_promise.completed?).to eq(true)
      dialog = dialog_promise.wait
      expect(dialog.type).to eq("beforeunload")
      expect(dialog.default_value).to eq("")
      expect(dialog.message).to eq("")
      dialog.accept
    end

    it 'should *not* run beforeunload by default', sinatra: true do
      context = page.browser_context

      new_page = context.new_page
      new_page.goto("#{server_prefix}/beforeunload.html")
      # We have to interact with a page so that 'beforeunload' handlers
      # fire.
      new_page.click('body')
      dialog_promise = Async::Promise.new.tap do |promise|
        new_page.once('dialog') { |d| promise.resolve(d) }
      end
      new_page.close
      sleep 0.2
      expect(dialog_promise.resolved?).to eq(false)
    end

    it 'should set the page close state' do
      context = page.browser_context

      new_page = context.new_page
      expect(new_page).not_to be_closed
      expect { new_page.close }.to change { new_page.closed? }.from(false).to(true)
    end

    it 'should terminate network waiters', sinatra: true do
      context = page.browser_context

      new_page = context.new_page
      req_promise = new_page.async_wait_for_request(url: server_empty_page)
      res_promise = new_page.async_wait_for_response(url: server_empty_page)
      new_page.close

      expect { req_promise.wait }.to raise_error(/Target Closed/)
      expect { res_promise.wait }.to raise_error(/Target Closed/)
    end
  end

  describe 'Page.Events.Load' do
    it 'should fire when expected' do
      Timeout.timeout(5) do
        load_promise = Async::Promise.new.tap do |promise|
          page.once('load') { promise.resolve(nil) }
        end
        await_with_trigger(load_promise) do
          page.goto("about:blank")
        end
      end
    end
  end

  describe 'removing and adding event handlers' do
    it 'should correctly fire event handlers as they are added and then removed', sinatra: true do
      calls = 0
      on_response = lambda do |response|
        next if response.url.include?('favicon.ico')

        calls += 1
      end

      page.on('response', &on_response)
      page.goto(server_empty_page)
      expect(calls).to eq(1)

      page.off('response', on_response)
      page.goto(server_empty_page)
      # Still one because we removed the handler.
      expect(calls).to eq(1)

      page.on('response', &on_response)
      page.goto(server_empty_page)
      # Two now because we added the handler back.
      expect(calls).to eq(2)
    end

    it 'should correctly added and removed request events', sinatra: true do
      calls = 0
      on_request = lambda do |request|
        next if request.url.include?('favicon.ico')

        calls += 1
      end

      page.on('request', &on_request)
      page.on('request', &on_request)
      page.goto(server_empty_page)
      expect(calls).to eq(2)

      page.off('request', on_request)
      page.goto(server_empty_page)
      # Still one because we removed the handler.
      expect(calls).to eq(3)

      page.off('request', on_request)
      page.goto(server_empty_page)
      expect(calls).to eq(3)

      page.on('request', &on_request)
      page.goto(server_empty_page)
      # Two now because we added the handler back.
      expect(calls).to eq(4)
    end
  end

  describe 'Page.Events.error' do
    it 'should throw when page crashes' do
      error_promise = Async::Promise.new.tap do |promise|
        page.once('error') { |err| promise.resolve(err) }
      end
      async_promise { page.goto("chrome://crash") }
      expect(error_promise.wait.message).to eq("Page crashed!")
    end
  end

  describe 'Page.Events.Popup' do
    it 'should work' do
      popup_promise = Async::Promise.new.tap do |promise|
        page.once('popup') { |popup| promise.resolve(popup) }
      end
      page.evaluate("() => { window.open('about:blank') }")
      popup = popup_promise.wait

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(true)
    end

    it 'should work with noopener' do
      popup_promise = Async::Promise.new.tap do |promise|
        page.once('popup') { |popup| promise.resolve(popup) }
      end
      page.evaluate("() => { window.open('about:blank', null, 'noopener') }")
      popup = popup_promise.wait

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(false)
    end

    it 'should work with clicking target=_blank', sinatra: true do
      page.goto(server_empty_page)
      page.content = '<a target=_blank href="/one-style.html">yo</a>'

      popup_promise = Async::Promise.new.tap do |promise|
        page.once('popup') { |popup| promise.resolve(popup) }
      end
      page.click("a")
      popup = popup_promise.wait

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(false) # was true in Chrome < 88.
    end

    it 'should work with clicking target=_blank and rel=opener', sinatra: true do
      page.goto(server_empty_page)
      page.content = '<a target=_blank rel=opener href="/one-style.html">yo</a>'

      popup_promise = Async::Promise.new.tap do |promise|
        page.once('popup') { |popup| promise.resolve(popup) }
      end
      page.click("a")
      popup = popup_promise.wait

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(true)
    end

    it 'should work with fake-clicking target=_blank and rel=noopener', sinatra: true do
      page.goto(server_empty_page)
      page.content = '<a target=_blank rel=noopener href="/one-style.html">yo</a>'

      popup_promise = Async::Promise.new.tap do |promise|
        page.once('popup') { |popup| promise.resolve(popup) }
      end
      page.eval_on_selector("a", "(a) => a.click()")
      popup = popup_promise.wait

      expect(page.evaluate("() => !!window.opener")).to eq(false)
      expect(popup.evaluate("() => !!window.opener")).to eq(false)
    end

    it 'should work with clicking target=_blank and rel=noopener', sinatra: true do
      page.goto(server_empty_page)
      page.content = '<a target=_blank rel=noopener href="/one-style.html">yo</a>'

      popup_promise = Async::Promise.new.tap do |promise|
        page.once('popup') { |popup| promise.resolve(popup) }
      end
      page.click("a")
      popup = popup_promise.wait

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

    it 'should deny permission when not listed' do
      page.browser_context.override_permissions(server_empty_page, [])
      expect(get_permission_for(page, "geolocation")).to eq("denied")
    end

    it 'should fail when bad permission is given' do
      expect { page.browser_context.override_permissions(server_empty_page, ['foo']) }.
        to raise_error(/Unknown permission: foo/)
    end

    it 'should grant permission when listed' do
      page.browser_context.override_permissions(server_empty_page, ['geolocation'])
      expect(get_permission_for(page, "geolocation")).to eq("granted")
    end

    it 'should reset permissions' do
      page.browser_context.override_permissions(server_empty_page, ['geolocation'])

      expect {
        page.browser_context.clear_permission_overrides
      }.to change { get_permission_for(page, "geolocation") }.from("granted").to("prompt")
    end

    it 'should trigger permission onchange' do
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

    it 'should isolate permissions between browser contexs' do
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

    it 'should grant persistent-storage' do
      expect(get_permission_for(page, 'persistent-storage')).to eq('prompt')
      page.browser_context.override_permissions(server_empty_page, ['persistent-storage'])
      expect(get_permission_for(page, "persistent-storage")).to eq("granted")
    end
  end

  describe '#geolocation=' do
    it 'should work', browser_context: :incognito, sinatra: true do
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
    it 'should work', sinatra: true do
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
  it 'should not fail for window object' do
    message = await_promises(
      Async::Promise.new.tap { |promise| page.once('console') { |m| promise.resolve(m) } },
      async_promise { page.evaluate('() => console.error(window)') },
    ).first
    expect(['JSHandle@object', 'JSHandle@window']).to include(message.text)
  end

  it 'should trigger correct Log' do
    page.goto("#{server_prefix}/empty.html")
    message = await_promises(
      Async::Promise.new.tap { |promise| page.once('console') { |m| promise.resolve(m) } },
      async_promise do
        page.evaluate('async (url) => fetch(url).catch(() => {})', "#{server_cross_process_prefix}/empty.html")
      end,
    ).first
    expect(message.text).to include('Access-Control-Allow-Origin')
    expect(message.log_type).to eq('error')
  end

  it 'should have location when fetch fails' do
    page.goto(server_empty_page)
    message = await_promises(
      Async::Promise.new.tap { |promise| page.once('console') { |m| promise.resolve(m) } },
      async_promise { page.set_content("<script>fetch('http://wat');</script>") },
    ).first
    expect(message.text).to include('ERR_NAME_NOT_RESOLVED')
    expect(message.log_type).to eq('error')
    expect(message.location.url).to eq('http://wat/')
    expect(message.location.line_number).to satisfy { |line| line.nil? || line < 0 }
  end
  it 'should have location and stack trace for console API calls', sinatra: true do
    page.goto(server_empty_page)

    message = await_promises(
      Async::Promise.new.tap { |promise| page.once('console') { |m| promise.resolve(m) } },
      async_promise { page.goto("#{server_prefix}/consolelog.html") },
    ).first
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
  # @see https://github.com/puppeteer/puppeteer/issues/3865
  it 'should not throw when there are console messages in detached iframes' do
    page.goto(server_empty_page)
    page.evaluate(<<~JAVASCRIPT)
    async () => {
      const win = window.open(
        window.location.href,
        'Title',
        'toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes,width=780,height=200,top=0,left=0'
      );
      await new Promise((x) => (win.onload = x));
      win.document.body.innerHTML = `<iframe src='/consolelog.html'></iframe>`;
      const frame = win.document.querySelector('iframe');
      await new Promise((x) => (frame.onload = x));
      frame.remove();
    }
    JAVASCRIPT
    popup_target = page.browser_context.targets.last
    popup_page = popup_target.page
    expect(popup_page).not_to eq(page)
  end
  # });

  describe 'Page.Events.DOMContentLoaded' do
    it 'should fire when expected' do
      Timeout.timeout(5) do
        promise = Async::Promise.new.tap do |p|
          page.once('domcontentloaded') { p.resolve(nil) }
        end
        page.goto('about:blank')
        promise.wait
      end
    end
  end

  describe 'Page#metrics' do
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
      metrics_promise = Async::Promise.new.tap do |promise|
        page.once('metrics') { |event| promise.resolve(event) }
      end

      page.evaluate('() => console.timeStamp("test42")')
      metrics_event = metrics_promise.wait
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
      requests = await_promises(*promises)
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

  describe 'Page.waitForResponse', sinatra: true do
    it 'should work' do
      page.goto(server_empty_page)
      response = page.wait_for_response(url: "#{server_prefix}/digits/2.png") do
        page.evaluate(<<~JAVASCRIPT)
        () => {
          fetch('/digits/1.png');
          fetch('/digits/2.png');
          fetch('/digits/3.png');
        }
        JAVASCRIPT
      end
      expect(response.url).to eq("#{server_prefix}/digits/2.png")
    end

    it 'should respect timeout' do
      page.goto(server_empty_page)
      expect { page.wait_for_response(predicate: ->(_) { false }, timeout: 1) }.
        to raise_error(Puppeteer::TimeoutError)
    end

    it 'should respect default timeout' do
      page.goto(server_empty_page)
      page.default_timeout = 1
      expect { page.wait_for_response(predicate: ->(_) { false }) }.
        to raise_error(Puppeteer::TimeoutError)
    end

    it 'should work with predicate' do
      page.goto(server_empty_page)
      predicate = ->(response) { response.url == "#{server_prefix}/digits/2.png" }
      response = page.wait_for_response(predicate: predicate) do
        page.evaluate(<<~JAVASCRIPT)
        () => {
          fetch('/digits/1.png');
          fetch('/digits/2.png');
          fetch('/digits/3.png');
        }
        JAVASCRIPT
      end
      expect(response.url).to eq("#{server_prefix}/digits/2.png")
    end

    it 'should work with async predicate' do
      page.goto(server_empty_page)
      predicate = ->(response) { Async { response.url == "#{server_prefix}/digits/2.png" } }
      response = page.wait_for_response(predicate: predicate) do
        page.evaluate(<<~JAVASCRIPT)
        () => {
          fetch('/digits/1.png');
          fetch('/digits/2.png');
          fetch('/digits/3.png');
        }
        JAVASCRIPT
      end
      expect(response.url).to eq("#{server_prefix}/digits/2.png")
    end

    it 'should work with no timeout' do
      page.goto(server_empty_page)
      response = page.wait_for_response(url: "#{server_prefix}/digits/2.png", timeout: 0) do
        page.evaluate(<<~JAVASCRIPT)
        () => setTimeout(() => {
          fetch('/digits/1.png');
          fetch('/digits/2.png');
          fetch('/digits/3.png');
        }, 50)
        JAVASCRIPT
      end
      expect(response.url).to eq("#{server_prefix}/digits/2.png")
    end

    it 'should be cancellable' do
      skip('AbortSignal is not supported')
    end
  end

  describe 'Page.waitForNetworkIdle', sinatra: true do
    it 'should work' do
      page.goto(server_empty_page)
      result = nil
      wait_promise = async_promise do
        result = page.wait_for_network_idle
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      evaluate_promise = async_promise do
        page.evaluate(<<~JAVASCRIPT)
        async () => {
          await Promise.all([fetch('/digits/1.png'), fetch('/digits/2.png')]);
          await new Promise(resolve => setTimeout(resolve, 200));
          await fetch('/digits/3.png');
          await new Promise(resolve => setTimeout(resolve, 200));
          await fetch('/digits/4.png');
        }
        JAVASCRIPT
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      t1, t2 = await_promises(wait_promise, evaluate_promise)
      expect(result).to be_nil
      expect(t1).to be > t2
      expect(t1 - t2).to be >= 0.4
    end

    it 'should respect timeout' do
      expect { page.wait_for_network_idle(timeout: 1) }.
        to raise_error(Puppeteer::TimeoutError)
    end

    it 'should respect idleTime' do
      page.goto(server_empty_page)
      wait_promise = async_promise do
        page.wait_for_network_idle(idle_time: 10)
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      evaluate_promise = async_promise do
        page.evaluate(<<~JAVASCRIPT)
        async () => {
          await Promise.all([fetch('/digits/1.png'), fetch('/digits/2.png')]);
          await new Promise(resolve => setTimeout(resolve, 250));
        }
        JAVASCRIPT
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      t1, t2 = await_promises(wait_promise, evaluate_promise)
      expect(t2).to be > t1
    end

    it 'should work with no timeout' do
      page.goto(server_empty_page)
      wait_promise = async_promise do
        page.wait_for_network_idle(timeout: 0)
      end
      evaluate_promise = async_promise do
        page.evaluate(<<~JAVASCRIPT)
        () => setTimeout(() => {
          fetch('/digits/1.png');
          fetch('/digits/2.png');
          fetch('/digits/3.png');
        }, 50)
        JAVASCRIPT
      end
      result = await_promises(wait_promise, evaluate_promise).first
      expect(result).to be_nil
    end

    it 'should work with aborted requests' do
      page.goto("#{server_prefix}/abort-request.html")
      element = page.query_selector('#abort')
      element.click
      expect { page.wait_for_network_idle }.not_to raise_error
    end

    it 'should work with delayed response' do
      page.goto(server_empty_page)
      response_started = Queue.new
      response_continue = Queue.new
      server.set_route('/fetch-request-b.js') do |_request, writer|
        response_started << true
        response_continue.pop
        writer.finish
      end

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      wait_promise = async_promise do
        page.wait_for_network_idle(idle_time: 100)
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      response_promise = async_promise do
        response_started.pop
        sleep 0.3
        response_continue << true
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      fetch_promise = async_promise do
        page.evaluate('async () => { await fetch("/fetch-request-b.js"); }')
      end

      t1, t2 = await_promises(wait_promise, response_promise, fetch_promise).first(2)
      expect(t1).to be > t2
      expect(t1 - t0).to be > 0.4
      expect(t1 - t2).to be >= 0.1
    end

    it 'should be cancelable' do
      skip('AbortSignal is not supported')
    end
  end

  describe 'Page.waitForFrame', sinatra: true do
    include Utils::AttachFrame

    it 'should work' do
      page.goto(server_empty_page)
      waited_frame = page.wait_for_frame(predicate: ->(frame) { frame.url.end_with?('/title.html') }) do
        attach_frame(page, 'frame2', "#{server_prefix}/title.html")
      end
      expect(waited_frame.parent_frame).to eq(page.main_frame)
    end

    it 'should work with a URL predicate' do
      page.goto(server_empty_page)
      waited_frame = page.wait_for_frame(url: "#{server_prefix}/title.html") do
        attach_frame(page, 'frame2', "#{server_prefix}/title.html")
      end
      expect(waited_frame.parent_frame).to eq(page.main_frame)
    end

    it 'should be cancellable' do
      skip('AbortSignal is not supported')
    end
  end

  describe 'Page#expose_function' do
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

  describe 'Page#remove_exposed_function' do
    it 'should work' do
      page.expose_function('compute', ->(a, b) { a * b })
      result = page.evaluate('async function() { return await globalThis.compute(9, 4) }')
      expect(result).to eq(36)
      page.remove_exposed_function('compute')

      expect {
        page.evaluate('async function() { return await globalThis.compute(9, 4) }')
      }.to raise_error(Puppeteer::Error)
    end
  end

  describe 'Page.Events.PageError' do
    it 'should fire', sinatra: true do
      Timeout.timeout(5) do
        error_promise = Async::Promise.new.tap do |promise|
          page.once('pageerror') { |err| promise.resolve(err) }
        end
        page.goto("#{server_prefix}/error.html")
        expect(error_promise.wait.message).to include("Fancy error!")
      end
    end
  end

  describe '#user_agent=', sinatra: true do
    include Utils::AttachFrame

    it 'should work' do
      expect(page.evaluate('() => navigator.userAgent')).to include('Mozilla')
      page.user_agent = 'foobar'
      async_wait_for_request = Async::Promise.new.tap do |promise|
        sinatra.get('/_empty.html') do
          promise.resolve(request)
          "EMPTY"
        end
      end
      page.goto("#{server_prefix}/_empty.html")
      request = async_wait_for_request.wait
      expect(request.env['HTTP_USER_AGENT']).to eq('foobar')
    end

    it 'should work for subframes' do
      expect(page.evaluate('() => navigator.userAgent')).to include('Mozilla')
      page.goto(server_empty_page)
      page.user_agent = 'foobar'
      async_wait_for_request = Async::Promise.new.tap do |promise|
        sinatra.get('/empty2.html') do
          promise.resolve(request)
          "EMPTY"
        end
      end
      attach_frame(page, 'frame1', '/empty2.html')
      request = async_wait_for_request.wait
      expect(request.env['HTTP_USER_AGENT']).to eq('foobar')
    end

    it 'should emulate device user-agent' do
      page.goto("#{server_prefix}/mobile.html")
      expect(page.evaluate('() => navigator.userAgent')).not_to include('iPhone')
      page.user_agent = Puppeteer::Devices.iPhone_6.user_agent
      expect(page.evaluate('() => navigator.userAgent')).to include('iPhone')
    end

    it 'should work with additional userAgentMetdata' do
      page.set_user_agent('MockBrowser',
        architecture: 'Mock1',
        mobile: false,
        model: 'Mockbook',
        platform: 'MockOS',
        platformVersion: '3.1',
      )

      async_wait_for_request = Async::Promise.new.tap do |promise|
        sinatra.get('/_empty.html') do
          promise.resolve(request)
          "EMPTY"
        end
      end
      page.goto("#{server_prefix}/_empty.html")
      request = async_wait_for_request.wait
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
      async_wait_for_request = Async::Promise.new.tap do |promise|
        sinatra.get('/img2.png') do
          promise.resolve(request)

          sleep 0.3 # emulate image to load
          ""
        end
      end

      content_promise = async_promise do
        page.content = "<img src=\"#{server_prefix}/img2.png\" />"
      end

      async_wait_for_request.wait
      expect(content_promise.completed?).to eq(false)

      sleep 1 # wait for image loaded completely

      expect(content_promise.completed?).to eq(true)
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

  describe '#bypass_csp=' do
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

    it 'should throw when added with content to the CSP page', sinatra: true do
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
    it 'should work' do
      page.javascript_enabled = false
      page.goto('data:text/html, <script>var something = "forbidden"</script>')
      expect { page.evaluate("something") }.to raise_error(/something is not defined/)

      page.javascript_enabled = true
      page.goto('data:text/html, <script>var something = "forbidden"</script>')
      expect(page.evaluate("something")).to eq("forbidden")
    end
  end

  describe 'Page.reload', sinatra: true do
    it 'should enable or disable the cache based on reload params' do
      page.goto("#{server_prefix}/cached/one-style.html")
      cached_request = await_promises(
        async_promise { server.wait_for_request('/cached/one-style.html') },
        async_promise { page.reload },
      ).first
      expect(cached_request.headers['if-modified-since']).not_to be_nil

      non_cached_request = await_promises(
        async_promise { server.wait_for_request('/cached/one-style.html') },
        async_promise { page.reload(ignore_cache: true) },
      ).first
      expect(non_cached_request.headers['if-modified-since']).to be_nil
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

    it 'should stay disabled when toggling request interception on/off' do
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
      new_page_promise = Async::Promise.new.tap do |promise|
        page.browser_context.once('targetcreated') { |target| promise.resolve(target.page) }
      end
      page.evaluate("() => { (window['newPage'] = window.open('about:blank')) }")
      new_page = new_page_promise.wait

      closed_promise = Async::Promise.new.tap do |promise|
        new_page.once('close') { promise.resolve(nil) }
      end
      page.evaluate("() => { window['newPage'].close() }")
      closed_promise.wait
    end

    it 'should work with page.close', puppeteer: :browser do
      new_page = browser.new_page
      closed_promise = Async::Promise.new.tap do |promise|
        new_page.once('close') { promise.resolve(nil) }
      end
      new_page.close
      closed_promise.wait
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

  describe '#client' do
    it 'should return the client instance' do
      expect(page.client).to be_a(Puppeteer::CDPSession)
    end
  end

  describe '#bring_to_front' do
    it 'should work' do
      context = page.browser_context
      page1 = context.new_page
      page2 = context.new_page

      page1.bring_to_front
      expect(page1.evaluate('() => document.visibilityState')).to eq('visible')
      expect(page2.evaluate('() => document.visibilityState')).to eq('hidden')

      page2.bring_to_front
      expect(page1.evaluate('() => document.visibilityState')).to eq('hidden')
      expect(page2.evaluate('() => document.visibilityState')).to eq('visible')

      page1.close
      page2.close
    end
  end
end
