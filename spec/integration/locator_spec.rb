require 'spec_helper'

RSpec.describe 'Locator' do
  it 'should work with a frame' do
    with_test_state do |page:, **|
      page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
      page.content = <<~HTML
        <button onclick="this.innerText = 'clicked';">test</button>
      HTML
      will_click = false
      page
        .main_frame
        .locator('button')
        .on(Puppeteer::LocatorEvent::Action) { will_click = true }
        .click
      button = page.query_selector('button')
      text = button.evaluate('(el) => el.innerText')
      expect(text).to eq('clicked')
      expect(will_click).to eq(true)
    end
  end

  it 'should work without preconditions' do
    with_test_state do |page:, **|
      page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
      page.content = <<~HTML
        <button onclick="this.innerText = 'clicked';">test</button>
      HTML
      will_click = false
      page
        .locator('button')
        .set_ensure_element_is_in_the_viewport(false)
        .set_timeout(0)
        .set_visibility(nil)
        .set_wait_for_enabled(false)
        .set_wait_for_stable_bounding_box(false)
        .on(Puppeteer::LocatorEvent::Action) { will_click = true }
        .click
      button = page.query_selector('button')
      text = button.evaluate('(el) => el.innerText')
      expect(text).to eq('clicked')
      expect(will_click).to eq(true)
    end
  end

  describe 'Locator.click' do
    it 'should work' do
      with_test_state do |page:, **|
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <button onclick="this.innerText = 'clicked';">test</button>
        HTML
        will_click = false
        page
          .locator('button')
          .on(Puppeteer::LocatorEvent::Action) { will_click = true }
          .click
        button = page.query_selector('button')
        text = button.evaluate('(el) => el.innerText')
        expect(text).to eq('clicked')
        expect(will_click).to eq(true)
      end
    end

    it 'should work for multiple selectors' do
      with_test_state do |page:, **|
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <button onclick="this.innerText = 'clicked';">test</button>
        HTML
        clicked = false
        page
          .locator('::-p-text(test), ::-p-xpath(/button)')
          .on(Puppeteer::LocatorEvent::Action) { clicked = true }
          .click
        button = page.query_selector('button')
        text = button.evaluate('(el) => el.innerText')
        expect(text).to eq('clicked')
        expect(clicked).to eq(true)
      end
    end

    it 'should work if the element is out of viewport' do
      with_test_state do |page:, **|
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <button
            style="margin-top: 600px;"
            onclick="this.innerText = 'clicked';"
          >
            test
          </button>
        HTML
        page.locator('button').click
        button = page.query_selector('button')
        text = button.evaluate('(el) => el.innerText')
        expect(text).to eq('clicked')
      end
    end

    it 'should work with element handles' do
      with_test_state do |page:, **|
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <button
            style="margin-top: 600px;"
            onclick="this.innerText = 'clicked';"
          >
            test
          </button>
        HTML
        button = page.query_selector('button')
        raise 'button not found' unless button

        button.as_locator.click
        text = button.evaluate('(el) => el.innerText')
        expect(text).to eq('clicked')
      end
    end

    it 'should work if the element becomes visible later' do
      with_test_state do |page:, **|
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <button
            style="display: none;"
            onclick="this.innerText = 'clicked';"
          >test</button>
        HTML
        button = page.query_selector('button')
        click_promise = async_promise { page.locator('button').click }
        expect(button.evaluate('(el) => el.innerText')).to eq('test')
        button.evaluate("(el) => { el.style.display = 'block'; }")
        click_promise.wait
        expect(button.evaluate('(el) => el.innerText')).to eq('clicked')
      end
    end

    it 'should work if the element becomes enabled later' do
      with_test_state do |page:, **|
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <button
            disabled
            onclick="this.innerText = 'clicked';"
          >test</button>
        HTML
        button = page.query_selector('button')
        click_promise = async_promise { page.locator('button').click }
        expect(button.evaluate('(el) => el.innerText')).to eq('test')
        button.evaluate('(el) => { el.disabled = false; }')
        click_promise.wait
        expect(button.evaluate('(el) => el.innerText')).to eq('clicked')
      end
    end

    it 'should work if multiple conditions are satisfied later' do
      with_test_state do |page:, **|
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <button
            style="margin-top: 600px;"
            style="display: none;"
            disabled
            onclick="this.innerText = 'clicked';"
          >
            test
          </button>
        HTML
        button = page.query_selector('button')
        click_promise = async_promise { page.locator('button').click }
        expect(button.evaluate('(el) => el.innerText')).to eq('test')
        button.evaluate("(el) => { el.disabled = false; el.style.display = 'block'; }")
        click_promise.wait
        expect(button.evaluate('(el) => el.innerText')).to eq('clicked')
      end
    end

    it 'should time out' do
      with_test_state do |page:, **|
        page.default_timeout = 500
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <button
            style="display: none;"
            onclick="this.innerText = 'clicked';"
          >
            test
          </button>
        HTML
        click_promise = async_promise { page.locator('button').click }
        expect { click_promise.wait }.to raise_error(Puppeteer::TimeoutError)
      end
    end

    it 'should retry clicks on errors' do
      with_test_state do |page:, **|
        page.default_timeout = 500
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <button
            style="display: none;"
            onclick="this.innerText = 'clicked';"
          >
            test
          </button>
        HTML
        click_promise = async_promise { page.locator('button').click }
        expect { click_promise.wait }.to raise_error(Puppeteer::TimeoutError)
      end
    end

    it 'can be aborted' do
      skip('AbortSignal is not supported')
    end

    it 'should work with a OOPIF', enable_site_per_process_flag: true do
      with_test_state do |page:, **|
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <iframe
            src="data:text/html,<button onclick=&quot;this.innerText = 'clicked';&quot;>test</button>"
          ></iframe>
        HTML
        frame = page.wait_for_frame(predicate: ->(frame) { frame.url.start_with?('data') })
        will_click = false
        frame
          .locator('button')
          .on(Puppeteer::LocatorEvent::Action) { will_click = true }
          .click
        button = frame.query_selector('button')
        text = button.evaluate('(el) => el.innerText')
        expect(text).to eq('clicked')
        expect(will_click).to eq(true)
      end
    end
  end

  describe 'Locator.hover' do
    it 'should work' do
      with_test_state do |page:, **|
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <button onmouseenter="this.innerText = 'hovered';">test</button>
        HTML
        hovered = false
        page
          .locator('button')
          .on(Puppeteer::LocatorEvent::Action) { hovered = true }
          .hover
        button = page.query_selector('button')
        text = button.evaluate('(el) => el.innerText')
        expect(text).to eq('hovered')
        expect(hovered).to eq(true)
      end
    end
  end

  describe 'Locator.scroll' do
    it 'should work' do
      with_test_state do |page:, **|
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = <<~HTML
          <div style="height: 500px; width: 500px; overflow: scroll;">
            <div style="height: 1000px; width: 1000px;">test</div>
          </div>
        HTML
        scrolled = false
        page
          .locator('div')
          .on(Puppeteer::LocatorEvent::Action) { scrolled = true }
          .scroll(scroll_top: 500, scroll_left: 500)
        scrollable = page.query_selector('div')
        scroll = scrollable.evaluate('(el) => el.scrollTop + " " + el.scrollLeft')
        expect(scroll).to eq('500 500')
        expect(scrolled).to eq(true)
      end
    end
  end

  describe 'Locator.fill' do
    it 'should work for textarea' do
      with_test_state do |page:, **|
        page.content = '<textarea></textarea>'
        filled = false
        page
          .locator('textarea')
          .on(Puppeteer::LocatorEvent::Action) { filled = true }
          .fill('test')
        result = page.evaluate('() => document.querySelector("textarea")?.value === "test"')
        expect(result).to eq(true)
        expect(filled).to eq(true)
      end
    end

    it 'should work for selects' do
      with_test_state do |page:, **|
        page.content = <<~HTML
          <select>
            <option value="value1">Option 1</option>
            <option value="value2">Option 2</option>
          </select>
        HTML
        filled = false
        page
          .locator('select')
          .on(Puppeteer::LocatorEvent::Action) { filled = true }
          .fill('value2')
        result = page.evaluate('() => document.querySelector("select")?.value === "value2"')
        expect(result).to eq(true)
        expect(filled).to eq(true)
      end
    end

    it 'should work for inputs' do
      with_test_state do |page:, **|
        page.content = '<input />'
        page.locator('input').fill('test')
        result = page.evaluate('() => document.querySelector("input")?.value === "test"')
        expect(result).to eq(true)
      end
    end

    it 'should work if the input becomes enabled later' do
      with_test_state do |page:, **|
        page.content = '<input disabled />'
        input = page.query_selector('input')
        fill_promise = async_promise { page.locator('input').fill('test') }
        expect(input.evaluate('(el) => el.value')).to eq('')
        input.evaluate('(el) => { el.disabled = false; }')
        fill_promise.wait
        expect(input.evaluate('(el) => el.value')).to eq('test')
      end
    end

    it 'should work for contenteditable' do
      with_test_state do |page:, **|
        page.content = '<div contenteditable="true"></div>'
        page.locator('div').fill('test')
        result = page.evaluate('() => document.querySelector("div")?.innerText === "test"')
        expect(result).to eq(true)
      end
    end

    it 'should work for pre-filled inputs' do
      with_test_state do |page:, **|
        page.content = '<input value="te" />'
        page.locator('input').fill('test')
        result = page.evaluate('() => document.querySelector("input")?.value === "test"')
        expect(result).to eq(true)
      end
    end

    it 'should override pre-filled inputs' do
      with_test_state do |page:, **|
        page.content = '<input value="wrong prefix" />'
        page.locator('input').fill('test')
        result = page.evaluate('() => document.querySelector("input")?.value === "test"')
        expect(result).to eq(true)
      end
    end

    it 'should work for non-text inputs' do
      with_test_state do |page:, **|
        page.content = '<input type="color" />'
        page.locator('input').fill('#333333')
        result = page.evaluate('() => document.querySelector("input")?.value === "#333333"')
        expect(result).to eq(true)
      end
    end

    it 'should work with a custom typing threshold' do
      with_test_state do |page:, **|
        page.content = '<input />'
        text = 'abc'
        page.locator('input').fill(text, typing_threshold: 10)
        expect(page.evaluate('() => document.querySelector("input")?.value')).to eq(text)

        page.content = '<input />'
        page.locator('input').fill(text, typing_threshold: 2)
        expect(page.evaluate('() => document.querySelector("input")?.value')).to eq(text)
      end
    end
  end

  describe 'Locator.race' do
    it 'races multiple locators' do
      with_test_state do |page:, **|
        page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
        page.content = '<button onclick="window.count++;">test</button>'
        page.evaluate('() => { window.count = 0; }')
        Puppeteer::Locator.race([
          page.locator('button'),
          page.locator('button'),
        ]).click
        count = page.evaluate('() => globalThis.count')
        expect(count).to eq(1)
      end
    end

    it 'can be aborted' do
      skip('AbortSignal is not supported')
    end

    it 'should time out when all locators do not match' do
      with_test_state do |page:, **|
        page.content = '<button>test</button>'
        action = async_promise do
          Puppeteer::Locator.race([
            page.locator('not-found'),
            page.locator('not-found'),
          ]).set_timeout(500).click
        end
        expect { action.wait }.to raise_error(Puppeteer::TimeoutError)
      end
    end

    it 'should not time out when one of the locators matches' do
      with_test_state do |page:, **|
        page.content = '<button>test</button>'
        result = Puppeteer::Locator.race([
          page.locator('not-found'),
          page.locator('button'),
        ]).click
        expect(result).to be_nil
      end
    end
  end

  describe 'Locator.prototype.map' do
    it 'should work' do
      with_test_state do |page:, **|
        page.content = '<div>test</div>'
        expect(
          page
            .locator('::-p-text(test)')
            .map('(element) => element.getAttribute("clickable")')
            .wait,
        ).to eq(nil)
        page.evaluate('() => { document.querySelector("div")?.setAttribute("clickable", "true"); }')
        expect(
          page
            .locator('::-p-text(test)')
            .map('(element) => element.getAttribute("clickable")')
            .wait,
        ).to eq('true')
      end
    end

    it 'should work with throws' do
      with_test_state do |page:, **|
        page.content = '<div>test</div>'
        mapper = <<~JAVASCRIPT
          element => {
            const clickable = element.getAttribute('clickable');
            if (!clickable) {
              throw new Error('Missing `clickable` as an attribute');
            }
            return clickable;
          }
        JAVASCRIPT
        result = async_promise do
          page
            .locator('::-p-text(test)')
            .map(mapper)
            .wait
        end
        page.evaluate('() => { document.querySelector("div")?.setAttribute("clickable", "true"); }')
        expect(result.wait).to eq('true')
      end
    end

    it 'should work with expect' do
      with_test_state do |page:, **|
        page.content = '<div>test</div>'
        result = async_promise do
          page
            .locator('::-p-text(test)')
            .filter('(element) => element.getAttribute("clickable") !== null')
            .map('(element) => element.getAttribute("clickable")')
            .wait
        end
        page.evaluate('() => { document.querySelector("div")?.setAttribute("clickable", "true"); }')
        expect(result.wait).to eq('true')
      end
    end
  end

  describe 'Locator.prototype.filter' do
    it 'should resolve as soon as the predicate matches' do
      with_test_state do |page:, **|
        page.content = '<div>test</div>'
        result = async_promise do
          page
            .locator('::-p-text(test)')
            .set_timeout(5000)
            .filter('async (element) => element.getAttribute("clickable") === "true"')
            .filter('(element) => element.getAttribute("clickable") === "true"')
            .hover
        end
        Puppeteer::AsyncUtils.sleep_seconds(0.1)
        page.evaluate('() => { document.querySelector("div")?.setAttribute("clickable", "true"); }')
        expect(result.wait).to be_nil
      end
    end
  end

  describe 'Locator.prototype.wait' do
    it 'should work' do
      with_test_state do |page:, **|
        page.content = <<~HTML
          <script>
            setTimeout(() => {
              const element = document.createElement('div');
              element.innerText = 'test2';
              document.body.append(element);
            }, 50);
          </script>
        HTML
        page.locator('div').wait
      end
    end
  end

  describe 'Locator.prototype.waitHandle' do
    it 'should work' do
      with_test_state do |page:, **|
        page.content = <<~HTML
          <script>
            setTimeout(() => {
              const element = document.createElement('div');
              element.innerText = 'test2';
              document.body.append(element);
            }, 50);
          </script>
        HTML
        handle = page.locator('div').wait_handle
        expect(handle).not_to be_nil
      end
    end
  end

  describe 'Locator.prototype.clone' do
    it 'should work' do
      with_test_state do |page:, **|
        locator = page.locator('div')
        clone = locator.clone
        expect(locator).not_to eq(clone)
      end
    end

    it 'should work internally with delegated locators' do
      with_test_state do |page:, **|
        locator = page.locator('div')
        delegated_locators = [
          locator.map('(div) => div.textContent'),
          locator.filter('(div) => div.textContent?.length === 0'),
        ]
        delegated_locators.each do |delegated_locator|
          updated = delegated_locator.set_timeout(500)
          expect(updated.timeout).not_to eq(locator.timeout)
        end
      end
    end
  end

  describe 'FunctionLocator' do
    it 'should work' do
      with_test_state do |page:, **|
        result = page
          .locator('() => new Promise(resolve => setTimeout(() => resolve(true), 100))')
          .wait
        expect(result).to eq(true)
      end
    end

    it 'should work with actions' do
      with_test_state do |page:, **|
        page.content = '<div onclick="window.clicked = true">test</div>'
        page
          .locator('() => document.getElementsByTagName("div")[0]')
          .click
        clicked = page.evaluate('() => window.clicked')
        expect(clicked).to eq(true)
      end
    end
  end
end
