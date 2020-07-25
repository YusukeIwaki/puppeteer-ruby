require 'spec_helper'

RSpec.describe Puppeteer::Page do
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

    before {
      page.goto("http://127.0.0.1:4567/button")
    }

    it 'should click button' do
      page.click('button')
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end

    context 'even if window.Node is removed' do
      before {
        page.evaluate('() => delete window.Node')
      }

      it 'should click button' do
        page.click('button')
        expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
      end
    end

    it 'should fail to click a missing button' do
      expect { page.click('button.does-not-exist') }.to raise_error(/No node found for selector: button.does-not-exist/)
    end
  end

  context 'with svg' do
    before {
      page.content = <<~SVG
      <svg height="100" width="100">
        <circle onclick="javascript:window.__CLICKED=42" cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
      </svg>
      SVG
    }

    it 'should click svg' do
      page.click('circle')
      expect(page.evaluate('() => globalThis.__CLICKED')).to eq(42)
    end
  end

  # https://github.com/puppeteer/puppeteer/issues/4281
  context 'with css-content span' do
    before {
      page.content = <<~HTML
      <style>
      span::before {
        content: 'q';
      }
      </style>
      <span onclick='javascript:window.CLICKED=42'></span>
      HTML
    }

    it 'should click on a span with an inline element inside' do
      page.click('span')
      expect(page.evaluate('() => globalThis.CLICKED')).to eq(42)
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

    it 'should click the button after navigation' do
      page.goto("http://127.0.0.1:4567/button")
      page.click('button')
      page.goto("http://127.0.0.1:4567/button")
      page.click('button')
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end

  context 'even when JavaScript is disabled' do
    sinatra do
      get('/wrappedlink') do
        <<~HTML
        <div>
          <a href='#clicked'>123321</a>
        </div>
        <script>
          document.querySelector('a').addEventListener('click', () => {
            window.__clicked = true;
          });
        </script>
        HTML
      end
    end

    before {
      page.javascript_enabled = false
      page.goto("http://127.0.0.1:4567/wrappedlink")
    }

    it 'should click with disabled javascript' do
      await_all(
        page.async_wait_for_navigation,
        page.async_click('a'),
      )
      expect(page.url).to eq('http://127.0.0.1:4567/wrappedlink#clicked')
    end
  end

  context 'with content outside of screen' do
    before {
      page.content = <<~HTML
      <style>
      i {
        position: absolute;
        top: -1000px;
      }
      </style>
      <span onclick='javascript:window.CLICKED = 42;'><i>woof</i><b>doggo</b></span>
      HTML
    }

    it 'should click when one of inline box children is outside of viewport' do
      page.click('span')
      expect(page.evaluate('() => globalThis.CLICKED')).to eq(42)
    end
  end

  context 'with textarea page' do
    sinatra do
      get('/textarea') do
        <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Textarea test</title>
          </head>
          <body>
            <textarea></textarea>
            <script src='mouse-helper.js'></script>
            <script>
              globalThis.result = '';
              globalThis.textarea = document.querySelector('textarea');
              textarea.addEventListener('input', () => result = textarea.value, false);
            </script>
          </body>
        </html>
        HTML
      end
    end

    before {
      page.goto("http://127.0.0.1:4567/textarea")
    }

    it 'should select the text by triple clicking' do
      page.focus('textarea')
      text = "This is the text that we are going to try to select. Let's see how it goes."
      page.keyboard.type_text(text)
      page.click('textarea')
      page.click('textarea', click_count: 2)
      page.click('textarea', click_count: 3)

      selected_text = page.evaluate <<~JAVASCRIPT
      () => {
        const textarea = document.querySelector('textarea');
        return textarea.value.substring(
          textarea.selectionStart,
          textarea.selectionEnd
        );
      }
      JAVASCRIPT
      expect(selected_text).to eq(text)
    end
  end

  context 'with offscreenbuttons page' do
    sinatra do
      get('/offscreenbuttons') do
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
        <span id="log"></span>
        <script>
        window.addEventListener('DOMContentLoaded', () => {
          for (const button of Array.from(document.querySelectorAll('button')))
            button.addEventListener('click', () => document.getElementById("log").innerHTML+=('button #' + button.textContent + ' clicked'), false);
        }, false);
        </script>
        HTML
      end
    end

    before {
      page.goto("http://127.0.0.1:4567/offscreenbuttons")
    }

    it 'should click offscreen buttons' do
      11.times do |i|
        # We might've scrolled to click a button - reset to (0, 0).
        page.evaluate('() => window.scrollTo(0, 0)')
        page.click("#btn#{i}")
      end
      expect(page.Seval('#log', 'el => el.textContent')).to eq([
        'button #0 clicked',
        'button #1 clicked',
        'button #2 clicked',
        'button #3 clicked',
        'button #4 clicked',
        'button #5 clicked',
        'button #6 clicked',
        'button #7 clicked',
        'button #8 clicked',
        'button #9 clicked',
        'button #10 clicked',
      ].join(''))
    end
  end

  context 'with wrappedlink page' do
    sinatra do
      get('/wrappedlink') do
        <<~HTML
        <div>
          <a href='#clicked'>123321</a>
        </div>
        <script>
          document.querySelector('a').addEventListener('click', () => {
            window.__clicked = true;
          });
        </script>
        HTML
      end
    end

    before {
      page.goto("http://127.0.0.1:4567/wrappedlink")
    }

    it 'should click wrapped link' do
      page.click('a')
      expect(page.evaluate('() => globalThis.__clicked')).to eq(true)
    end
  end

  context 'with checkbox page' do
    sinatra do
      get('/checkbox') do
        <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Selection Test</title>
          </head>
          <body>
            <label for="agree">Remember Me</label>
            <input id="agree" type="checkbox">
            <script>
              window.result = {
                check: null,
                events: [],
              };

              let checkbox = document.querySelector('input');

              const events = [
                'change',
                'click',
                'dblclick',
                'input',
                'mousedown',
                'mouseenter',
                'mouseleave',
                'mousemove',
                'mouseout',
                'mouseover',
                'mouseup',
              ];

              for (let event of events) {
                checkbox.addEventListener(event, () => {
                  if (['change', 'click', 'dblclick', 'input'].includes(event) === true) {
                    result.check = checkbox.checked;
                  }

                  result.events.push(event);
                }, false);
              }
            </script>
          </body>
        </html>
        HTML
      end
    end

    before {
      page.goto("http://127.0.0.1:4567/checkbox")
    }

    it 'should click on checkbox input and toggle' do
      expect(page.evaluate('() => globalThis.result.check')).to be_nil

      page.click('input#agree')
      expect(page.evaluate('() => globalThis.result.check')).to eq(true)
      expect(page.evaluate('() => globalThis.result.events')).to eq([
        'mouseover',
        'mouseenter',
        'mousemove',
        'mousedown',
        'mouseup',
        'click',
        'input',
        'change',
      ])

      page.click('input#agree')
      expect(page.evaluate('() => globalThis.result.check')).to eq(false)
    end

    it 'should click on checkbox label and toggle' do
      expect(page.evaluate('() => globalThis.result.check')).to be_nil

      page.click('label[for="agree"]')
      expect(page.evaluate('() => globalThis.result.check')).to eq(true)
      expect(page.evaluate('() => globalThis.result.events')).to eq([
        'click',
        'input',
        'change',
      ])

      page.click('label[for="agree"]')
      expect(page.evaluate('() => globalThis.result.check')).to eq(false)
    end
  end

  context 'with touch-enabled viewports' do
    before {
      page.viewport = Puppeteer::Devices.iPhone_6.viewport
    }

    it 'should not hang' do
      expect {
        Timeout.timeout(2) do
          page.mouse.down
          page.mouse.move(100, 10)
          page.mouse.up()
        end
      }.not_to raise_error(Timeout::Error)
    end
  end

  context 'with scrollable page' do
    sinatra do
      get('/scrollable') do
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

    before {
      page.goto("http://127.0.0.1:4567/scrollable")
    }

    it 'should scroll and click the button' do
      page.click('#button-5')
      expect(page.evaluate("() => document.querySelector('#button-5').textContent")).to eq('clicked')
      page.click('#button-80')
      expect(page.evaluate("() => document.querySelector('#button-80').textContent")).to eq('clicked')
    end

    it 'should fire contextmenu event on right click' do
      page.click('#button-8', button: 'right')
      expect(page.evaluate("() => document.querySelector('#button-8').textContent")).to eq('context menu')
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

    before {
      page.goto("http://127.0.0.1:4567/button")
    }

    context 'with double click listener' do
      before {
        page.evaluate <<~JAVASCRIPT
        () => {
          globalThis.double = false;
          const button = document.querySelector('button');
          button.addEventListener('dblclick', () => {
            globalThis.double = true;
          });
        }
        JAVASCRIPT
      }

      it 'should double click button' do
        page.click('button', click_count: 2)
        expect(page.evaluate('() => globalThis.double')).to eq(true)
        expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
      end
    end

    context 'even if the button is partially obscured' do
      before {
        page.evaluate <<~JAVASCRIPT
        () => {
          const button = document.querySelector('button');
          button.textContent = 'Some really long text that will go offscreen';
          button.style.position = 'absolute';
          button.style.left = '368px';
        }
        JAVASCRIPT
      }

      it 'should click button' do
        page.click('button')
        expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
      end
    end
  end

  context 'with rotated button page' do
    sinatra do
      get('/rotatedButton') do
        <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Rotated button test</title>
          </head>
          <body>
            <script src="mouse-helper.js"></script>
            <button onclick="clicked();">Click target</button>
            <style>
              button {
                transform: rotateY(180deg);
              }
            </style>
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

    before {
      page.goto("http://127.0.0.1:4567/rotatedButton")
    }

    it 'should click button' do
      page.click('button')
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end

  # https://github.com/puppeteer/puppeteer/issues/206
  context 'with empty page link' do
    before {
      page.content = '<a href="about:blank">empty.html</a>'
    }

    it 'should not hang' do
      expect {
        Timeout.timeout(2) do
          page.click('a')
        end
      }.not_to raise_error(Timeout::Error)
    end
  end

  def attach_frame(page, frame_id, url)
    js = <<~JAVASCRIPT
    async function attachFrame(frameId, url) {
      const frame = document.createElement('iframe');
      frame.src = url;
      frame.id = frameId;
      document.body.appendChild(frame);
      await new Promise((x) => (frame.onload = x));
      return frame;
    }
    JAVASCRIPT
    page.evaluate_handle(js, frame_id, url).as_element.content_frame
  end

  context 'with button inside an iframe' do
    sinatra do
      get('/') do
        '<div style="width:100px;height:100px">spacer</div>'
      end
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

    context 'without device scale factor' do
      before {
        page.goto('http://127.0.0.1:4567/')
        attach_frame(page, 'button-test', '/button')
      }

      it 'should click the button inside an iframe' do
        frame = page.frames.last
        frame.S('button').click
        expect(frame.evaluate('() => globalThis.result')).to eq('Clicked')
      end
    end

    context 'with device scale factor' do
      before {
        page.viewport = Puppeteer::Viewport.new(width: 400, height: 400, device_scale_factor: 5)
        unless page.evaluate('() => window.devicePixelRatio') == 5
          raise 'something wrong...'
        end

        page.goto('http://127.0.0.1:4567/')
        attach_frame(page, 'button-test', '/button')
      }

      it 'should click the button inside an iframe' do
        frame = page.frames.last
        frame.S('button').click
        expect(frame.evaluate('() => globalThis.result')).to eq('Clicked')
      end
    end
  end
end
