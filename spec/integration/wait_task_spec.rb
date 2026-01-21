require 'spec_helper'

RSpec.describe 'waittask specs' do
  include Utils::AttachFrame
  include Utils::DetachFrame

  def add_element_js
    "(tag) => document.body.appendChild(document.createElement(tag))"
  end

  def sleep_ms(milliseconds)
    Puppeteer::AsyncUtils.sleep_seconds(milliseconds / 1000.0)
  end

  describe 'Frame.waitForFunction', sinatra: true do
    it 'should accept a string' do
      with_test_state do |page:, **|
        watchdog = page.async_wait_for_function('self.__FOO === 1')
        page.evaluate('() => { globalThis.__FOO = 1; }')
        watchdog.wait
      end
    end

    it 'should work when resolved right before execution context disposal' do
      with_test_state do |page:, **|
        page.evaluate_on_new_document('() => { globalThis.__RELOADED = true; }')
        page.wait_for_function(<<~JAVASCRIPT)
        () => {
          if (!globalThis.__RELOADED) {
            window.location.reload();
            return false;
          }
          return true;
        }
        JAVASCRIPT
      end
    end

    it 'should poll on interval' do
      with_test_state do |page:, **|
        start_time = Time.now
        polling = 100
        watchdog = page.async_wait_for_function(
          '() => globalThis.__FOO === "hit"',
          polling: polling,
        )
        page.evaluate(<<~JAVASCRIPT)
        () => {
          setTimeout(() => {
            globalThis.__FOO = 'hit';
          }, 50);
        }
        JAVASCRIPT
        watchdog.wait
        elapsed_ms = (Time.now - start_time) * 1000
        expect(elapsed_ms).to be >= (polling / 2.0)
      end
    end

    it 'should poll on mutation' do
      with_test_state do |page:, **|
        watchdog = page.async_wait_for_function(
          '() => globalThis.__FOO === "hit"',
          polling: 'mutation',
        )
        page.evaluate('() => { globalThis.__FOO = "hit"; }')
        sleep_ms(40)
        expect(watchdog.completed?).to eq(false)
        page.evaluate('() => document.body.appendChild(document.createElement("div"))')
        watchdog.wait
      end
    end

    it 'should poll on mutation async' do
      with_test_state do |page:, **|
        watchdog = page.async_wait_for_function(
          'async () => globalThis.__FOO === "hit"',
          polling: 'mutation',
        )
        page.evaluate('async () => { globalThis.__FOO = "hit"; }')
        sleep_ms(40)
        expect(watchdog.completed?).to eq(false)
        page.evaluate('async () => document.body.appendChild(document.createElement("div"))')
        watchdog.wait
      end
    end

    it 'should poll on raf' do
      with_test_state do |page:, **|
        watchdog = page.async_wait_for_function(
          '() => globalThis.__FOO === "hit"',
          polling: 'raf',
        )
        page.evaluate('() => { globalThis.__FOO = "hit"; }')
        watchdog.wait
      end
    end

    it 'should poll on raf async' do
      with_test_state do |page:, **|
        watchdog = page.async_wait_for_function(
          'async () => globalThis.__FOO === "hit"',
          polling: 'raf',
        )
        page.evaluate('async () => { globalThis.__FOO = "hit"; }')
        watchdog.wait
      end
    end

    it 'should work with strict CSP policy' do
      with_test_state do |page:, server:, **|
        server.set_csp('/empty.html', "script-src #{server.prefix}")
        page.goto(server.empty_page)
        watchdog = page.async_wait_for_function(
          '() => globalThis.__FOO === "hit"',
          polling: 'raf',
        )
        page.evaluate('() => { globalThis.__FOO = "hit"; }')
        watchdog.wait
      end
    end

    it 'should throw negative polling interval' do
      with_test_state do |page:, **|
        expect do
          page.wait_for_function('() => !!document.body', polling: -10)
        end.to raise_error(ArgumentError, /Cannot poll with non-positive interval/)
      end
    end

    it 'should return the success value as a JSHandle' do
      with_test_state do |page:, **|
        handle = page.wait_for_function('() => 5')
        expect(handle.json_value).to eq(5)
      end
    end

    it 'should return the window as a success value' do
      with_test_state do |page:, **|
        handle = page.wait_for_function('() => window')
        expect(handle).not_to be_nil
      end
    end

    it 'should accept ElementHandle arguments' do
      with_test_state do |page:, **|
        page.set_content('<div></div>')
        div = page.query_selector('div')
        watchdog = page.async_wait_for_function(
          '(element) => element.localName === "div" && !element.parentElement',
          args: [div],
        )
        sleep_ms(40)
        expect(watchdog.completed?).to eq(false)
        page.evaluate('(element) => element.remove()', div)
        watchdog.wait
        div&.dispose
      end
    end

    it 'should respect timeout' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.wait_for_function('() => false', timeout: 10)
        rescue => err
          error = err
        end
        expect(error).to be_a(Puppeteer::TimeoutError)
        expect(error.message).to include('Waiting failed: 10ms exceeded')
      end
    end

    it 'should respect default timeout' do
      with_test_state do |page:, **|
        page.default_timeout = 1
        error = nil
        begin
          page.wait_for_function('() => false')
        rescue => err
          error = err
        end
        expect(error).to be_a(Puppeteer::TimeoutError)
        expect(error.message).to include('Waiting failed: 1ms exceeded')
      end
    end

    it 'should disable timeout when its set to 0' do
      with_test_state do |page:, **|
        watchdog = page.async_wait_for_function(
          <<~JAVASCRIPT,
          () => {
            globalThis.__counter = (globalThis.__counter || 0) + 1;
            return globalThis.__injected;
          }
          JAVASCRIPT
          polling: 10,
          timeout: 0,
        )
        page.wait_for_function('() => globalThis.__counter > 10')
        page.evaluate('() => { globalThis.__injected = true; }')
        watchdog.wait
      end
    end

    it 'should survive cross-process navigation' do
      with_test_state do |page:, server:, **|
        watchdog = page.async_wait_for_function('() => globalThis.__FOO === 1')
        page.goto(server.empty_page)
        expect(watchdog.completed?).to eq(false)
        page.reload
        expect(watchdog.completed?).to eq(false)
        page.goto("#{server.cross_process_prefix}/grid.html")
        expect(watchdog.completed?).to eq(false)
        page.evaluate('() => { globalThis.__FOO = 1; }')
        watchdog.wait
        expect(watchdog.completed?).to eq(true)
      end
    end

    it 'should survive navigations' do
      with_test_state do |page:, server:, **|
        watchdog = page.async_wait_for_function('() => globalThis.__done')
        page.goto(server.empty_page)
        page.goto("#{server.prefix}/consolelog.html")
        page.evaluate('() => { globalThis.__done = true; }')
        watchdog.wait
      end
    end

    it 'should be cancellable' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        abort_controller = Puppeteer::AbortController.new
        task = page.async_wait_for_function(
          '() => globalThis.__done',
          signal: abort_controller.signal,
        )
        abort_controller.abort
        expect { task.wait }.to raise_error(/aborted/)
      end
    end

    it 'can start multiple tasks without node warnings' do
      with_test_state do |page:, **|
        abort_controller = Puppeteer::AbortController.new
        page.wait_for_function('() => true', signal: abort_controller.signal)
        page.wait_for_function('() => true', signal: abort_controller.signal)
      end
    end
  end

  describe 'Frame.waitForSelector', sinatra: true do
    it 'should immediately resolve promise if node exists' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        frame = page.main_frame
        frame.wait_for_selector('*')
        frame.evaluate(add_element_js, 'div')
        frame.wait_for_selector('div')
      end
    end

    it 'should be cancellable' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        abort_controller = Puppeteer::AbortController.new
        task = page.async_wait_for_selector('wrong', signal: abort_controller.signal)
        abort_controller.abort
        expect { task.wait }.to raise_error(/aborted/)
      end
    end

    it 'should work with removed MutationObserver' do
      with_test_state do |page:, **|
        page.evaluate('() => { delete window.MutationObserver; }')
        watchdog = page.async_wait_for_selector('.zombo')
        page.set_content('<div class="zombo">anything</div>')
        handle = watchdog.wait
        expect(page.evaluate('(x) => x?.textContent', handle)).to eq('anything')
      end
    end

    it 'should resolve promise when node is added' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        frame = page.main_frame
        watchdog = frame.async_wait_for_selector('div')
        frame.evaluate(add_element_js, 'br')
        frame.evaluate(add_element_js, 'div')
        handle = watchdog.wait
        tag_name = handle.property('tagName').json_value
        expect(tag_name).to eq('DIV')
      end
    end

    it 'should work when node is added through innerHTML' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        watchdog = page.async_wait_for_selector('h3 div')
        page.evaluate(add_element_js, 'span')
        page.evaluate("() => (document.querySelector('span').innerHTML = '<h3><div></div></h3>')")
        watchdog.wait
      end
    end

    it 'should work when node is added in a shadow root' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        watcher = page.async_wait_for_selector('div >>> h1')
        page.evaluate(add_element_js, 'div')
        sleep_ms(40)
        expect(watcher.completed?).to eq(false)
        page.evaluate(<<~JAVASCRIPT)
        () => {
          const host = document.querySelector('div');
          const shadow = host.attachShadow({mode: 'open'});
          const h1 = document.createElement('h1');
          h1.textContent = 'inside';
          shadow.appendChild(h1);
        }
        JAVASCRIPT
        element = watcher.wait
        expect(element.evaluate('el => el.textContent')).to eq('inside')
      end
    end

    it 'should work for selector with a pseudo class' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        watchdog = page.async_wait_for_selector('input:focus')
        sleep_ms(40)
        expect(watchdog.completed?).to eq(false)
        page.set_content('<input></input>')
        page.click('input')
        watchdog.wait
      end
    end

    it 'Page.waitForSelector is shortcut for main frame' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        attach_frame(page, 'frame1', server.empty_page)
        other_frame = page.frames[1]
        watchdog = page.async_wait_for_selector('div')
        other_frame.evaluate(add_element_js, 'div')
        page.evaluate(add_element_js, 'div')
        handle = watchdog.wait
        expect(handle.frame).to eq(page.main_frame)
      end
    end

    it 'should run in specified frame' do
      with_test_state do |page:, server:, **|
        attach_frame(page, 'frame1', server.empty_page)
        attach_frame(page, 'frame2', server.empty_page)
        frame1 = page.frames[1]
        frame2 = page.frames[2]
        watchdog = frame2.async_wait_for_selector('div')
        frame1.evaluate(add_element_js, 'div')
        frame2.evaluate(add_element_js, 'div')
        handle = watchdog.wait
        expect(handle.frame).to eq(frame2)
      end
    end

    it 'should throw when frame is detached' do
      with_test_state do |page:, server:, **|
        attach_frame(page, 'frame1', server.empty_page)
        frame = page.frames[1]
        watchdog = frame.async_wait_for_selector('.box')
        detach_frame(page, 'frame1')
        expect { watchdog.wait }.to raise_error(Puppeteer::Error, 'Waiting for selector `.box` failed')
      end
    end

    it 'should survive cross-process navigation' do
      with_test_state do |page:, server:, **|
        box_found = false
        wait_for_selector = page.async_wait_for_selector('.box')
        page.goto(server.empty_page)
        expect(wait_for_selector.completed?).to eq(false)
        page.reload
        expect(wait_for_selector.completed?).to eq(false)
        page.goto("#{server.cross_process_prefix}/grid.html")
        wait_for_selector.wait
        box_found = true
        expect(box_found).to eq(true)
      end
    end

    it 'should wait for element to be visible (display)' do
      with_test_state do |page:, **|
        promise = page.async_wait_for_selector('div', visible: true)
        page.set_content('<div style="display: none">text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]').as_element
        sleep_ms(40)
        expect(promise.completed?).to eq(false)
        element.evaluate('e => e.style.removeProperty("display")')
        promise.wait
        element&.dispose
      end
    end

    it 'should wait for element to be visible (without DOM mutations)' do
      with_test_state do |page:, **|
        promise = page.async_wait_for_selector('div', visible: true)
        page.set_content(<<~HTML)
          <style>
            div {
              display: none;
            }
          </style>
          <div>text</div>
        HTML
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]').as_element
        sleep_ms(40)
        expect(promise.completed?).to eq(false)
        page.evaluate(<<~JAVASCRIPT)
        () => {
          const extraSheet = new CSSStyleSheet();
          extraSheet.replaceSync('div { display: block; }');
          document.adoptedStyleSheets = [...document.adoptedStyleSheets, extraSheet];
        }
        JAVASCRIPT
        promise.wait
        element&.dispose
      end
    end

    it 'should wait for element to be visible (visibility)' do
      with_test_state do |page:, **|
        promise = page.async_wait_for_selector('div', visible: true)
        page.set_content('<div style="visibility: hidden">text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]').as_element
        sleep_ms(40)
        expect(promise.completed?).to eq(false)
        element.evaluate('e => e.style.setProperty("visibility", "collapse")')
        sleep_ms(40)
        expect(promise.completed?).to eq(false)
        element.evaluate('e => e.style.removeProperty("visibility")')
        promise.wait
        element&.dispose
      end
    end

    it 'should wait for element to be visible (bounding box)' do
      with_test_state do |page:, **|
        promise = page.async_wait_for_selector('div', visible: true)
        page.set_content('<div style="width: 0">text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]').as_element
        sleep_ms(40)
        expect(promise.completed?).to eq(false)
        element.evaluate('e => { e.style.setProperty("height", "0"); e.style.removeProperty("width"); }')
        sleep_ms(40)
        expect(promise.completed?).to eq(false)
        element.evaluate('e => e.style.removeProperty("height")')
        promise.wait
        element&.dispose
      end
    end

    it 'should wait for element to be visible recursively' do
      with_test_state do |page:, **|
        promise = page.async_wait_for_selector('div#inner', visible: true)
        page.set_content(<<~HTML)
          <div style="display: none; visibility: hidden;">
            <div id="inner">hi</div>
          </div>
        HTML
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]').as_element
        sleep_ms(40)
        expect(promise.completed?).to eq(false)
        element.evaluate('e => e.style.removeProperty("display")')
        sleep_ms(40)
        expect(promise.completed?).to eq(false)
        element.evaluate('e => e.style.removeProperty("visibility")')
        promise.wait
        element&.dispose
      end
    end

    it 'should wait for element to be hidden (visibility)' do
      with_test_state do |page:, **|
        promise = page.async_wait_for_selector('div', hidden: true)
        page.set_content('<div style="display: block;">text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]').as_element
        element.evaluate('e => e.style.setProperty("visibility", "hidden")')
        promise.wait
        element&.dispose
      end
    end

    it 'should wait for element to be hidden (display)' do
      with_test_state do |page:, **|
        promise = page.async_wait_for_selector('div', hidden: true)
        page.set_content('<div style="display: block;">text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]').as_element
        element.evaluate('e => e.style.setProperty("display", "none")')
        promise.wait
        element&.dispose
      end
    end

    it 'should wait for element to be hidden (bounding box)' do
      with_test_state do |page:, **|
        promise = page.async_wait_for_selector('div', hidden: true)
        page.set_content('<div>text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]').as_element
        element.evaluate('e => e.style.setProperty("height", "0")')
        promise.wait
        element&.dispose
      end
    end

    it 'should wait for element to be hidden (removal)' do
      with_test_state do |page:, **|
        promise = page.async_wait_for_selector('div', hidden: true)
        page.set_content('<div>text</div>')
        element = page.evaluate_handle('() => document.getElementsByTagName("div")[0]').as_element
        element.evaluate('e => e.remove()')
        expect(promise.wait).to be_nil
        element&.dispose
      end
    end

    it 'should return null if waiting to hide non-existing element' do
      with_test_state do |page:, **|
        handle = page.wait_for_selector('non-existing', hidden: true)
        expect(handle).to be_nil
      end
    end

    it 'should respect timeout' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.wait_for_selector('div', timeout: 10)
        rescue => err
          error = err
        end
        expect(error).to be_a(Puppeteer::TimeoutError)
        expect(error.message).to eq('Waiting for selector `div` failed')
      end
    end

    it 'should have an error message specifically for awaiting an element to be hidden' do
      with_test_state do |page:, **|
        page.set_content('<div>text</div>')
        error = nil
        begin
          page.wait_for_selector('div', hidden: true, timeout: 10)
        rescue => err
          error = err
        end
        expect(error).to be_a(Puppeteer::TimeoutError)
        expect(error.message).to eq('Waiting for selector `div` failed')
      end
    end

    it 'should respond to node attribute mutation' do
      with_test_state do |page:, **|
        wait_for_selector = page.async_wait_for_selector('.zombo')
        page.set_content('<div class="notZombo"></div>')
        sleep_ms(40)
        expect(wait_for_selector.completed?).to eq(false)
        page.evaluate('() => { document.querySelector("div").className = "zombo"; }')
        wait_for_selector.wait
      end
    end

    it 'should return the element handle' do
      with_test_state do |page:, **|
        wait_for_selector = page.async_wait_for_selector('.zombo')
        page.set_content('<div class="zombo">anything</div>')
        handle = wait_for_selector.wait
        expect(handle).to be_a(Puppeteer::ElementHandle)
        expect(page.evaluate('(x) => x?.textContent', handle)).to eq('anything')
      end
    end

    it 'should have correct stack trace for timeout' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.wait_for_selector('.zombo', timeout: 10)
        rescue => err
          error = err
        end
        expect(error).to be_a(Puppeteer::TimeoutError)
        expect(error.message).to eq('Waiting for selector `.zombo` failed')
      end
    end

    describe 'xpath' do
      it 'should support some fancy xpath' do
        with_test_state do |page:, **|
          page.set_content('<p>red herring</p><p>hello  world  </p>')
          wait_for_selector = page.async_wait_for_selector('xpath/.//p[normalize-space(.)="hello world"]')
          handle = wait_for_selector.wait
          expect(page.evaluate('(x) => x?.textContent', handle)).to eq('hello  world  ')
        end
      end

      it 'should respect timeout' do
        with_test_state do |page:, **|
          error = nil
          begin
            page.wait_for_selector('xpath/.//div', timeout: 10)
          rescue => err
            error = err
          end
          expect(error).to be_a(Puppeteer::TimeoutError)
          expect(error.message).to eq('Waiting for selector `.//div` failed')
        end
      end

      it 'should run in specified frame' do
        with_test_state do |page:, server:, **|
          attach_frame(page, 'frame1', server.empty_page)
          attach_frame(page, 'frame2', server.empty_page)
          frame1 = page.frames[1]
          frame2 = page.frames[2]
          watchdog = frame2.async_wait_for_selector('xpath/.//div')
          frame1.evaluate(add_element_js, 'div')
          frame2.evaluate(add_element_js, 'div')
          handle = watchdog.wait
          expect(handle.frame).to eq(frame2)
        end
      end

      it 'should throw when frame is detached' do
        with_test_state do |page:, server:, **|
          attach_frame(page, 'frame1', server.empty_page)
          frame = page.frames[1]
          watchdog = frame.async_wait_for_selector('xpath/.//*[@class="box"]')
          detach_frame(page, 'frame1')
          expect { watchdog.wait }.to raise_error(Puppeteer::Error, 'Waiting for selector `.//*[@class="box"]` failed')
        end
      end

      it 'hidden should wait for display: none' do
        with_test_state do |page:, **|
          page.set_content('<div style="display: block;">text</div>')
          wait_for_selector = page.async_wait_for_selector('xpath/.//div', hidden: true)
          page.wait_for_selector('xpath/.//div')
          sleep_ms(40)
          expect(wait_for_selector.completed?).to eq(false)
          page.evaluate('() => document.querySelector("div")?.style.setProperty("display", "none")')
          wait_for_selector.wait
        end
      end

      it 'hidden should return null if the element is not found' do
        with_test_state do |page:, **|
          wait_for_selector = page.wait_for_selector('xpath/.//div', hidden: true)
          expect(wait_for_selector).to be_nil
        end
      end

      it 'hidden should return an empty element handle if the element is found' do
        with_test_state do |page:, **|
          page.set_content('<div style="display: none;">text</div>')
          wait_for_selector = page.wait_for_selector('xpath/.//div', hidden: true)
          expect(wait_for_selector).to be_a(Puppeteer::ElementHandle)
        end
      end

      it 'should return the element handle' do
        with_test_state do |page:, **|
          wait_for_selector = page.async_wait_for_selector('xpath/.//*[@class="zombo"]')
          page.set_content('<div class="zombo">anything</div>')
          handle = wait_for_selector.wait
          expect(page.evaluate('(x) => x?.textContent', handle)).to eq('anything')
        end
      end

      it 'should allow you to select a text node' do
        with_test_state do |page:, **|
          page.set_content('<div>some text</div>')
          text_handle = page.wait_for_selector('xpath/.//div/text()')
          expect(text_handle).to be_a(Puppeteer::ElementHandle)
          node_type = text_handle.property('nodeType').json_value
          expect(node_type).to eq(3)
        end
      end

      it 'should allow you to select an element with single slash' do
        with_test_state do |page:, **|
          page.set_content('<div>some text</div>')
          wait_for_selector = page.async_wait_for_selector('xpath/html/body/div')
          handle = wait_for_selector.wait
          expect(page.evaluate('(x) => x?.textContent', handle)).to eq('some text')
        end
      end
    end
  end

  describe 'protocol timeout' do
    it 'should error if underyling protocol command times out with raf polling' do
      with_browser(protocol_timeout: 3000) do |browser|
        page = browser.new_page
        begin
          error = nil
          begin
            page.wait_for_function('() => false', timeout: 6000)
          rescue => err
            error = err
          end
          expect(error).to be_a(Puppeteer::Error)
          expect(error.message).to eq('Waiting failed')
          expect(error.cause).to be_a(StandardError)
        ensure
          page.close unless page.closed?
        end
      end
    end
  end
end
