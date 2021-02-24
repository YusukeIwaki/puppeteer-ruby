require 'spec_helper'

RSpec.describe Puppeteer::Keyboard do
  context 'with textarea content' do
    before {
      page.evaluate(<<~JAVASCRIPT)
      () => {
        const textarea = document.createElement('textarea');
        document.body.appendChild(textarea);
        textarea.focus();
      }
      JAVASCRIPT
    }

    it 'should type into a textarea' do
      text = 'Hello world. I am the text that was typed!'
      page.keyboard.type_text(text)
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq(text)
    end

    it 'should input ( by type_text method' do
      text = '(puppeteer)'
      page.keyboard.type_text(text)
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq(text)
    end

    it 'should input ( by pressing Shift + 9' do
      page.keyboard do
        down('Shift')
        press('Digit9')
        up('Shift')
      end
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('(')
    end
  end

  context 'with key event listener content' do
    before {
      page.evaluate(<<~JAVASCRIPT)
      () => {
        window.keyPromise = new Promise((resolve) =>
          document.addEventListener('keydown', (event) => resolve(event.key))
        );
      }
      JAVASCRIPT
    }

    it 'should press the metaKey' do
      page.keyboard.press('Meta')
      expect(page.evaluate('keyPromise')).to eq('Meta')
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

    it 'should move with the arrow keys' do
      page.type_text('textarea', 'Hello World!')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('Hello World!')

      'World!'.length.times { page.keyboard.press('ArrowLeft') }
      page.keyboard.type_text('inserted ')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('Hello inserted World!')

      page.keyboard.down('Shift')
      'inserted '.length.times { page.keyboard.press('ArrowLeft') }
      page.keyboard.up('Shift')
      page.keyboard.press('Backspace')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('Hello World!')
    end

    it 'should send a character with ElementHandle.press' do
      textarea = page.query_selector('textarea')
      textarea.press('a')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('a')

      page.evaluate("() => window.addEventListener('keydown', (e) => e.preventDefault(), true)")
      textarea.press('b')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('a')
    end

    it_fails_firefox 'ElementHandle.press should support |text| option' do
      textarea = page.query_selector('textarea')
      textarea.press('a', text: 'ё')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('ё')
    end

    it_fails_firefox 'should send a character with sendCharacter' do
      page.focus('textarea')
      page.keyboard.send_character('嗨')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('嗨')

      page.evaluate("() => window.addEventListener('keydown', (e) => e.preventDefault(), true)")
      page.keyboard.send_character('a')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('嗨a')
    end

    it 'should not type canceled events' do
      page.focus('textarea')
      page.evaluate(<<~JAVASCRIPT)
      () => {
        window.addEventListener(
          'keydown',
          (event) => {
            event.stopPropagation();
            event.stopImmediatePropagation();
            if (event.key === 'l') event.preventDefault();
            if (event.key === 'o') event.preventDefault();
          },
          false
        );
      }
      JAVASCRIPT
      page.keyboard.type_text('Hello World!')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('He Wrd!')
    end

    it_fails_firefox 'should specify repeat property' do
      page.focus('textarea')
      page.evaluate(<<~JAVASCRIPT)
      () => document.querySelector('textarea').addEventListener('keydown', (e) => (globalThis.lastEvent = e), true)
      JAVASCRIPT

      page.keyboard.down('a')
      expect(page.evaluate('() => globalThis.lastEvent.repeat')).to eq(false)
      page.keyboard.press('a')
      expect(page.evaluate('() => globalThis.lastEvent.repeat')).to eq(true)

      page.keyboard.down('b')
      expect(page.evaluate('() => globalThis.lastEvent.repeat')).to eq(false)
      page.keyboard.press('b')
      expect(page.evaluate('() => globalThis.lastEvent.repeat')).to eq(true)

      page.keyboard.up('a')
      page.keyboard.down('a')
      expect(page.evaluate('() => globalThis.lastEvent.repeat')).to eq(false)
    end

    it_fails_firefox 'should type all kinds of characters' do
      page.focus('textarea')
      text = 'This text goes onto two lines.\nThis character is 嗨.'
      page.keyboard.type_text(text)
      expect(page.evaluate('result')).to eq(text)
    end

    it_fails_firefox 'should specify location' do
      page.evaluate(<<~JAVASCRIPT)
      () => {
        window.addEventListener(
          'keydown',
          (event) => (globalThis.keyLocation = event.location),
          true
        );
      }
      JAVASCRIPT

      textarea = page.query_selector('textarea')

      {
        'Digit5' => 0,
        'ControlLeft' => 1,
        'ControlRight' => 2,
        'NumpadSubtract' => 3,
      }.each do |key, location|
        textarea.press(key)
        expect(page.evaluate('keyLocation')).to eq(location)
      end
    end

    it_fails_firefox 'should type emoji' do
      page.type_text('textarea', '👹 Tokyo street Japan 🇯🇵')
      expect(page.eval_on_selector('textarea', '(textarea) => textarea.value')).to eq('👹 Tokyo street Japan 🇯🇵')
    end
  end

  context 'with keyboard page' do
    sinatra do
      get('/keyboard') do
        <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Keyboard test</title>
          </head>
          <body>
            <textarea></textarea>
            <script>
              window.result = "";
              let textarea = document.querySelector('textarea');
              textarea.focus();
              textarea.addEventListener('keydown', event => {
                log('Keydown:', event.key, event.code, event.which, modifiers(event));
              });
              textarea.addEventListener('keypress', event => {
                log('Keypress:', event.key, event.code, event.which, event.charCode, modifiers(event));
              });
              textarea.addEventListener('keyup', event => {
                log('Keyup:', event.key, event.code, event.which, modifiers(event));
              });
              function modifiers(event) {
                let m = [];
                if (event.altKey)
                  m.push('Alt')
                if (event.ctrlKey)
                  m.push('Control');
                if (event.shiftKey)
                  m.push('Shift')
                return '[' + m.join(' ') + ']';
              }
              function log(...args) {
                console.log.apply(console, args);
                result += args.join(' ') + '\\n';
              }
              function getResult() {
                let temp = result.trim();
                result = "";
                return temp;
              }
            </script>
          </body>
        </html>
        HTML
      end
    end

    before {
      page.goto("http://127.0.0.1:4567/keyboard")
    }

    {
      'Shift' => 16,
      'Alt' => 18,
      'Control' => 17,
    }.each do |modifier_key, modifier_code|
      it "should report shiftKey  [modifier_key: #{modifier_key}]" do
        page.keyboard.down(modifier_key)
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq("Keydown: #{modifier_key} #{modifier_key}Left #{modifier_code} [#{modifier_key}]")

        page.keyboard.down('!')
        result = page.evaluate('() => globalThis.getResult()')
        # Shift+! will generate a keypress
        if modifier_key == 'Shift'
          expect(result).to eq("Keydown: ! Digit1 49 [#{modifier_key}]\nKeypress: ! Digit1 33 33 [#{modifier_key}]")
        elsif modifier_key == 'Alt' && Puppeteer.env.firefox? && Puppeteer.env.darwin?
          expect(result).to eq("Keydown: ! Digit1 49 [#{modifier_key}]\nKeypress: ! Digit1 33 33 [#{modifier_key}]")
        else
          expect(result).to eq("Keydown: ! Digit1 49 [#{modifier_key}]")
        end

        page.keyboard.up('!')
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq("Keyup: ! Digit1 49 [#{modifier_key}]")

        page.keyboard.up(modifier_key)
        result = page.evaluate('() => globalThis.getResult()')
        expect(result).to eq("Keyup: #{modifier_key} #{modifier_key}Left #{modifier_code} []")
      end
    end

    it 'should report multiple modifiers' do
      page.keyboard.down('Control')
      result = page.evaluate('() => globalThis.getResult()')
      expect(result).to eq('Keydown: Control ControlLeft 17 [Control]')

      page.keyboard.down('Alt')
      result = page.evaluate('() => globalThis.getResult()')
      expect(result).to eq('Keydown: Alt AltLeft 18 [Alt Control]')

      page.keyboard.down(';')
      result = page.evaluate('() => globalThis.getResult()')
      expect(result).to eq('Keydown: ; Semicolon 186 [Alt Control]')

      page.keyboard.up(';')
      result = page.evaluate('() => globalThis.getResult()')
      expect(result).to eq('Keyup: ; Semicolon 186 [Alt Control]')

      page.keyboard.up('Control')
      result = page.evaluate('() => globalThis.getResult()')
      expect(result).to eq('Keyup: Control ControlLeft 17 [Alt]')

      page.keyboard.up('Alt')
      result = page.evaluate('() => globalThis.getResult()')
      expect(result).to eq('Keyup: Alt AltLeft 18 []')
    end

    it 'should send proper codes while typing' do
      page.keyboard.type_text('!')
      result = page.evaluate('() => globalThis.getResult()')
      expect(result).to eq([
        'Keydown: ! Digit1 49 []',
        'Keypress: ! Digit1 33 33 []',
        'Keyup: ! Digit1 49 []',
      ].join("\n"))

      page.keyboard.type_text('^')
      result = page.evaluate('() => globalThis.getResult()')
      expect(result).to eq([
        'Keydown: ^ Digit6 54 []',
        'Keypress: ^ Digit6 94 94 []',
        'Keyup: ^ Digit6 54 []',
      ].join("\n"))
    end

    it 'should send proper codes while typing with shift' do
      page.keyboard.down('Shift')
      page.keyboard.type_text('~')
      result = page.evaluate('() => globalThis.getResult()')
      expect(result).to eq([
        'Keydown: Shift ShiftLeft 16 [Shift]',
        'Keydown: ~ Backquote 192 [Shift]', # 192 is ` keyCode
        'Keypress: ~ Backquote 126 126 [Shift]', # 126 is ~ charCode
        'Keyup: ~ Backquote 192 [Shift]',
      ].join("\n"))
      page.keyboard.up('Shift')
    end
  end

  it 'should throw on unknown keys' do
    expect { page.keyboard.press('NotARealKey') }.to raise_error(/Unknown key: "NotARealKey"/)
    expect { page.keyboard.press('ё') }.to raise_error(/Unknown key: "ё"/)
    expect { page.keyboard.press('😊') }.to raise_error(/Unknown key: "😊"/)
  end

  context 'with textarea page and iframe' do
    include Utils::AttachFrame

    sinatra do
      get('/') do
        '<html><body></body></html>'
      end
      get('/textarea') do
        <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Textarea test</title>
          </head>
          <body>
            <textarea></textarea>
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
      page.goto("http://127.0.0.1:4567/")
      attach_frame(page, 'emoji-test', '/textarea')
    }

    it_fails_firefox 'should type emoji into an iframe' do
      frame = page.frames.last
      textarea = frame.query_selector('textarea')
      textarea.type_text('👹 Tokyo street Japan 🇯🇵')
      expect(frame.eval_on_selector('textarea', '(textarea) => textarea.value')).to eq('👹 Tokyo street Japan 🇯🇵')
    end
  end

  context 'with keydown event listener' do
    before {
      page.evaluate(<<~JAVASCRIPT)
      () => {
        globalThis.result = null;
        document.addEventListener('keydown', (event) => {
          globalThis.result = [event.key, event.code, event.metaKey];
        });
      }
      JAVASCRIPT
    }

    it 'should press the meta key' do
      page.keyboard.press('Meta')

      key, code, meta_key = page.evaluate('result')
      expect(key).to eq('Meta')
      if Puppeteer.env.firefox?
        if Puppeteer.env.darwin?
          expect(code).to eq('OSLeft')
        else
          expect(code).to eq('AltLeft')
        end
      else
        expect(code).to eq('MetaLeft')
      end
      expect(meta_key).to eq(true)
    end
  end

  describe 'block' do
    before {
      page.content = '<html><body><input id="editor" type="text" /></body></html>'
    }

    it 'can use press, send_text with block' do
      page.click('input')
      page.keyboard {
        type_text '123456789'
        down 'Shift'
        5.times { press 'ArrowLeft' }
        up 'Shift'
        if Puppeteer.env.firefox?
          press('a')
        else
          send_character('a')
        end
      }
      expect(page.query_selector('input').evaluate('(el) => el.value')).to eq('1234a')
    end

    it 'can use press, send_text without block' do
      page.click('input')
      page.keyboard.type_text('123456789')
      page.keyboard.down('Shift')
      5.times { page.keyboard.press('ArrowLeft') }
      page.keyboard.up('Shift')
      if Puppeteer.env.firefox?
        page.keyboard.press('a')
      else
        page.keyboard.send_character('a')
      end
      expect(page.query_selector('input').evaluate('(el) => el.value')).to eq('1234a')
    end
  end
end
