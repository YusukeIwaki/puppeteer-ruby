require 'spec_helper'

RSpec.describe 'Keyboard (white-box / Ruby-specific)' do
  def with_textarea(&block)
    with_test_state do |page:, **|
      page.evaluate(<<~JAVASCRIPT)
      () => {
        const textarea = document.createElement('textarea');
        document.body.appendChild(textarea);
        textarea.focus();
      }
      JAVASCRIPT
      block.call(page: page)
    end
  end

  it 'should input ( by type_text method' do
    with_textarea do |page:|
      text = '(puppeteer)'
      page.keyboard.type_text(text)
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq(text)
    end
  end

  it 'should input ( by pressing Shift + 9' do
    with_textarea do |page:|
      page.keyboard do
        down('Shift')
        press('Digit9')
        up('Shift')
      end
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('(')
    end
  end

  it 'should input <' do
    with_textarea do |page:|
      text = '<puppeteer>'
      page.keyboard.type_text(text)
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq(text)
    end
  end

  it 'should input < by pressing Shift + ,' do
    with_textarea do |page:|
      page.keyboard do
        down('Shift')
        press('Comma')
        up('Shift')
      end
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('<')
    end
  end

  describe 'block DSL' do
    it 'should input < by pressing Shift + , using press with block' do
      with_textarea do |page:|
        page.keyboard do
          press('Shift') do
            press('Comma')
          end
        end
        expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('<')
      end
    end

    it 'can use press, send_text with block' do
      with_test_state do |page:, **|
        page.content = '<html><body><input id="editor" type="text" /></body></html>'
        page.click('input')
        page.keyboard {
          type_text '123456789'
          down 'Shift'
          5.times { press 'ArrowLeft' }
          up 'Shift'
          send_character('a')
        }
        expect(page.query_selector('input').evaluate('(el) => el.value')).to eq('1234a')
      end
    end
  end
end
