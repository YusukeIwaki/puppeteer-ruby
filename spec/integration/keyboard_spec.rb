require 'spec_helper'

RSpec.describe Puppeteer::Keyboard do
  include Utils::AttachFrame

  it 'should type into a textarea' do
    with_test_state do |page:, **|
      page.evaluate(<<~JAVASCRIPT)
      () => {
        const textarea = document.createElement('textarea');
        document.body.appendChild(textarea);
        textarea.focus();
      }
      JAVASCRIPT
      text = 'Hello world. I am the text that was typed!'
      page.keyboard.type_text(text)
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq(text)
    end
  end

  it 'should move with the arrow keys' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
      page.type_text('textarea', 'Hello World!')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('Hello World!')

      'World!'.each_char { page.keyboard.press('ArrowLeft') }
      page.keyboard.type_text('inserted ')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('Hello inserted World!')

      page.keyboard.down('Shift')
      'inserted '.each_char { page.keyboard.press('ArrowLeft') }
      page.keyboard.up('Shift')
      page.keyboard.press('Backspace')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('Hello World!')
    end
  end

  # @see https://github.com/puppeteer/puppeteer/issues/1313
  it 'should trigger commands of keyboard shortcuts' do
    with_test_state do |page:, server:, **|
      cmd_key = Puppeteer.env.darwin? ? 'Meta' : 'Control'

      page.goto("#{server.prefix}/input/textarea.html")
      page.type_text('textarea', 'hello')

      page.keyboard.down(cmd_key)
      page.keyboard.press('a', commands: ['SelectAll'])
      page.keyboard.up(cmd_key)

      page.keyboard.down(cmd_key)
      page.keyboard.down('c', commands: ['Copy'])
      page.keyboard.up('c')
      page.keyboard.up(cmd_key)

      page.keyboard.down(cmd_key)
      page.keyboard.press('v', commands: ['Paste'])
      page.keyboard.press('v', commands: ['Paste'])
      page.keyboard.up(cmd_key)

      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('hellohello')
    end
  end

  it 'should send a character with ElementHandle.press' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
      textarea = page.query_selector('textarea')
      textarea.press('a')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('a')

      page.evaluate(<<~JAVASCRIPT)
      () => {
        return window.addEventListener(
          'keydown',
          (event) => {
            return event.preventDefault();
          },
          true
        );
      }
      JAVASCRIPT

      textarea.press('b')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('a')
    end
  end

  it 'ElementHandle.press should not support |text| option' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
      textarea = page.query_selector('textarea')
      textarea.press('a', text: 'ё')
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('a')
    end
  end

  it 'should send a character with sendCharacter' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
      page.focus('textarea')

      page.evaluate(<<~JAVASCRIPT)
      () => {
        globalThis.inputCount = 0;
        globalThis.keyDownCount = 0;
        window.addEventListener(
          'input',
          () => {
            globalThis.inputCount += 1;
          },
          true
        );
        window.addEventListener(
          'keydown',
          () => {
            globalThis.keyDownCount += 1;
          },
          true
        );
      }
      JAVASCRIPT

      page.keyboard.send_character('嗨')
      result = page.eval_on_selector('textarea', <<~JAVASCRIPT)
      (textarea) => ({
        value: textarea.value,
        inputs: globalThis.inputCount,
        keyDowns: globalThis.keyDownCount,
      })
      JAVASCRIPT
      expect(result).to eq({ 'value' => '嗨', 'inputs' => 1, 'keyDowns' => 0 })

      page.keyboard.send_character('a')
      result = page.eval_on_selector('textarea', <<~JAVASCRIPT)
      (textarea) => ({
        value: textarea.value,
        inputs: globalThis.inputCount,
        keyDowns: globalThis.keyDownCount,
      })
      JAVASCRIPT
      expect(result).to eq({ 'value' => '嗨a', 'inputs' => 2, 'keyDowns' => 0 })
    end
  end

  it 'should send a character with sendCharacter in iframe' do
    with_test_state do |page:, **|
      Timeout.timeout(2) do
        page.set_content(<<~HTML)
          <iframe
            srcdoc="<iframe name='test' srcdoc='<textarea></textarea>'></iframe>"
          ></iframe>
        HTML
        frame = page.wait_for_frame(predicate: ->(frame) { frame.name == 'test' })
        frame.focus('textarea')

        frame.evaluate(<<~JAVASCRIPT)
        () => {
          globalThis.inputCount = 0;
          globalThis.keyDownCount = 0;
          window.addEventListener(
            'input',
            () => {
              globalThis.inputCount += 1;
            },
            true
          );
          window.addEventListener(
            'keydown',
            () => {
              globalThis.keyDownCount += 1;
            },
            true
          );
        }
        JAVASCRIPT

        page.keyboard.send_character('嗨')
        result = frame.eval_on_selector('textarea', <<~JAVASCRIPT)
        (textarea) => ({
          value: textarea.value,
          inputs: globalThis.inputCount,
          keyDowns: globalThis.keyDownCount,
        })
        JAVASCRIPT
        expect(result).to eq({ 'value' => '嗨', 'inputs' => 1, 'keyDowns' => 0 })

        page.keyboard.send_character('a')
        result = frame.eval_on_selector('textarea', <<~JAVASCRIPT)
        (textarea) => ({
          value: textarea.value,
          inputs: globalThis.inputCount,
          keyDowns: globalThis.keyDownCount,
        })
        JAVASCRIPT
        expect(result).to eq({ 'value' => '嗨a', 'inputs' => 2, 'keyDowns' => 0 })
      end
    end
  end

  it 'should report shiftKey' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/keyboard.html")
      keyboard = page.keyboard
      %w[Shift Alt Control].each do |modifier_key|
        keyboard.down(modifier_key)
        expect(page.evaluate('() => globalThis.getResult()')).to eq("Keydown: #{modifier_key} #{modifier_key}Left [#{modifier_key}]")

        keyboard.down('!')
        if modifier_key == 'Shift'
          expect(page.evaluate('() => globalThis.getResult()')).to eq("Keydown: ! Digit1 [#{modifier_key}]\ninput: ! insertText false")
        else
          expect(page.evaluate('() => globalThis.getResult()')).to eq("Keydown: ! Digit1 [#{modifier_key}]")
        end

        keyboard.up('!')
        expect(page.evaluate('() => globalThis.getResult()')).to eq("Keyup: ! Digit1 [#{modifier_key}]")

        keyboard.up(modifier_key)
        expect(page.evaluate('() => globalThis.getResult()')).to eq("Keyup: #{modifier_key} #{modifier_key}Left []")
      end
    end
  end

  it 'should report multiple modifiers' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/keyboard.html")
      keyboard = page.keyboard
      keyboard.down('Control')
      expect(page.evaluate('() => globalThis.getResult()')).to eq('Keydown: Control ControlLeft [Control]')

      keyboard.down('Alt')
      expect(page.evaluate('() => globalThis.getResult()')).to eq('Keydown: Alt AltLeft [Alt Control]')

      keyboard.down(';')
      expect(page.evaluate('() => globalThis.getResult()')).to eq('Keydown: ; Semicolon [Alt Control]')

      keyboard.up(';')
      expect(page.evaluate('() => globalThis.getResult()')).to eq('Keyup: ; Semicolon [Alt Control]')

      keyboard.up('Control')
      expect(page.evaluate('() => globalThis.getResult()')).to eq('Keyup: Control ControlLeft [Alt]')

      keyboard.up('Alt')
      expect(page.evaluate('() => globalThis.getResult()')).to eq('Keyup: Alt AltLeft []')
    end
  end

  it 'should send proper codes while typing' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/keyboard.html")
      page.keyboard.type_text('!')
      expect(page.evaluate('() => globalThis.getResult()')).to eq([
        'Keydown: ! Digit1 []',
        'input: ! insertText false',
        'Keyup: ! Digit1 []',
      ].join("\n"))

      page.keyboard.type_text('^')
      expect(page.evaluate('() => globalThis.getResult()')).to eq([
        'Keydown: ^ Digit6 []',
        'input: ^ insertText false',
        'Keyup: ^ Digit6 []',
      ].join("\n"))
    end
  end

  it 'should send proper codes while typing with shift' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/keyboard.html")
      keyboard = page.keyboard
      keyboard.down('Shift')
      page.keyboard.type_text('~')
      expect(page.evaluate('() => globalThis.getResult()')).to eq([
        'Keydown: Shift ShiftLeft [Shift]',
        'Keydown: ~ Backquote [Shift]',
        'input: ~ insertText false',
        'Keyup: ~ Backquote [Shift]',
      ].join("\n"))
      keyboard.up('Shift')
    end
  end

  it 'should not type canceled events' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
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
      expect(page.evaluate('() => globalThis.textarea.value')).to eq('He Wrd!')
    end
  end

  it 'should specify repeat property' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
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
      page.keyboard.down('b')
      expect(page.evaluate('() => globalThis.lastEvent.repeat')).to eq(true)

      page.keyboard.up('a')
      page.keyboard.down('a')
      expect(page.evaluate('() => globalThis.lastEvent.repeat')).to eq(false)
    end
  end

  it 'should type all kinds of characters' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
      page.focus('textarea')
      text = "This text goes onto two lines.\nThis character is 嗨."
      page.keyboard.type_text(text)
      expect(page.evaluate('result')).to eq(text)
    end
  end

  it 'should specify location' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
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

      textarea.press('Digit5')
      expect(page.evaluate('keyLocation')).to eq(0)

      textarea.press('ControlLeft')
      expect(page.evaluate('keyLocation')).to eq(1)

      textarea.press('ControlRight')
      expect(page.evaluate('keyLocation')).to eq(2)

      textarea.press('NumpadSubtract')
      expect(page.evaluate('keyLocation')).to eq(3)
    end
  end

  it 'should throw on unknown keys' do
    with_test_state do |page:, **|
      expect { page.keyboard.press('NotARealKey') }.to raise_error(/Unknown key: "NotARealKey"/)
    end
  end

  it 'should type emoji' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
      page.type_text('textarea', '👹 Tokyo street Japan 🇯🇵')
      expect(page.eval_on_selector('textarea', '(textarea) => textarea.value')).to eq('👹 Tokyo street Japan 🇯🇵')
    end
  end

  it 'should type emoji into an iframe' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/empty.html")
      attach_frame(page, 'emoji-test', "#{server.prefix}/input/textarea.html")
      frame = page.frames[1]
      textarea = frame.query_selector('textarea')
      textarea.type_text('👹 Tokyo street Japan 🇯🇵')
      expect(frame.eval_on_selector('textarea', '(textarea) => textarea.value')).to eq('👹 Tokyo street Japan 🇯🇵')
    end
  end

  it 'should press the meta key' do
    with_test_state do |page:, **|
      skip('This test only runs on macOS.') unless Puppeteer.env.darwin?

      page.evaluate(<<~JAVASCRIPT)
      () => {
        globalThis.result = null;
        document.addEventListener('keydown', (event) => {
          globalThis.result = [event.key, event.code, event.metaKey];
        });
      }
      JAVASCRIPT
      page.keyboard.press('Meta')

      key, code, meta_key = page.evaluate('result')
      expect(key).to eq('Meta')
      expect(code).to eq('MetaLeft')
      expect(meta_key).to eq(true)
    end
  end
end
