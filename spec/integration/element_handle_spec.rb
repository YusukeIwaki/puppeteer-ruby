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

    it_fails_firefox 'should work with offset' do
      clicks = []
      page.expose_function('reportClick', -> (x, y) { clicks << [x, y] })

      page.evaluate(<<~JAVASCRIPT)
      () => {
        document.body.style.padding = '0';
        document.body.style.margin = '0';
        document.body.innerHTML = `
          <div style="cursor: pointer; width: 120px; height: 60px; margin: 30px; padding: 15px;"></div>
        `;
        document.body.addEventListener('click', (e) => {
          window.reportClick(e.clientX, e.clientY);
        });
      }
      JAVASCRIPT

      div_handle = page.query_selector('div')
      div_handle.click
      div_handle.click(offset: { x: 10, y: 15 })

      Timeout.timeout(1) do
        until clicks.count == 2
          sleep 0.01
        end
      end
      expect(clicks[0]).to eq([45 + 60, 45 + 30]) # margin + middle point offset
      expect(clicks[1]).to eq([30 + 10, 30 + 15]) # margin + offset
    end
  end

  describe 'clickable_point' do
    it 'should work' do
      page.evaluate(<<~JAVASCRIPT)
      () => {
        document.body.style.padding = '0';
        document.body.style.margin = '0';
        document.body.innerHTML = `
          <div style="cursor: pointer; width: 120px; height: 60px; margin: 30px; padding: 15px;"></div>
        `;
      }
      JAVASCRIPT

      page.evaluate(<<~JAVASCRIPT)
      async () => {
        return new Promise((resolve) => window.requestAnimationFrame(resolve));
      }
      JAVASCRIPT

      div_handle = page.query_selector('div')
      expect(div_handle.clickable_point).to eq({
        x: 45 + 60, # margin + middle point offset
        y: 45 + 30, # margin + middle point offset
      })
      expect(div_handle.clickable_point({ x: 10, y: 15 })).to eq({
        x: 30 + 10, # margin + offset
        y: 30 + 15, # margin + offset
      })
    end

    it 'should work for iframes' do
      page.evaluate(<<~JAVASCRIPT)
      () => {
        document.body.style.padding = '10px';
        document.body.style.margin = '10px';
        document.body.innerHTML = `
          <iframe style="border: none; margin: 0; padding: 0;" seamless sandbox srcdoc="<style>* { margin: 0; padding: 0;}</style><div style='cursor: pointer; width: 120px; height: 60px; margin: 30px; padding: 15px;' />"></iframe>
        `;
      }
      JAVASCRIPT

      page.evaluate(<<~JAVASCRIPT)
      async () => {
        return new Promise((resolve) => window.requestAnimationFrame(resolve));
      }
      JAVASCRIPT

      frame = page.frames[1]
      div_handle = frame.query_selector('div')
      expect(div_handle.clickable_point).to eq({
        x: 20 + 45 + 60, # iframe pos + margin + middle point offset
        y: 20 + 45 + 30, # iframe pos + margin + middle point offset
      })
      expect(div_handle.clickable_point({ x: 10, y: 15 })).to eq({
        x: 20 + 30 + 10, # iframe pos + margin + offset
        y: 20 + 30 + 15, # iframe pos + margin + offset
      })
    end
  end

  describe '#wait_for_selector' do
    it 'should wait correctly with waitForSelector on an element' do
      element = page.wait_for_selector('.foo') do
        # Set the page content after the waitFor has been started.
        page.content = '<div id="not-foo"></div><div class="bar">bar2</div><div class="foo">Foo1</div>'
      end

      inner_element = element.wait_for_selector('.bar') do
        element.evaluate(<<~JAVASCRIPT)
        (el) => {
          el.innerHTML = '<div class="bar">bar1</div>';
        }
        JAVASCRIPT
      end
      expect(inner_element).not_to be_nil
      text = inner_element.evaluate('el => el.innerText')
      expect(text).to eq('bar1')
    end
  end

  describe '#wait_for_xpath' do
    it 'should wait correctly with waitForXPath on an element' do
      # Set the page content after the waitFor has been started.
      page.content = <<~HTML
        `<div id=el1>
          el1
          <div id=el2>
            el2
          </div>
        </div>
        <div id=el3>
          el3
        </div>`
      HTML

      el2 = page.wait_for_selector('#el1')
      expect(el2.wait_for_xpath('//div').evaluate('el => el.id')).to eq('el2')
      expect(el2.wait_for_xpath('.//div').evaluate('el => el.id')).to eq('el2')
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

  describe '#intersecting_viewport?', sinatra: true do
    before {
      page.goto("#{server_prefix}/offscreenbuttons.html")
    }

    it 'should work' do
      10.times do |i|
        button = page.query_selector("#btn#{i}")
        # All but last button are visible.
        expect(button.intersecting_viewport?).to eq(true)
      end
      button = page.query_selector("#btn10")
      expect(button.intersecting_viewport?).to eq(false)
    end

    it 'should work with threshold' do
      # a button almost cannot be seen
      # sometimes we expect to return false by isIntersectingViewport1
      button = page.query_selector('#btn11')
      expect(button.intersecting_viewport?(threshold: 0.001)).to eq(false)
    end

    it 'should work with threshold of 1' do
      # a button almost cannot be seen
      # sometimes we expect to return false by isIntersectingViewport1
      button = page.query_selector('#btn0')
      expect(button.intersecting_viewport?(threshold: 1)).to eq(true)
    end
  end

  describe 'Custom queries' do
    it 'should register and unregister' do
      page.content = '<div id="not-foo"></div><div id="foo"></div>'

      Puppeteer.with_custom_query_handler(
        name: 'getById',
        query_one: '(element, selector) => document.querySelector(`[id="${selector}"]`)',
        query_all: '(element, selector) => document.querySelectorAll(`[id="${selector}"]`)',
      ) do
        element = page.query_selector('getById/foo')
        expect(element.evaluate('el => el.id')).to eq('foo')
      end

      expect {
        page.query_selector('getById/foo')
      }.to raise_error(/Query set to use "getById", but no query handler of that name was found/)
    end

    it 'should throw with invalid query names' do
      expect {
        Puppeteer.register_custom_query_handler(
          name: '1/2/3',
          query_one: '(element, selector) => null',
          query_all: '(element, selector) => []',
        )
      }.to raise_error(/Custom query handler names may only contain \[a-zA-Z\]/)
    end

    it 'should work for multiple elements' do
      page.content = <<~HTML
      <div id="not-foo"></div>
      <div class="foo">Foo1</div>
      <div class="foo baz">Foo2</div>
      HTML

      Puppeteer.with_custom_query_handler(
        name: 'getByClass',
        query_one: '(element, selector) => document.querySelector(`.${selector}`)',
        query_all: '(element, selector) => document.querySelectorAll(`.${selector}`)',
      ) do
        elements = page.query_selector_all('getByClass/foo')
        class_names = elements.map do |element|
          element.evaluate('(element) => element.className')
        end

        expect(class_names).to eq(['foo', 'foo baz'])
      end
    end

    it 'should eval correctly' do
      page.content = <<~HTML
      <div id="not-foo"></div>
      <div class="foo">Foo1</div>
      <div class="foo baz">Foo2</div>
      HTML

      Puppeteer.with_custom_query_handler(
        name: 'getByClass',
        query_one: '(element, selector) => document.querySelector(`.${selector}`)',
        query_all: '(element, selector) => document.querySelectorAll(`.${selector}`)',
      ) do
        num_elements = page.eval_on_selector_all('getByClass/foo', '(divs) => divs.length')
        expect(num_elements).to eq(2)
      end
    end
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
  # it('should wait correctly with waitForSelector on an element', async () => {
  #   const { page, puppeteer } = getTestState();
  #   puppeteer.registerCustomQueryHandler('getByClass', {
  #     queryOne: (element, selector) => element.querySelector(`.${selector}`),
  #   });
  #   const waitFor = page.waitForSelector('getByClass/foo');

  #   // Set the page content after the waitFor has been started.
  #   await page.setContent(
  #     '<div id="not-foo"></div><div class="bar">bar2</div><div class="foo">Foo1</div>'
  #   );
  #   let element = await waitFor;
  #   expect(element).toBeDefined();

  #   const innerWaitFor = element.waitForSelector('getByClass/bar');

  #   await element.evaluate((el) => {
  #     el.innerHTML = '<div class="bar">bar1</div>';
  #   });

  #   element = await innerWaitFor;
  #   expect(element).toBeDefined();
  #   expect(
  #     await element.evaluate((el: HTMLElement) => el.innerText)
  #   ).toStrictEqual('bar1');
  # });

    it 'should work when both queryOne and queryAll are registered' do
      page.content = <<~HTML
      <div id="not-foo"></div>
      <div class="foo">
        <div id="nested-foo" class="foo"/>
      </div>
      <div class="foo baz">Foo2</div>
      HTML

      Puppeteer.with_custom_query_handler(
        name: 'getByClass',
        query_one: '(element, selector) => element.querySelector(`.${selector}`)',
        query_all: '(element, selector) => element.querySelectorAll(`.${selector}`)',
      ) do
        element = page.query_selector('getByClass/foo')
        expect(element).to be_a(Puppeteer::ElementHandle)

        elements = page.query_selector_all('getByClass/foo')
        expect(elements.size).to eq(3)
      end
    end

    it 'should eval when both queryOne and queryAll are registered' do
      page.content = <<~HTML
      <div id="not-foo"></div>
      <div class="foo">text</div>
      <div class="foo baz">content</div>
      HTML

      Puppeteer.with_custom_query_handler(
        name: 'getByClass',
        query_one: '(element, selector) => element.querySelector(`.${selector}`)',
        query_all: '(element, selector) => element.querySelectorAll(`.${selector}`)',
      ) do
        txt_content = page.eval_on_selector('getByClass/foo', '(div) => div.textContent')
        expect(txt_content).to eq('text')

        txt_contents = page.eval_on_selector_all('getByClass/foo', '(divs) => divs.map((d) => d.textContent).join("")')
        expect(txt_contents).to eq('textcontent')
      end
    end
  end
end
