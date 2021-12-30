require 'spec_helper'

RSpec.describe 'AriaQueryHandler', skip: Puppeteer.env.firefox? do
  describe 'parseAreaSelector', puppeteer: :page do
    before {
      page.content = '<button id="btn" role="button"> Submit  button   and some spaces  </button>'
    }

    let(:button) { page.query_selector(selector) }
    subject(:found) { button.evaluate('(button) => button.id') == 'btn' }

    [
      'aria/Submit button and some spaces[role="button"]',
      "aria/Submit button and some spaces[role='button']",
      'aria/  Submit button and some spaces[role="button"]',
      'aria/Submit button and some spaces  [role="button"]',
      'aria/Submit  button   and  some  spaces   [  role  =  "button" ] ',
      'aria/[role="button"]Submit button and some spaces',
      'aria/Submit button [role="button"]and some spaces',
      'aria/[name="  Submit  button and some  spaces"][role="button"]',
      "aria/[name='  Submit  button and some  spaces'][role='button']",
      'aria/ignored[name="Submit  button and some  spaces"][role="button"]',
    ].each do |selector_value|
      context "selector=#{selector_value}" do
        let(:selector) { selector_value }

        it 'should find element' do
          expect(found).to eq(true)
        end
      end
    end
  end

  describe 'query_one', puppeteer: :page do
    it 'should find button by role' do
      page.content = '<div id="div"><button id="btn" role="button">Submit</button></div>'
      button = page.query_selector('aria/[role="button"]')
      expect(button.evaluate('(button) => button.id')).to eq('btn')
    end

    it 'should find button by name and role' do
      page.content = '<div id="div"><button id="btn" role="button">Submit</button></div>'
      button = page.query_selector('aria/Submit[role="button"]')
      expect(button.evaluate('(button) => button.id')).to eq('btn')
    end

    it 'should find first matching element' do
      page.content = 2.times.map { |i| "<div role=\"menu\" id=\"mnu#{i}\" aria-label=\"menu div\"></div>" }.join("")
      div = page.query_selector('aria/menu div')
      expect(div.evaluate('(div) => div.id')).to eq('mnu0')
    end

    it 'should find by name' do
      page.content = 2.times.map { |i| "<div role=\"menu\" id=\"mnu#{i}\" aria-label=\"menu-label#{i}\"></div>" }.join("")
      div = page.query_selector('aria/menu-label1')
      expect(div.evaluate('(div) => div.id')).to eq('mnu1')
      div = page.query_selector('aria/menu-label0')
      expect(div.evaluate('(div) => div.id')).to eq('mnu0')
    end
  end

  describe 'query_all' do
    it 'should find by name' do
      page.content = 2.times.map { |i| "<div role=\"menu\" id=\"mnu#{i}\" aria-label=\"menu div\"></div>" }.join("")
      div = page.query_selector_all('aria/menu div')
      expect(div[0].evaluate('(div) => div.id')).to eq('mnu0')
      expect(div[1].evaluate('(div) => div.id')).to eq('mnu1')
    end
  end

  describe 'query_all_array' do
    it 'eval_on_selector_all should handle many elements' do
      page.content = ''
      js = <<~JAVASCRIPT
      for (var i = 0; i <= 100; i++) {
          const button = document.createElement('button');
          button.textContent = i;
          document.body.appendChild(button);
      }
      JAVASCRIPT
      page.evaluate(js)
      sum = page.eval_on_selector_all('aria/[role="button"]', '(buttons) => buttons.reduce((acc, button) => acc + Number(button.textContent), 0)')
      expect(sum).to eq((0..100).sum)
    end
  end

  describe 'wait_for_selector (aria)', puppeteer: :page, sinatra: true do
    let(:add_element) { '(tag) => document.body.appendChild(document.createElement(tag))' }

    it 'should immediately resolve promise if node exists' do
      page.goto(server_empty_page)
      page.evaluate(add_element, 'button')
      Timeout.timeout(1) { page.wait_for_selector('aria/[role="button"]') }
    end

    it 'should persist query handler bindings across reloads' do
      page.goto(server_empty_page)
      page.evaluate(add_element, 'button')
      Timeout.timeout(1) { page.wait_for_selector('aria/[role="button"]') }
      page.reload
      page.evaluate(add_element, 'button')
      Timeout.timeout(1) { page.wait_for_selector('aria/[role="button"]') }
    end

    it 'should persist query handler bindings across navigations' do
      # Reset page but make sure that execution context ids start with 1.
      page.goto('data:text/html,')
      page.goto(server_empty_page)
      page.evaluate(add_element, 'button')
      Timeout.timeout(1) { page.wait_for_selector('aria/[role="button"]') }

      # Reset page but again make sure that execution context ids start with 1.
      page.goto('data:text/html,')
      page.goto(server_empty_page)
      page.evaluate(add_element, 'button')
      Timeout.timeout(1) { page.wait_for_selector('aria/[role="button"]') }
    end

    it 'should work independently of `exposeFunction`' do
      page.goto(server_empty_page)
      page.expose_function('ariaQuerySelector', -> (a, b) { a + b })
      page.evaluate(add_element, 'button')
      page.wait_for_selector('aria/[role="button"]')
      result = page.evaluate('globalThis.ariaQuerySelector(2,8)')
      expect(result).to eq(10)
    end

    # it('should work with removed MutationObserver', async () => {
    #   const { page } = getTestState();

    #   await page.evaluate(() => delete window.MutationObserver);
    #   const [handle] = await Promise.all([
    #     page.waitForSelector('aria/anything'),
    #     page.setContent(`<h1>anything</h1>`),
    #   ]);
    #   expect(
    #     await page.evaluate((x: HTMLElement) => x.textContent, handle)
    #   ).toBe('anything');
    # });

    # it('should resolve promise when node is added', async () => {
    #   const { page, server } = getTestState();

    #   await page.goto(server.EMPTY_PAGE);
    #   const frame = page.mainFrame();
    #   const watchdog = frame.waitForSelector('aria/[role="heading"]');
    #   await frame.evaluate(addElement, 'br');
    #   await frame.evaluate(addElement, 'h1');
    #   const elementHandle = await watchdog;
    #   const tagName = await elementHandle
    #     .getProperty('tagName')
    #     .then((element) => element.jsonValue());
    #   expect(tagName).toBe('H1');
    # });

    # it('should work when node is added through innerHTML', async () => {
    #   const { page, server } = getTestState();

    #   await page.goto(server.EMPTY_PAGE);
    #   const watchdog = page.waitForSelector('aria/name');
    #   await page.evaluate(addElement, 'span');
    #   await page.evaluate(
    #     () =>
    #       (document.querySelector('span').innerHTML =
    #         '<h3><div aria-label="name"></div></h3>')
    #   );
    #   await watchdog;
    # });

    # it('Page.waitForSelector is shortcut for main frame', async () => {
    #   const { page, server } = getTestState();

    #   await page.goto(server.EMPTY_PAGE);
    #   await utils.attachFrame(page, 'frame1', server.EMPTY_PAGE);
    #   const otherFrame = page.frames()[1];
    #   const watchdog = page.waitForSelector('aria/[role="button"]');
    #   await otherFrame.evaluate(addElement, 'button');
    #   await page.evaluate(addElement, 'button');
    #   const elementHandle = await watchdog;
    #   expect(elementHandle.executionContext().frame()).toBe(page.mainFrame());
    # });

    # it('should run in specified frame', async () => {
    #   const { page, server } = getTestState();

    #   await utils.attachFrame(page, 'frame1', server.EMPTY_PAGE);
    #   await utils.attachFrame(page, 'frame2', server.EMPTY_PAGE);
    #   const frame1 = page.frames()[1];
    #   const frame2 = page.frames()[2];
    #   const waitForSelectorPromise = frame2.waitForSelector(
    #     'aria/[role="button"]'
    #   );
    #   await frame1.evaluate(addElement, 'button');
    #   await frame2.evaluate(addElement, 'button');
    #   const elementHandle = await waitForSelectorPromise;
    #   expect(elementHandle.executionContext().frame()).toBe(frame2);
    # });

    # it('should throw when frame is detached', async () => {
    #   const { page, server } = getTestState();

    #   await utils.attachFrame(page, 'frame1', server.EMPTY_PAGE);
    #   const frame = page.frames()[1];
    #   let waitError = null;
    #   const waitPromise = frame
    #     .waitForSelector('aria/does-not-exist')
    #     .catch((error) => (waitError = error));
    #   await utils.detachFrame(page, 'frame1');
    #   await waitPromise;
    #   expect(waitError).toBeTruthy();
    #   expect(waitError.message).toContain(
    #     'waitForFunction failed: frame got detached.'
    #   );
    # });

    # it('should survive cross-process navigation', async () => {
    #   const { page, server } = getTestState();

    #   let imgFound = false;
    #   const waitForSelector = page
    #     .waitForSelector('aria/[role="img"]')
    #     .then(() => (imgFound = true));
    #   await page.goto(server.EMPTY_PAGE);
    #   expect(imgFound).toBe(false);
    #   await page.reload();
    #   expect(imgFound).toBe(false);
    #   await page.goto(server.CROSS_PROCESS_PREFIX + '/grid.html');
    #   await waitForSelector;
    #   expect(imgFound).toBe(true);
    # });

    it 'should wait for visible' do
      div_found = false
      wait_for_selector_promise = page.async_wait_for_selector('aria/name', visible: true).then { div_found = true }
      page.content = "<div aria-label='name' style='display: none; visibility: hidden;'>1</div>"

      expect(div_found).to eq(false)
      page.evaluate(<<~JAVASCRIPT)
      () => document.querySelector('div').style.removeProperty('display')
      JAVASCRIPT
      expect(div_found).to eq(false)
      page.evaluate(<<~JAVASCRIPT)
      () => document.querySelector('div').style.removeProperty('visibility')
      JAVASCRIPT
      await wait_for_selector_promise
      expect(div_found).to eq(true)
    end

    # it('should wait for visible recursively', async () => {
    #   const { page } = getTestState();

    #   let divVisible = false;
    #   const waitForSelector = page
    #     .waitForSelector('aria/inner', { visible: true })
    #     .then(() => (divVisible = true));
    #   await page.setContent(
    #     `<div style='display: none; visibility: hidden;'><div aria-label="inner">hi</div></div>`
    #   );
    #   expect(divVisible).toBe(false);
    #   await page.evaluate(() =>
    #     document.querySelector('div').style.removeProperty('display')
    #   );
    #   expect(divVisible).toBe(false);
    #   await page.evaluate(() =>
    #     document.querySelector('div').style.removeProperty('visibility')
    #   );
    #   expect(await waitForSelector).toBe(true);
    #   expect(divVisible).toBe(true);
    # });

    # it('hidden should wait for visibility: hidden', async () => {
    #   const { page } = getTestState();

    #   let divHidden = false;
    #   await page.setContent(
    #     `<div role='button' style='display: block;'></div>`
    #   );
    #   const waitForSelector = page
    #     .waitForSelector('aria/[role="button"]', { hidden: true })
    #     .then(() => (divHidden = true));
    #   await page.waitForSelector('aria/[role="button"]'); // do a round trip
    #   expect(divHidden).toBe(false);
    #   await page.evaluate(() =>
    #     document.querySelector('div').style.setProperty('visibility', 'hidden')
    #   );
    #   expect(await waitForSelector).toBe(true);
    #   expect(divHidden).toBe(true);
    # });

    # it('hidden should wait for display: none', async () => {
    #   const { page } = getTestState();

    #   let divHidden = false;
    #   await page.setContent(`<div role='main' style='display: block;'></div>`);
    #   const waitForSelector = page
    #     .waitForSelector('aria/[role="main"]', { hidden: true })
    #     .then(() => (divHidden = true));
    #   await page.waitForSelector('aria/[role="main"]'); // do a round trip
    #   expect(divHidden).toBe(false);
    #   await page.evaluate(() =>
    #     document.querySelector('div').style.setProperty('display', 'none')
    #   );
    #   expect(await waitForSelector).toBe(true);
    #   expect(divHidden).toBe(true);
    # });

    # it('hidden should wait for removal', async () => {
    #   const { page } = getTestState();

    #   await page.setContent(`<div role='main'></div>`);
    #   let divRemoved = false;
    #   const waitForSelector = page
    #     .waitForSelector('aria/[role="main"]', { hidden: true })
    #     .then(() => (divRemoved = true));
    #   await page.waitForSelector('aria/[role="main"]'); // do a round trip
    #   expect(divRemoved).toBe(false);
    #   await page.evaluate(() => document.querySelector('div').remove());
    #   expect(await waitForSelector).toBe(true);
    #   expect(divRemoved).toBe(true);
    # });

    # it('should return null if waiting to hide non-existing element', async () => {
    #   const { page } = getTestState();

    #   const handle = await page.waitForSelector('aria/non-existing', {
    #     hidden: true,
    #   });
    #   expect(handle).toBe(null);
    # });

    # it('should respect timeout', async () => {
    #   const { page, puppeteer } = getTestState();

    #   let error = null;
    #   await page
    #     .waitForSelector('aria/[role="button"]', { timeout: 10 })
    #     .catch((error_) => (error = error_));
    #   expect(error).toBeTruthy();
    #   expect(error.message).toContain(
    #     'waiting for selector `[role="button"]` failed: timeout'
    #   );
    #   expect(error).toBeInstanceOf(puppeteer.errors.TimeoutError);
    # });

    # it('should have an error message specifically for awaiting an element to be hidden', async () => {
    #   const { page } = getTestState();

    #   await page.setContent(`<div role='main'></div>`);
    #   let error = null;
    #   await page
    #     .waitForSelector('aria/[role="main"]', { hidden: true, timeout: 10 })
    #     .catch((error_) => (error = error_));
    #   expect(error).toBeTruthy();
    #   expect(error.message).toContain(
    #     'waiting for selector `[role="main"]` to be hidden failed: timeout'
    #   );
    # });

    # it('should respond to node attribute mutation', async () => {
    #   const { page } = getTestState();

    #   let divFound = false;
    #   const waitForSelector = page
    #     .waitForSelector('aria/zombo')
    #     .then(() => (divFound = true));
    #   await page.setContent(`<div aria-label='notZombo'></div>`);
    #   expect(divFound).toBe(false);
    #   await page.evaluate(() =>
    #     document.querySelector('div').setAttribute('aria-label', 'zombo')
    #   );
    #   expect(await waitForSelector).toBe(true);
    # });

    it 'should return the element handle' do
      promise = page.async_wait_for_selector('aria/zombo')
      page.content = "<div aria-label='zombo'>anything</div>"
      result = await promise
      expect(result).to be_a(Puppeteer::ElementHandle)
      expect(page.evaluate('(x) => x.textContent', result)).to eq('anything')
    end

    # it('should have correct stack trace for timeout', async () => {
    #   const { page } = getTestState();

    #   let error;
    #   await page
    #     .waitForSelector('aria/zombo', { timeout: 10 })
    #     .catch((error_) => (error = error_));
    #   expect(error.stack).toContain('waiting for selector `zombo` failed');
    # });
  end

  # describe('queryOne (Chromium web test)', async () => {
  #   beforeEach(async () => {
  #     const { page } = getTestState();
  #     await page.setContent(
  #       `
  #         <h2 id="shown">title</h2>
  #         <h2 id="hidden" aria-hidden="true">title</h2>
  #         <div id="node1" aria-labeledby="node2"></div>
  #         <div id="node2" aria-label="bar"></div>
  #         <div id="node3" aria-label="foo"></div>
  #         <div id="node4" class="container">
  #         <div id="node5" role="button" aria-label="foo"></div>
  #         <div id="node6" role="button" aria-label="foo"></div>
  #         <!-- Accessible name not available when element is hidden -->
  #         <div id="node7" hidden role="button" aria-label="foo"></div>
  #         <div id="node8" role="button" aria-label="bar"></div>
  #         </div>
  #         <button id="node10">text content</button>
  #         <h1 id="node11">text content</h1>
  #         <!-- Accessible name not available when role is "presentation" -->
  #         <h1 id="node12" role="presentation">text content</h1>
  #         <!-- Elements inside shadow dom should be found -->
  #         <script>
  #         const div = document.createElement('div');
  #         const shadowRoot = div.attachShadow({mode: 'open'});
  #         const h1 = document.createElement('h1');
  #         h1.textContent = 'text content';
  #         h1.id = 'node13';
  #         shadowRoot.appendChild(h1);
  #         document.documentElement.appendChild(div);
  #         </script>
  #         <img id="node20" src="" alt="Accessible Name">
  #         <input id="node21" type="submit" value="Accessible Name">
  #         <label id="node22" for="node23">Accessible Name</label>
  #         <!-- Accessible name for the <input> is "Accessible Name" -->
  #         <input id="node23">
  #         <div id="node24" title="Accessible Name"></div>
  #         <div role="treeitem" id="node30">
  #         <div role="treeitem" id="node31">
  #         <div role="treeitem" id="node32">item1</div>
  #         <div role="treeitem" id="node33">item2</div>
  #         </div>
  #         <div role="treeitem" id="node34">item3</div>
  #         </div>
  #         <!-- Accessible name for the <div> is "item1 item2 item3" -->
  #         <div aria-describedby="node30"></div>
  #         `
  #     );
  #   });
  #   const getIds = async (elements: ElementHandle[]) =>
  #     Promise.all(
  #       elements.map((element) =>
  #         element.evaluate((element: Element) => element.id)
  #       )
  #     );
  #   it('should find by name "foo"', async () => {
  #     const { page } = getTestState();
  #     const found = await page.$$('aria/foo');
  #     const ids = await getIds(found);
  #     expect(ids).toEqual(['node3', 'node5', 'node6']);
  #   });
  #   it('should find by name "bar"', async () => {
  #     const { page } = getTestState();
  #     const found = await page.$$('aria/bar');
  #     const ids = await getIds(found);
  #     expect(ids).toEqual(['node1', 'node2', 'node8']);
  #   });
  #   it('should find treeitem by name', async () => {
  #     const { page } = getTestState();
  #     const found = await page.$$('aria/item1 item2 item3');
  #     const ids = await getIds(found);
  #     expect(ids).toEqual(['node30']);
  #   });
  #   it('should find by role "button"', async () => {
  #     const { page } = getTestState();
  #     const found = await page.$$('aria/[role="button"]');
  #     const ids = await getIds(found);
  #     expect(ids).toEqual(['node5', 'node6', 'node8', 'node10', 'node21']);
  #   });
  #   it('should find by role "heading"', async () => {
  #     const { page } = getTestState();
  #     const found = await page.$$('aria/[role="heading"]');
  #     const ids = await getIds(found);
  #     expect(ids).toEqual(['shown', 'node11', 'node13']);
  #   });
  #   it('should not find ignored', async () => {
  #     const { page } = getTestState();
  #     const found = await page.$$('aria/title');
  #     const ids = await getIds(found);
  #     expect(ids).toEqual(['shown']);
  #   });
  # });
end
