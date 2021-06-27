require 'spec_helper'

RSpec.describe Puppeteer::WaitTask do
  describe 'Page.waitFor', sinatra: true do
    it 'should wait for selector' do
      found = false
      wait_for = page.async_wait_for_selector('div').then { found = true }

      page.goto(server_empty_page)
      expect(found).to eq(false)

      page.goto("#{server_prefix}/grid.html")
      await wait_for
      expect(found).to eq(true)
    end

    it 'should wait for an xpath' do
      found = false
      wait_for = page.async_wait_for_xpath('//div').then { found = true }

      page.goto(server_empty_page)
      expect(found).to eq(false)

      page.goto("#{server_prefix}/grid.html")
      await wait_for
      expect(found).to eq(true)
    end

    it 'should timeout' do
      start_time = Time.now
      page.wait_for_timeout(42)
      end_time = Time.now
      expect(end_time - start_time).to be >= 0.021
    end

    it 'should work with multiline body' do
      result = page.wait_for_function(<<~JAVASCRIPT)

      () => true

      JAVASCRIPT
      expect(result.json_value).to eq(true)
    end

    it 'should wait for predicate' do
      Timeout.timeout(1) do # assert not timeout.
        page.wait_for_function('() => window.innerWidth < 100') do
          page.viewport = Puppeteer::Viewport.new(width: 10, height: 10)
        end
      end
    end

    it 'should wait for predicate with arguments' do
      Timeout.timeout(1) do # assert not timeout.
        page.wait_for_function('(arg1, arg2) => arg1 !== arg2', args: [1, 2])
      end
    end
  end

  describe 'Frame.waitForSelector' do
    include Utils::AttachFrame
    include Utils::DetachFrame

    let(:add_element) { "(tag) => document.body.appendChild(document.createElement(tag))" }

    it 'should immediately resolve promise if node exists', sinatra: true do
      page.goto(server_empty_page)
      frame = page.main_frame
      Timeout.timeout(1) { frame.wait_for_selector('*') }
      frame.evaluate(add_element, 'div')
      Timeout.timeout(1) { frame.wait_for_selector('div') }
    end

    it_fails_firefox 'should work with removed MutationObserver' do
      page.evaluate("() => delete window.MutationObserver")


      handle = page.wait_for_selector('.zombo') do
        sleep 0.1
        page.content = "<div class='zombo'>anything</div>"
      end
      expect(page.evaluate("(x) => x.textContent", handle)).to eq('anything')
    end

    it 'should resolve promise when node is added' do
      frame = page.main_frame

      watchdog = frame.async_wait_for_selector('div')
      frame.evaluate(add_element, 'br')
      frame.evaluate(add_element, 'div')
      handle = Timeout.timeout(1) { await watchdog }
      tag_name = handle.property('tagName').json_value
      expect(tag_name).to eq('DIV')
    end

    it 'should work when node is added through innerHTML', sinatra: true do
      page.goto(server_empty_page)
      watchdog = page.async_wait_for_selector('h3 div')
      page.evaluate(add_element, 'span')
      page.evaluate("() => (document.querySelector('span').innerHTML = '<h3><div></div></h3>')")
      Timeout.timeout(1) { await watchdog }
    end

    it 'Page.waitForSelector is shortcut for main frame', sinatra: true do
      page.goto(server_empty_page)
      attach_frame(page, 'frame1', server_empty_page)
      other_frame = page.frames.last
      watchdog = page.async_wait_for_selector('div')
      other_frame.evaluate(add_element, 'div')
      page.evaluate(add_element, 'div')
      handle = await watchdog
      expect(handle.execution_context.frame).to eq(page.main_frame)
    end

    it 'should run in specified frame', sinatra: true do
      page.goto(server_empty_page)
      attach_frame(page, 'frame1', server_empty_page)
      attach_frame(page, 'frame2', server_empty_page)
      frame1 = page.frames[1]
      frame2 = page.frames[2]
      promise = frame2.async_wait_for_selector('div')
      frame1.evaluate(add_element, 'div')
      frame2.evaluate(add_element, 'div')
      handle = await promise
      expect(handle.execution_context.frame).to eq(frame2)
    end

    it 'should throw when frame is detached', sinatra: true do
      page.goto(server_empty_page)
      attach_frame(page, 'frame1', server_empty_page)
      frame = page.frames.last
      promise = frame.async_wait_for_selector('.box')
      detach_frame(page, 'frame1')
      expect { await promise }.to raise_error(/waitForFunction failed: frame got detached./)
    end
    #   it('should survive cross-process navigation', async () => {
    #     const { page, server } = getTestState();

    #     let boxFound = false;
    #     const waitForSelector = page
    #       .waitForSelector('.box')
    #       .then(() => (boxFound = true));
    #     await page.goto(server.EMPTY_PAGE);
    #     expect(boxFound).toBe(false);
    #     await page.reload();
    #     expect(boxFound).toBe(false);
    #     await page.goto(server.CROSS_PROCESS_PREFIX + '/grid.html');
    #     await waitForSelector;
    #     expect(boxFound).toBe(true);
    #   });
    it 'should wait for visible' do
      promise = page.async_wait_for_selector('div', visible: true)
      page.content = "<div style='display: none; visibility: hidden;'>1</div>"
      sleep 1
      expect(promise).not_to be_fulfilled

      page.evaluate("() => document.querySelector('div').style.removeProperty('display')")
      sleep 1
      expect(promise).not_to be_fulfilled

      page.evaluate("() => document.querySelector('div').style.removeProperty('visibility')")
      Timeout.timeout(1) { await promise }
    end
    #   it('should wait for visible recursively', async () => {
    #     const { page } = getTestState();

    #     let divVisible = false;
    #     const waitForSelector = page
    #       .waitForSelector('div#inner', { visible: true })
    #       .then(() => (divVisible = true));
    #     await page.setContent(
    #       `<div style='display: none; visibility: hidden;'><div id="inner">hi</div></div>`
    #     );
    #     expect(divVisible).toBe(false);
    #     await page.evaluate(() =>
    #       document.querySelector('div').style.removeProperty('display')
    #     );
    #     expect(divVisible).toBe(false);
    #     await page.evaluate(() =>
    #       document.querySelector('div').style.removeProperty('visibility')
    #     );
    #     expect(await waitForSelector).toBe(true);
    #     expect(divVisible).toBe(true);
    #   });
    #   it('hidden should wait for visibility: hidden', async () => {
    #     const { page } = getTestState();

    #     let divHidden = false;
    #     await page.setContent(`<div style='display: block;'></div>`);
    #     const waitForSelector = page
    #       .waitForSelector('div', { hidden: true })
    #       .then(() => (divHidden = true));
    #     await page.waitForSelector('div'); // do a round trip
    #     expect(divHidden).toBe(false);
    #     await page.evaluate(() =>
    #       document.querySelector('div').style.setProperty('visibility', 'hidden')
    #     );
    #     expect(await waitForSelector).toBe(true);
    #     expect(divHidden).toBe(true);
    #   });
    it 'hidden should wait for display: none' do
      page.content = "<div style='display: block;'></div>"
      promise = page.async_wait_for_selector('div', hidden: true)

      Timeout.timeout(1) { page.wait_for_selector('div') } # do a round trip
      expect(promise).not_to be_fulfilled

      page.evaluate("() => document.querySelector('div').style.setProperty('display', 'none')")
      Timeout.timeout(1) { await promise }
    end

    it 'hidden should wait for removal' do
      page.content = '<div></div>'
      promise = page.async_wait_for_selector('div', hidden: true)
      page.evaluate("() => document.querySelector('div').remove()")
      Timeout.timeout(1) { await promise }
    end

    it 'should return null if waiting to hide non-existing element' do
      handle = page.wait_for_selector('non-existing', hidden: true)
      expect(handle).to be_nil
    end

    it 'should respect timeout' do
      page.content = '<span></span>'
      expect {
        page.wait_for_selector('div', timeout: 10)
      }.to raise_error(Puppeteer::TimeoutError)
    end
    #   it('should have an error message specifically for awaiting an element to be hidden', async () => {
    #     const { page } = getTestState();

    #     await page.setContent(`<div></div>`);
    #     let error = null;
    #     await page
    #       .waitForSelector('div', { hidden: true, timeout: 10 })
    #       .catch((error_) => (error = error_));
    #     expect(error).toBeTruthy();
    #     expect(error.message).toContain(
    #       'waiting for selector `div` to be hidden failed: timeout'
    #     );
    #   });

    #   it('should respond to node attribute mutation', async () => {
    #     const { page } = getTestState();

    #     let divFound = false;
    #     const waitForSelector = page
    #       .waitForSelector('.zombo')
    #       .then(() => (divFound = true));
    #     await page.setContent(`<div class='notZombo'></div>`);
    #     expect(divFound).toBe(false);
    #     await page.evaluate(
    #       () => (document.querySelector('div').className = 'zombo')
    #     );
    #     expect(await waitForSelector).toBe(true);
    #   });
    it 'should return the element handle' do
      promise = page.async_wait_for_selector('.zombo')
      page.content = "<div class='zombo'>anything</div>"
      handle = await promise
      expect(handle).to be_a(Puppeteer::ElementHandle)
      expect(page.evaluate('(x) => x.textContent', handle)).to eq('anything')
    end
    #   it('should have correct stack trace for timeout', async () => {
    #     const { page } = getTestState();

    #     let error;
    #     await page
    #       .waitForSelector('.zombo', { timeout: 10 })
    #       .catch((error_) => (error = error_));
    #     expect(error.stack).toContain('waiting for selector `.zombo` failed');
    #     // The extension is ts here as Mocha maps back via sourcemaps.
    #     expect(error.stack).toContain('waittask.spec.ts');
    #   });
    # });
  end
end
