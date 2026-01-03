require 'spec_helper'

RSpec.describe 'AriaQueryHandler' do
  describe 'parseAreaSelector' do
    selectors = [
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
    ]

    selectors.each do |selector|
      it "selector=#{selector} should find element" do
        with_test_state do |page:, **|
          page.content = '<button id="btn" role="button"> Submit  button   and some spaces  </button>'
          button = page.query_selector(selector)
          found = button.evaluate('(button) => button.id') == 'btn'
          expect(found).to eq(true)
        end
      end
    end
  end

  describe 'query_one' do
    it 'should find button by role' do
      with_test_state do |page:, **|
        page.content = '<div id="div"><button id="btn" role="button">Submit</button></div>'
        button = page.query_selector('aria/[role="button"]')
        expect(button.evaluate('(button) => button.id')).to eq('btn')
      end
    end

    it 'should find button by name and role' do
      with_test_state do |page:, **|
        page.content = '<div id="div"><button id="btn" role="button">Submit</button></div>'
        button = page.query_selector('aria/Submit[role="button"]')
        expect(button.evaluate('(button) => button.id')).to eq('btn')
      end
    end

    it 'should find first matching element' do
      with_test_state do |page:, **|
        page.content = 2.times.map { |i| "<div role=\"menu\" id=\"mnu#{i}\" aria-label=\"menu div\"></div>" }.join('')
        div = page.query_selector('aria/menu div')
        expect(div.evaluate('(div) => div.id')).to eq('mnu0')
      end
    end

    it 'should find by name' do
      with_test_state do |page:, **|
        page.content = 2.times.map { |i| "<div role=\"menu\" id=\"mnu#{i}\" aria-label=\"menu-label#{i}\"></div>" }.join('')
        div = page.query_selector('aria/menu-label1')
        expect(div.evaluate('(div) => div.id')).to eq('mnu1')
        div = page.query_selector('aria/menu-label0')
        expect(div.evaluate('(div) => div.id')).to eq('mnu0')
      end
    end
  end

  describe 'query_all' do
    it 'should find by name' do
      with_test_state do |page:, **|
        page.content = 2.times.map { |i| "<div role=\"menu\" id=\"mnu#{i}\" aria-label=\"menu div\"></div>" }.join('')
        div = page.query_selector_all('aria/menu div')
        expect(div[0].evaluate('(div) => div.id')).to eq('mnu0')
        expect(div[1].evaluate('(div) => div.id')).to eq('mnu1')
      end
    end
  end

  describe 'query_all_array' do
    it 'eval_on_selector_all should handle many elements' do
      with_test_state do |page:, **|
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
  end

  describe 'wait_for_selector (aria)' do
    let(:add_element) { '(tag) => document.body.appendChild(document.createElement(tag))' }

    it 'should immediately resolve promise if node exists' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.evaluate(add_element, 'button')
        Timeout.timeout(1) { page.wait_for_selector('aria/[role="button"]') }
      end
    end

    it 'should return the element handle' do
      with_test_state do |page:, **|
        page.evaluate(<<~JAVASCRIPT)
          () => (document.body.innerHTML = `<div></div>`)
        JAVASCRIPT
        element = page.query_selector('div')
        inner_element = element.wait_for_selector('aria/test') do
          element.evaluate(<<~JAVASCRIPT)
            el => el.innerHTML="<p><button>test</button></p>"
          JAVASCRIPT
        end
        expect(inner_element.evaluate('el => el.outerHTML')).to eq('<button>test</button>')
      end
    end

    it 'should persist query handler bindings across reloads' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.evaluate(add_element, 'button')
        Timeout.timeout(1) { page.wait_for_selector('aria/[role="button"]') }
        page.reload
        page.evaluate(add_element, 'button')
        Timeout.timeout(1) { page.wait_for_selector('aria/[role="button"]') }
      end
    end

    it 'should persist query handler bindings across navigations' do
      with_test_state do |page:, server:, **|
        # Reset page but make sure that execution context ids start with 1.
        page.goto('data:text/html,')
        page.goto(server.empty_page)
        page.evaluate(add_element, 'button')
        Timeout.timeout(1) { page.wait_for_selector('aria/[role="button"]') }

        # Reset page but again make sure that execution context ids start with 1.
        page.goto('data:text/html,')
        page.goto(server.empty_page)
        page.evaluate(add_element, 'button')
        Timeout.timeout(1) { page.wait_for_selector('aria/[role="button"]') }
      end
    end

    it 'should work independently of `exposeFunction`' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        page.expose_function('ariaQuerySelector', ->(a, b) { a + b })
        page.evaluate(add_element, 'button')
        page.wait_for_selector('aria/[role="button"]')
        result = page.evaluate('globalThis.ariaQuerySelector(2,8)')
        expect(result).to eq(10)
      end
    end

    it 'should wait for visible' do
      with_test_state do |page:, **|
        wait_for_selector_task = page.async_wait_for_selector('aria/name', visible: true)
        page.content = "<div aria-label='name' style='display: none; visibility: hidden;'>1</div>"

        expect(wait_for_selector_task.completed?).to eq(false)
        page.evaluate(<<~JAVASCRIPT)
        () => document.querySelector('div').style.removeProperty('display')
        JAVASCRIPT
        expect(wait_for_selector_task.completed?).to eq(false)
        page.evaluate(<<~JAVASCRIPT)
        () => document.querySelector('div').style.removeProperty('visibility')
        JAVASCRIPT
        wait_for_selector_task.wait
        expect(wait_for_selector_task.completed?).to eq(true)
      end
    end

    it 'should return the element handle' do
      with_test_state do |page:, **|
        result = page.wait_for_selector('aria/zombo') do
          page.content = "<div aria-label='zombo'>anything</div>"
        end
        expect(result).to be_a(Puppeteer::ElementHandle)
        expect(page.evaluate('(x) => x.textContent', result)).to eq('anything')
      end
    end
  end
end
