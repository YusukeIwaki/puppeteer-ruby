require 'spec_helper'

RSpec.describe Puppeteer::ElementHandle do
  describe '#bounding_box' do
    context 'with grid page' do
      sinatra do
        get('/grid.html') do
          <<~HTML
          <script>
          document.addEventListener('DOMContentLoaded', function() {
              function generatePalette(amount) {
                  var result = [];
                  var hueStep = 360 / amount;
                  for (var i = 0; i < amount; ++i)
                      result.push('hsl(' + (hueStep * i) + ', 100%, 90%)');
                  return result;
              }

              var palette = generatePalette(100);
              for (var i = 0; i < 200; ++i) {
                  var box = document.createElement('div');
                  box.classList.add('box');
                  box.style.setProperty('background-color', palette[i % palette.length]);
                  var x = i;
                  do {
                      var digit = x % 10;
                      x = (x / 10)|0;
                      var img = document.createElement('img');
                      img.src = `./digits/${digit}.png`;
                      box.insertBefore(img, box.firstChild);
                  } while (x);
                  document.body.appendChild(box);
              }
          });
          </script>

          <style>

          body {
              margin: 0;
              padding: 0;
          }

          .box {
              font-family: arial;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              margin: 0;
              padding: 0;
              width: 50px;
              height: 50px;
              box-sizing: border-box;
              border: 1px solid darkgray;
          }

          ::-webkit-scrollbar {
              display: none;
          }
          </style>
          HTML
        end
      end

      it 'should work' do
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.goto('http://127.0.0.1:4567/grid.html')

        element_handle = page.S('.box:nth-of-type(13)')
        box = element_handle.bounding_box
        expect(box.x).to eq(100)
        expect(box.y).to eq(50)
        expect(box.width).to eq(50)
        expect(box.height).to eq(50)
      end
    end

    context 'with nested frames page' do
      sinatra do
        get('/nested-frames.html') do
          <<~HTML
          <style>
          body {
              display: flex;
          }

          body iframe {
              flex-grow: 1;
              flex-shrink: 1;
          }
          ::-webkit-scrollbar{
              display: none;
          }
          </style>
          <script>
          async function attachFrame(frameId, url) {
              var frame = document.createElement('iframe');
              frame.src = url;
              frame.id = frameId;
              document.body.appendChild(frame);
              await new Promise(x => frame.onload = x);
              return 'kazakh';
          }
          </script>
          <iframe src='./two-frames.html' name='2frames'></iframe>
          <iframe src='./frame.html' name='aframe'></iframe>
          HTML
        end
        get('/two-frames.html') do
          <<~HTML
          <style>
          body {
              display: flex;
              flex-direction: column;
          }

          body iframe {
              flex-grow: 1;
              flex-shrink: 1;
          }
          </style>
          <iframe src='./frame.html' name='uno'></iframe>
          <iframe src='./frame.html' name='dos'></iframe>

          <!-- flex layout often layout iframes with 250px height... So increase the number of frames :) --->
          <iframe src='./frame.html' name='xxx'></iframe>
          <iframe src='./frame.html' name='yyy'></iframe>
          HTML
        end
        get('/frame.html') do
          <<~HTML
          <script src='./script.js' type='text/javascript'></script>
          <style>
          div {
            color: blue;
            line-height: 18px;
          }
          </style>
          <div>Hi, I'm frame</div>
          HTML
        end
      end

      it 'should handle nested frames' do
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.goto('http://127.0.0.1:4567/nested-frames.html')

        nested_frame = page.frames[1].child_frames[1]
        element_handle = nested_frame.S('div')
        box = element_handle.bounding_box

        expect(box.x).to eq(28)
        expect(box.y).to eq(182)
        expect(box.width).to eq(264)
        expect(box.height).to eq(18)
      end
    end

    it 'should return null for invisible elements' do
      page.content = '<div style="display:none">hi</div>'
      element = page.S('div')
      expect(element.bounding_box).to be_nil
    end

    it 'should force a layout' do
      page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
      page.content = '<div style="width: 100px; height: 100px">hello</div>'

      element_handle = page.S('div')
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
      element = page.S('#therect')
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
    context 'with reset css page' do
      include Utils::AttachFrame

      sinatra do
        get('/resetcss.html') do
          <<~HTML
          <style>
          /* http://meyerweb.com/eric/tools/css/reset/
            v2.0 | 20110126
            License: none (public domain)
          */

          html, body, div, span, applet, object, iframe,
          h1, h2, h3, h4, h5, h6, p, blockquote, pre,
          a, abbr, acronym, address, big, cite, code,
          del, dfn, em, img, ins, kbd, q, s, samp,
          small, strike, strong, sub, sup, tt, var,
          b, u, i, center,
          dl, dt, dd, ol, ul, li,
          fieldset, form, label, legend,
          table, caption, tbody, tfoot, thead, tr, th, td,
          article, aside, canvas, details, embed,
          figure, figcaption, footer, header, hgroup,
          menu, nav, output, ruby, section, summary,
          time, mark, audio, video {
            margin: 0;
            padding: 0;
            border: 0;
            font-size: 100%;
            font: inherit;
            vertical-align: baseline;
          }
          /* HTML5 display-role reset for older browsers */
          article, aside, details, figcaption, figure,
          footer, header, hgroup, menu, nav, section {
            display: block;
          }
          body {
            line-height: 1;
          }
          ol, ul {
            list-style: none;
          }
          blockquote, q {
            quotes: none;
          }
          blockquote:before, blockquote:after,
          q:before, q:after {
            content: '';
            content: none;
          }
          table {
            border-collapse: collapse;
            border-spacing: 0;
          }
          </style>
          HTML
        end
      end

      before { page.goto('http://127.0.0.1:4567/resetcss.html') }

      it 'should work' do
        # Step 1: Add Frame and position it absolutely.
        attach_frame(page, 'frame1', '/resetcss.html')
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
    end

    it 'should return null for invisible elements' do
      page.content = '<div style="display:none">hi</div>'
      element = page.S('div')
      expect(element.box_model).to be_nil
    end
  end

  describe '#contentFrame' do
    include Utils::AttachFrame
    sinatra do
      get('/') do
        '<html><body></body></html>'
      end
    end

    it 'should work' do
      page.goto('http://127.0.0.1:4567/')
      attach_frame(page, 'frame1', '/')
      element_handle = page.S('#frame1')
      frame = element_handle.content_frame
      expect(frame).to eq(page.frames()[1])
    end
  end

  describe '#click' do
    context 'with shadow DOM page' do
      sinatra do
        get('/shadow') do
          <<~HTML
          <script>
          let h1 = null;
          window.button = null;
          window.clicked = false;

          window.addEventListener('DOMContentLoaded', () => {
            const shadowRoot = document.body.attachShadow({mode: 'open'});
            h1 = document.createElement('h1');
            h1.textContent = 'Hellow Shadow DOM v1';
            button = document.createElement('button');
            button.textContent = 'Click';
            button.addEventListener('click', () => clicked = true);
            shadowRoot.appendChild(h1);
            shadowRoot.appendChild(button);
          });
          </script>
          HTML
        end
      end

      before { page.goto('http://127.0.0.1:4567/shadow') }

      it 'should work for Shadow DOM v1' do
        button_handle = page.evaluate_handle('() => button')
        button_handle.click
        expect(page.evaluate('() => clicked')).to eq(true)
      end
    end

    context 'with button page' do
      sinatra do
        get('/button') do
          <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Button test</title>
            </head>
            <body>
              <button onclick="clicked();">Click target</button>
              <script>
                window.result = 'Was not clicked';
                function clicked() {
                  result = 'Clicked';
                }
              </script>
            </body>
          </html>
          HTML
        end
      end

      before { page.goto('http://127.0.0.1:4567/button') }

      it 'should work' do
        page.S('button').click
        expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
      end

      it 'should throw for TextNodes' do
        button_text_node = page.evaluate_handle("() => document.querySelector('button').firstChild")
        expect { button_text_node.click }.to raise_error(/Node is not of type HTMLElement/)
      end

      it 'should throw for detached nodes' do
        button = page.S('button')
        page.evaluate('(button) => button.remove()', button)
        expect { button.click }.to raise_error(/Node is detached from document/)
      end

      it 'should throw for hidden nodes' do
        button = page.S('button')
        page.evaluate("(button) => (button.style.display = 'none')", button)
        expect { button.click }.to raise_error(/Node is either not visible or not an HTMLElement/)
      end

      it 'should throw for recursively hidden nodes' do
        button = page.S('button')
        page.evaluate("(button) => (button.parentElement.style.display = 'none')", button)
        expect { button.click }.to raise_error(/Node is either not visible or not an HTMLElement/)
      end
    end

    it 'should throw for <br> elements' do
      page.content = 'hello<br>goodbye'
      br = page.S('br')
      expect { br.click }.to raise_error(/Node is either not visible or not an HTMLElement/)
    end
  end

  describe '#hover' do
    context 'with scrollable page' do
      sinatra do
        get('/scrollable.html') do
          <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Scrollable test</title>
            </head>
            <body>
              <script src='mouse-helper.js'></script>
              <script>
                  for (let i = 0; i < 100; i++) {
                      let button = document.createElement('button');
                      button.textContent = i + ': not clicked';
                      button.id = 'button-' + i;
                      button.onclick = () => button.textContent = 'clicked';
                      button.oncontextmenu = event => {
                        event.preventDefault();
                        button.textContent = 'context menu';
                      }
                      document.body.appendChild(button);
                      document.body.appendChild(document.createElement('br'));
                  }
              </script>
            </body>
          </html>
          HTML
        end
      end

      before { page.goto('http://127.0.0.1:4567/scrollable.html') }

      it 'should work' do
        button = page.S('#button-6')
        button.hover
        expect(page.evaluate("() => document.querySelector('button:hover').id")).to eq('button-6')
      end
    end
  end

  describe '#intersecting_viewport?' do
    context 'with offscreenbutton page' do
      sinatra do
        get('/offscreenbuttons.html') do
          <<~HTML
          <style>
            button {
              position: absolute;
              width: 100px;
              height: 20px;
            }

            #btn0 { right: 0px; top: 0; }
            #btn1 { right: -10px; top: 25px; }
            #btn2 { right: -20px; top: 50px; }
            #btn3 { right: -30px; top: 75px; }
            #btn4 { right: -40px; top: 100px; }
            #btn5 { right: -50px; top: 125px; }
            #btn6 { right: -60px; top: 150px; }
            #btn7 { right: -70px; top: 175px; }
            #btn8 { right: -80px; top: 200px; }
            #btn9 { right: -90px; top: 225px; }
            #btn10 { right: -100px; top: 250px; }
          </style>
          <button id=btn0>0</button>
          <button id=btn1>1</button>
          <button id=btn2>2</button>
          <button id=btn3>3</button>
          <button id=btn4>4</button>
          <button id=btn5>5</button>
          <button id=btn6>6</button>
          <button id=btn7>7</button>
          <button id=btn8>8</button>
          <button id=btn9>9</button>
          <button id=btn10>10</button>
          <script>
          window.addEventListener('DOMContentLoaded', () => {
            for (const button of Array.from(document.querySelectorAll('button')))
              button.addEventListener('click', () => console.log('button #' + button.textContent + ' clicked'), false);
          }, false);
          </script>
          HTML
        end
      end

      before { page.goto('http://127.0.0.1:4567/offscreenbuttons.html') }

      it 'should work' do
        10.times do |i|
          button = page.S("#btn#{i}")
          # All but last button are visible.
          expect(button.intersecting_viewport?).to eq(true)
        end
        button = page.S("#btn10")
        expect(button.intersecting_viewport?).to eq(false)
      end
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
