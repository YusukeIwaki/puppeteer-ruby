require 'spec_helper'

RSpec.describe Puppeteer::Mouse do
  def dimensions_js
    <<~JAVASCRIPT
    () => {
      const rect = document.querySelector('textarea').getBoundingClientRect();
      return {
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height,
      };
    }
    JAVASCRIPT
  end

  def add_mouse_data_listeners(page, include_move: false)
    page.evaluate(<<~JAVASCRIPT, { 'includeMove' => include_move })
    ({ includeMove }) => {
      const clicks = [];
      const mouseEventListener = event => {
        clicks.push({
          type: event.type,
          detail: event.detail,
          clientX: event.clientX,
          clientY: event.clientY,
          isTrusted: event.isTrusted,
          button: event.button,
          buttons: event.buttons,
        });
      };
      document.addEventListener('mousedown', mouseEventListener);
      if (includeMove) {
        document.addEventListener('mousemove', mouseEventListener);
      }
      document.addEventListener('mouseup', mouseEventListener);
      document.addEventListener('click', mouseEventListener);
      document.addEventListener('auxclick', mouseEventListener);
      globalThis.clicks = clicks;
    }
    JAVASCRIPT
  end

  it 'should click the document' do
    with_test_state do |page:, **|
      page.evaluate(<<~JAVASCRIPT)
      () => {
        globalThis.clickPromise = new Promise(resolve => {
          document.addEventListener('click', event => {
            resolve({
              type: event.type,
              detail: event.detail,
              clientX: event.clientX,
              clientY: event.clientY,
              isTrusted: event.isTrusted,
              button: event.button,
            });
          });
        });
      }
      JAVASCRIPT
      page.mouse.click(50, 60)
      event = page.evaluate('() => globalThis.clickPromise')
      expect(event['type']).to eq('click')
      expect(event['detail']).to eq(1)
      expect(event['clientX']).to eq(50)
      expect(event['clientY']).to eq(60)
      expect(event['isTrusted']).to eq(true)
      expect(event['button']).to eq(0)
    end
  end

  it 'should resize the textarea' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
      dimensions = page.evaluate(dimensions_js)
      x = dimensions['x']
      y = dimensions['y']
      width = dimensions['width']
      height = dimensions['height']
      mouse = page.mouse
      mouse.move(x + width - 4, y + height - 4)
      mouse.down
      mouse.move(x + width + 100, y + height + 100)
      mouse.up
      new_dimensions = page.evaluate(dimensions_js)
      expect(new_dimensions['width']).to eq((width + 104).round)
      expect(new_dimensions['height']).to eq((height + 104).round)
    end
  end

  it 'should select the text with mouse' do
    with_test_state do |page:, server:, **|
      text = "This is the text that we are going to try to select. Let's see how it goes."

      page.goto("#{server.prefix}/input/textarea.html")
      page.focus('textarea')
      page.keyboard.type_text(text)
      handle = page.wait_for_selector('textarea')
      dimensions = page.evaluate(dimensions_js)
      page.mouse.move(dimensions['x'] + 2, dimensions['y'] + 2)
      page.mouse.down
      page.mouse.move(100, 100)
      page.mouse.up
      selected_text = handle.evaluate(<<~JAVASCRIPT)
      (element) => {
        return element.value.substring(
          element.selectionStart,
          element.selectionEnd,
        );
      }
      JAVASCRIPT
      expect(selected_text).to eq(text)
    ensure
      handle&.dispose
    end
  end

  it 'should trigger hover state' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/scrollable.html")
      page.hover('#button-6')
      expect(page.evaluate("() => document.querySelector('button:hover').id")).to eq('button-6')
      page.hover('#button-2')
      expect(page.evaluate("() => document.querySelector('button:hover').id")).to eq('button-2')
      page.hover('#button-91')
      expect(page.evaluate("() => document.querySelector('button:hover').id")).to eq('button-91')
    end
  end

  it 'should trigger hover state with removed window.Node' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/scrollable.html")
      page.evaluate('() => delete window.Node')
      page.hover('#button-6')
      expect(page.evaluate("() => document.querySelector('button:hover').id")).to eq('button-6')
    end
  end

  it 'should set modifier keys on click' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/scrollable.html")
      page.evaluate(<<~JAVASCRIPT)
      () => {
        return document.querySelector('#button-3').addEventListener(
          'mousedown',
          e => {
            return (globalThis.lastEvent = e);
          },
          true,
        );
      }
      JAVASCRIPT
      modifiers = {
        'Shift' => 'shiftKey',
        'Control' => 'ctrlKey',
        'Alt' => 'altKey',
        'Meta' => 'metaKey',
      }
      modifiers.each do |modifier, key|
        page.keyboard.down(modifier)
        page.click('#button-3')
        expect(page.evaluate('(mod) => globalThis.lastEvent[mod]', key)).to eq(true)
        page.keyboard.up(modifier)
      end
      page.click('#button-3')
      modifiers.each do |_modifier, key|
        expect(page.evaluate('(mod) => globalThis.lastEvent[mod]', key)).to eq(false)
      end
    end
  end

  it 'should send mouse wheel events' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/wheel.html")
      element = page.query_selector('div')
      bounding_box_before = element.bounding_box
      expect(bounding_box_before.width).to eq(115)
      expect(bounding_box_before.height).to eq(115)

      page.mouse.move(
        bounding_box_before.x + bounding_box_before.width / 2,
        bounding_box_before.y + bounding_box_before.height / 2,
      )

      page.mouse.wheel(delta_y: -100)
      bounding_box_after = element.bounding_box
      expect(bounding_box_after.width).to eq(230)
      expect(bounding_box_after.height).to eq(230)
    ensure
      element&.dispose
    end
  end

  it 'should set ctrlKey on the wheel event' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      ctrl_key_promise = async_promise do
        page.evaluate(<<~JAVASCRIPT)
        () => {
          return new Promise(resolve => {
            window.addEventListener(
              'wheel',
              event => {
                resolve(event.ctrlKey);
              },
              {
                once: true,
              },
            );
          });
        }
        JAVASCRIPT
      end
      page.keyboard.down('Control')
      page.mouse.wheel(delta_y: -100)
      page.keyboard.up('Control')
      ctrl_key = await_promises(ctrl_key_promise).first
      expect(ctrl_key).to eq(true)
    end
  end

  it 'should tween mouse movement' do
    with_test_state do |page:, **|
      page.mouse.move(100, 100)
      page.evaluate(<<~JAVASCRIPT)
      () => {
        globalThis.result = [];
        document.addEventListener('mousemove', event => {
          globalThis.result.push([event.clientX, event.clientY]);
        });
      }
      JAVASCRIPT
      page.mouse.move(200, 300, steps: 5)
      expect(page.evaluate('() => globalThis.result')).to eq([
        [120, 140],
        [140, 180],
        [160, 220],
        [180, 260],
        [200, 300],
      ])
    end
  end

  # @see https://crbug.com/929806
  it 'should work with mobile viewports and cross process navigations' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      page.viewport = Puppeteer::Viewport.new(width: 360, height: 640, is_mobile: true)
      page.goto("#{server.cross_process_prefix}/mobile.html")
      page.evaluate(<<~JAVASCRIPT)
      () => {
        document.addEventListener('click', event => {
          globalThis.result = {x: event.clientX, y: event.clientY};
        });
      }
      JAVASCRIPT

      page.mouse.click(30, 40)

      expect(page.evaluate('() => globalThis.result')).to eq({ 'x' => 30, 'y' => 40 })
    end
  end

  it 'should not throw if buttons are pressed twice' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      page.mouse.down
      page.mouse.down
    end
  end

  it 'should not throw if clicking in parallel' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      add_mouse_data_listeners(page)

      await_promises(
        async_promise { page.mouse.click(0, 5) },
        async_promise { page.mouse.click(6, 10) },
      )

      data = page.evaluate('() => globalThis.clicks')
      common_attrs = {
        'isTrusted' => true,
        'detail' => 1,
        'clientY' => 5,
        'clientX' => 0,
        'button' => 0,
      }
      expect(data.shift(3)).to eq([
        common_attrs.merge('type' => 'mousedown', 'buttons' => 1),
        common_attrs.merge('type' => 'mouseup', 'buttons' => 0),
        common_attrs.merge('type' => 'click', 'buttons' => 0),
      ])
      second_attrs = common_attrs.merge('clientX' => 6, 'clientY' => 10)
      expect(data).to eq([
        second_attrs.merge('type' => 'mousedown', 'buttons' => 1),
        second_attrs.merge('type' => 'mouseup', 'buttons' => 0),
        second_attrs.merge('type' => 'click', 'buttons' => 0),
      ])
    end
  end

  it 'should reset properly' do
    skip('TODO: implement Mouse#reset and button state tracking')
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)

      page.mouse.move(5, 5)
      await_promises(
        async_promise { page.mouse.down(button: Puppeteer::Mouse::Button::LEFT) },
        async_promise { page.mouse.down(button: Puppeteer::Mouse::Button::MIDDLE) },
        async_promise { page.mouse.down(button: Puppeteer::Mouse::Button::RIGHT) },
      )

      add_mouse_data_listeners(page, include_move: true)
      page.mouse.reset

      data = page.evaluate('() => globalThis.clicks')
      common_attrs = {
        'isTrusted' => true,
        'clientY' => 5,
        'clientX' => 5,
      }

      expect(data.take(2)).to eq([
        common_attrs.merge('button' => 2, 'buttons' => 5, 'detail' => 1, 'type' => 'mouseup'),
        common_attrs.merge('button' => 2, 'buttons' => 5, 'detail' => 1, 'type' => 'auxclick'),
      ])
      expect(data.drop(2)).to eq([
        common_attrs.merge('button' => 1, 'buttons' => 1, 'detail' => 0, 'type' => 'mouseup'),
        common_attrs.merge('button' => 0, 'buttons' => 0, 'detail' => 0, 'type' => 'mouseup'),
      ])
    end
  end

  it 'should evaluate before mouse event' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      page.goto("#{server.cross_process_prefix}/input/button.html")

      button = page.wait_for_selector('button')
      point = button.clickable_point

      result_promise = async_promise do
        page.evaluate(<<~JAVASCRIPT)
        () => {
          return new Promise(resolve => {
            document
              .querySelector('button')
              ?.addEventListener('click', resolve, { once: true });
          });
        }
        JAVASCRIPT
      end
      page.mouse.click(point.x, point.y)
      await_promises(result_promise)
    ensure
      button&.dispose
    end
  end
end
