require 'spec_helper'

RSpec.describe Puppeteer::ElementHandle do
  describe '#bounding_box' do
    it 'should work', sinatra: true, pending: Puppeteer.env.ci? && Puppeteer.env.firefox? do
      page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
      page.goto("#{server_prefix}/grid.html")

      element_handle = page.query_selector('.box:nth-of-type(13)')
      box = element_handle.bounding_box
      expect(box.x).to eq(100)
      expect(box.y).to eq(50)
      expect(box.width).to eq(50)
      expect(box.height).to eq(50)
    end


    it 'should handle nested frames', sinatra: true, pending: Puppeteer.env.ci? && Puppeteer.env.firefox? do
      page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
      page.goto("#{server_prefix}/frames/nested-frames.html")

      nested_frame = page.frames[1].child_frames[1]
      element_handle = nested_frame.query_selector('div')
      box = element_handle.bounding_box

      expect(box.x).to eq(28)
      expect(box.y).to eq(182)
      expect(box.width).to eq(264)
      expect(box.height).to eq(18)
    end

    it 'should return null for invisible elements' do
      page.content = '<div style="display:none">hi</div>'
      element = page.query_selector('div')
      expect(element.bounding_box).to be_nil
    end

    it 'should force a layout' do
      page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
      page.content = '<div style="width: 100px; height: 100px">hello</div>'

      element_handle = page.query_selector('div')
      page.evaluate("(element) => element.style.height = '200px'", element_handle)
      box = element_handle.bounding_box
      expect(box.width).to eq(100)
      expect(box.height).to eq(200)
    end

    it 'should work with SVG nodes' do
      page.content = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="500" height="500">
          <rect id="theRect" x="30" y="50" width="200" height="300"></rect>
        </svg>
      SVG
      element = page.query_selector('#therect')
      pptr_bounding_box = element.bounding_box

      js = <<~JAVASCRIPT
      (e) => {
        const rect = e.getBoundingClientRect();
        return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
      }
      JAVASCRIPT
      web_bounding_box = page.evaluate(js, element)

      expect(pptr_bounding_box.x).to eq(web_bounding_box['x'])
      expect(pptr_bounding_box.y).to eq(web_bounding_box['y'])
      expect(pptr_bounding_box.width).to eq(web_bounding_box['width'])
      expect(pptr_bounding_box.height).to eq(web_bounding_box['height'])
    end
  end

  describe '#box_model' do
    include Utils::AttachFrame

    it 'should work', sinatra: true do
      page.goto("#{server_prefix}/resetcss.html")

      # Step 1: Add Frame and position it absolutely.
      attach_frame(page, 'frame1', "#{server_prefix}/resetcss.html")
      js = <<~JAVASCRIPT
      () => {
        const frame = document.querySelector('#frame1');
        frame.style.position = 'absolute';
        frame.style.left = '1px';
        frame.style.top = '2px';
      }
      JAVASCRIPT
      page.evaluate(js)

      # Step 2: Add div and position it absolutely inside frame.
      frame = page.frames[1]
      js = <<~JAVASCRIPT
        () => {
          const div = document.createElement('div');
          document.body.appendChild(div);
          div.style.boxSizing = 'border-box';
          div.style.position = 'absolute';
          div.style.borderLeft = '1px solid black';
          div.style.paddingLeft = '2px';
          div.style.marginLeft = '3px';
          div.style.left = '4px';
          div.style.top = '5px';
          div.style.width = '6px';
          div.style.height = '7px';
          return div;
        }
      JAVASCRIPT

      div_handle = frame.evaluate_handle(js).as_element

      #  Step 3: query div's boxModel and assert box values.
      box = div_handle.box_model
      expect(box.width).to eq(6)
      expect(box.height).to eq(7)
      expect(box.margin[0].x).to eq(1 + 4) # frame.left + div.left
      expect(box.margin[0].y).to eq(2 + 5)
      expect(box.border[0].x).to eq(1 + 4 + 3) # frame.left + div.left + div.margin-left
      expect(box.border[0].y).to eq(2 + 5)
      expect(box.padding[0].x).to eq(1 + 4 + 3 + 1) # frame.left + div.left + div.marginLeft + div.borderLeft
      expect(box.padding[0].y).to eq(2 + 5)
      expect(box.content[0].x).to eq(1 + 4 + 3 + 1 + 2) # frame.left + div.left + div.marginLeft + div.borderLeft + dif.paddingLeft
      expect(box.content[0].y).to eq(2 + 5)
    end

    it 'should return null for invisible elements' do
      page.content = '<div style="display:none">hi</div>'
      element = page.query_selector('div')
      expect(element.box_model).to be_nil
    end
  end

  describe '#contentFrame' do
    include Utils::AttachFrame

    it 'should work', sinatra: true do
      page.goto(server_empty_page)
      attach_frame(page, 'frame1', server_empty_page)
      element_handle = page.query_selector('#frame1')
      frame = element_handle.content_frame
      expect(frame).to eq(page.frames[1])
    end
  end

  describe '#click' do
    it 'should work', sinatra: true do
      page.goto("#{server_prefix}/input/button.html")
      page.query_selector('button').click
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end

    it 'should work for Shadow DOM v1', sinatra: true do
      page.goto("#{server_prefix}/shadow.html")
      button_handle = page.evaluate_handle('() => button')
      button_handle.click
      expect(page.evaluate('() => clicked')).to eq(true)
    end

    it 'should throw for TextNodes', sinatra: true do
      page.goto("#{server_prefix}/input/button.html")
      button_text_node = page.evaluate_handle("() => document.querySelector('button').firstChild")
      expect { button_text_node.click }.to raise_error(/Node is not of type HTMLElement/)
    end

    it 'should throw for detached nodes', sinatra: true do
      page.goto("#{server_prefix}/input/button.html")
      button = page.query_selector('button')
      page.evaluate('(button) => button.remove()', button)
      expect { button.click }.to raise_error(/Node is detached from document/)
    end

    it 'should throw for hidden nodes', sinatra: true do
      page.goto("#{server_prefix}/input/button.html")
      button = page.query_selector('button')
      page.evaluate("(button) => (button.style.display = 'none')", button)
      expect { button.click }.to raise_error(/Node is either not visible or not an HTMLElement/)
    end

    it 'should throw for recursively hidden nodes', sinatra: true do
      page.goto("#{server_prefix}/input/button.html")
      button = page.query_selector('button')
      page.evaluate("(button) => (button.parentElement.style.display = 'none')", button)
      expect { button.click }.to raise_error(/Node is either not visible or not an HTMLElement/)
    end

    it 'should throw for <br> elements' do
      page.content = 'hello<br>goodbye'
      br = page.query_selector('br')
      expect { br.click }.to raise_error(/Node is either not visible or not an HTMLElement/)
    end
  end

  describe '#hover' do
    it 'should work', sinatra: true do
      page.goto("#{server_prefix}/input/scrollable.html")
      button = page.query_selector('#button-6')
      button.hover
      expect(page.evaluate("() => document.querySelector('button:hover').id")).to eq('button-6')
    end
  end

  describe '#intersecting_viewport?' do
    it 'should work', sinatra: true do
      page.goto("#{server_prefix}/offscreenbuttons.html")

      10.times do |i|
        button = page.query_selector("#btn#{i}")
        # All but last button are visible.
        expect(button.intersecting_viewport?).to eq(true)
      end
      button = page.query_selector("#btn10")
      expect(button.intersecting_viewport?).to eq(false)
    end
  end

  # describe('Custom queries', function () {
  #   this.afterEach(() => {
  #     const { puppeteer } = getTestState();
  #     puppeteer.__experimental_clearQueryHandlers();
  #   });
  #   it('should register and unregister', async () => {
  #     const { page, puppeteer } = getTestState();
  #     await page.setContent('<div id="not-foo"></div><div id="foo"></div>');

  #     // Register.
  #     puppeteer.__experimental_registerCustomQueryHandler('getById', {
  #       queryOne: (element, selector) =>
  #         document.querySelector(`[id="${selector}"]`),
  #     });
  #     const element = await page.$('getById/foo');
  #     expect(
  #       await page.evaluate<(element: HTMLElement) => string>(
  #         (element) => element.id,
  #         element
  #       )
  #     ).toBe('foo');

  #     // Unregister.
  #     puppeteer.__experimental_unregisterCustomQueryHandler('getById');
  #     try {
  #       await page.$('getById/foo');
  #       throw new Error('Custom query handler name not set - throw expected');
  #     } catch (error) {
  #       expect(error).toStrictEqual(
  #         new Error(
  #           'Query set to use "getById", but no query handler of that name was found'
  #         )
  #       );
  #     }
  #   });
  #   it('should throw with invalid query names', () => {
  #     try {
  #       const { puppeteer } = getTestState();
  #       puppeteer.__experimental_registerCustomQueryHandler(
  #         '1/2/3',
  #         // @ts-expect-error
  #         () => {}
  #       );
  #       throw new Error(
  #         'Custom query handler name was invalid - throw expected'
  #       );
  #     } catch (error) {
  #       expect(error).toStrictEqual(
  #         new Error('Custom query handler names may only contain [a-zA-Z]')
  #       );
  #     }
  #   });
  #   it('should work for multiple elements', async () => {
  #     const { page, puppeteer } = getTestState();
  #     await page.setContent(
  #       '<div id="not-foo"></div><div class="foo">Foo1</div><div class="foo baz">Foo2</div>'
  #     );
  #     puppeteer.__experimental_registerCustomQueryHandler('getByClass', {
  #       queryAll: (element, selector) =>
  #         document.querySelectorAll(`.${selector}`),
  #     });
  #     const elements = await page.$$('getByClass/foo');
  #     const classNames = await Promise.all(
  #       elements.map(
  #         async (element) =>
  #           await page.evaluate<(element: HTMLElement) => string>(
  #             (element) => element.className,
  #             element
  #           )
  #       )
  #     );

  #     expect(classNames).toStrictEqual(['foo', 'foo baz']);
  #   });
  #   it('should eval correctly', async () => {
  #     const { page, puppeteer } = getTestState();
  #     await page.setContent(
  #       '<div id="not-foo"></div><div class="foo">Foo1</div><div class="foo baz">Foo2</div>'
  #     );
  #     puppeteer.__experimental_registerCustomQueryHandler('getByClass', {
  #       queryAll: (element, selector) =>
  #         document.querySelectorAll(`.${selector}`),
  #     });
  #     const elements = await page.$$eval(
  #       'getByClass/foo',
  #       (divs) => divs.length
  #     );

  #     expect(elements).toBe(2);
  #   });
  #   it('should wait correctly with waitForSelector', async () => {
  #     const { page, puppeteer } = getTestState();
  #     puppeteer.__experimental_registerCustomQueryHandler('getByClass', {
  #       queryOne: (element, selector) => element.querySelector(`.${selector}`),
  #     });
  #     const waitFor = page.waitForSelector('getByClass/foo');

  #     // Set the page content after the waitFor has been started.
  #     await page.setContent(
  #       '<div id="not-foo"></div><div class="foo">Foo1</div>'
  #     );
  #     const element = await waitFor;

  #     expect(element).toBeDefined();
  #   });

  #   it('should wait correctly with waitFor', async () => {
  #     /* page.waitFor is deprecated so we silence the warning to avoid test noise */
  #     sinon.stub(console, 'warn').callsFake(() => {});
  #     const { page, puppeteer } = getTestState();
  #     puppeteer.__experimental_registerCustomQueryHandler('getByClass', {
  #       queryOne: (element, selector) => element.querySelector(`.${selector}`),
  #     });
  #     const waitFor = page.waitFor('getByClass/foo');

  #     // Set the page content after the waitFor has been started.
  #     await page.setContent(
  #       '<div id="not-foo"></div><div class="foo">Foo1</div>'
  #     );
  #     const element = await waitFor;

  #     expect(element).toBeDefined();
  #   });
  #   it('should work when both queryOne and queryAll are registered', async () => {
  #     const { page, puppeteer } = getTestState();
  #     await page.setContent(
  #       '<div id="not-foo"></div><div class="foo"><div id="nested-foo" class="foo"/></div><div class="foo baz">Foo2</div>'
  #     );
  #     puppeteer.__experimental_registerCustomQueryHandler('getByClass', {
  #       queryOne: (element, selector) => element.querySelector(`.${selector}`),
  #       queryAll: (element, selector) =>
  #         element.querySelectorAll(`.${selector}`),
  #     });

  #     const element = await page.$('getByClass/foo');
  #     expect(element).toBeDefined();

  #     const elements = await page.$$('getByClass/foo');
  #     expect(elements.length).toBe(3);
  #   });
  #   it('should eval when both queryOne and queryAll are registered', async () => {
  #     const { page, puppeteer } = getTestState();
  #     await page.setContent(
  #       '<div id="not-foo"></div><div class="foo">text</div><div class="foo baz">content</div>'
  #     );
  #     puppeteer.__experimental_registerCustomQueryHandler('getByClass', {
  #       queryOne: (element, selector) => element.querySelector(`.${selector}`),
  #       queryAll: (element, selector) =>
  #         element.querySelectorAll(`.${selector}`),
  #     });

  #     const txtContent = await page.$eval(
  #       'getByClass/foo',
  #       (div) => div.textContent
  #     );
  #     expect(txtContent).toBe('text');

  #     const txtContents = await page.$$eval('getByClass/foo', (divs) =>
  #       divs.map((d) => d.textContent).join('')
  #     );
  #     expect(txtContents).toBe('textcontent');
  #   });
  # });
end
