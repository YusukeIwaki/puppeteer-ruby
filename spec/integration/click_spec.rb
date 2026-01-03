require 'spec_helper'

RSpec.describe Puppeteer::Page do
  include Utils::AttachFrame

  it 'should click button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      page.click('button')
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end

  it 'should click button even if window.Node is removed' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      page.evaluate('() => delete window.Node')
      page.click('button')
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end

  it 'should fail to click a missing button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      expect { page.click('button.does-not-exist') }.to raise_error(/No node found for selector: button.does-not-exist/)
    end
  end

  it 'should click svg' do
    with_test_state do |page:, **|
      page.content = <<~SVG
      <svg height="100" width="100">
        <circle onclick="javascript:window.__CLICKED=42" cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
      </svg>
      SVG

      page.click('circle')
      expect(page.evaluate('() => globalThis.__CLICKED')).to eq(42)
    end
  end

  # https://github.com/puppeteer/puppeteer/issues/4281
  it 'should click on a span with an inline element inside' do
    with_test_state do |page:, **|
      page.content = <<~HTML
      <style>
      span::before {
        content: 'q';
      }
      </style>
      <span onclick='javascript:window.CLICKED=42'></span>
      HTML

      page.click('span')
      expect(page.evaluate('() => globalThis.CLICKED')).to eq(42)
    end
  end

  it 'should click the button after navigation' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      page.click('button')
      page.goto("#{server.prefix}/input/button.html")
      page.click('button')
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end

  it 'should click with disabled javascript' do
    with_test_state do |page:, server:, **|
      page.javascript_enabled = false
      page.goto("#{server.prefix}/wrappedlink.html")

      page.wait_for_navigation do
        page.click('a')
      end
      expect(page.url).to eq("#{server.prefix}/wrappedlink.html#clicked")
    end
  end

  it 'should click when one of inline box children is outside of viewport' do
    with_test_state do |page:, **|
      page.content = <<~HTML
      <style>
      i {
        position: absolute;
        top: -1000px;
      }
      </style>
      <span onclick='javascript:window.CLICKED = 42;'><i>woof</i><b>doggo</b></span>
      HTML
      page.click('span')
      expect(page.evaluate('() => globalThis.CLICKED')).to eq(42)
    end
  end

  it 'should select the text by triple clicking' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/textarea.html")
      page.focus('textarea')
      text = "This is the text that we are going to try to select. Let's see how it goes."
      page.keyboard.type_text(text)
      page.click('textarea')
      page.click('textarea', click_count: 2)
      page.click('textarea', click_count: 3)

      selected_text = page.evaluate(<<~JAVASCRIPT)
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

  it 'should click offscreen buttons' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/offscreenbuttons.html")
      messages = []
      page.on('console') do |message|
        messages << message.text if message.log_type == 'log'
      end
      11.times do |i|
        # We might've scrolled to click a button - reset to (0, 0).
        page.evaluate('() => window.scrollTo(0, 0)')
        page.click("#btn#{i}")
      end
      expect(messages).to eq([
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
      ])
    end
  end

  it 'should click wrapped link' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/wrappedlink.html")
      page.click('a')
      expect(page.evaluate('() => globalThis.__clicked')).to eq(true)
    end
  end

  it 'should click on checkbox input and toggle' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/checkbox.html")
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
  end

  it 'should click on checkbox label and toggle' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/checkbox.html")
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

  it 'should not hang with touch-enabled viewports' do
    with_test_state do |page:, **|
      page.viewport = Puppeteer::Devices.iPhone_6.viewport
      expect {
        Timeout.timeout(2) do
          page.mouse.down
          page.mouse.move(100, 10)
          page.mouse.up
        end
      }.not_to raise_error(Timeout::Error)
    end
  end

  it 'should scroll and click the button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/scrollable.html")
      page.click('#button-5')
      expect(page.evaluate("() => document.querySelector('#button-5').textContent")).to eq('clicked')
      page.click('#button-80')
      expect(page.evaluate("() => document.querySelector('#button-80').textContent")).to eq('clicked')
    end
  end

  it 'should double click button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      page.evaluate(<<~JAVASCRIPT)
      () => {
        globalThis.double = false;
        const button = document.querySelector('button');
        button.addEventListener('dblclick', () => {
          globalThis.double = true;
        });
      }
      JAVASCRIPT

      page.click('button', click_count: 2)
      expect(page.evaluate('() => globalThis.double')).to eq(true)
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end

  it 'should click a partially obscured button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      page.evaluate(<<~JAVASCRIPT)
      () => {
        const button = document.querySelector('button');
        button.textContent = 'Some really long text that will go offscreen';
        button.style.position = 'absolute';
        button.style.left = '368px';
      }
      JAVASCRIPT

      page.click('button')
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end

  it 'should click a rotated button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/rotatedButton.html")
      page.click('button')
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end

  it 'should fire contextmenu event on right click' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/scrollable.html")
      page.click('#button-8', button: 'right')
      expect(page.evaluate("() => document.querySelector('#button-8').textContent")).to eq('context menu')
    end
  end

  # https://github.com/puppeteer/puppeteer/issues/206
  it 'should click links which cause navigation' do
    with_test_state do |page:, server:, **|
      page.content = "<a href=\"#{server.empty_page}\">empty.html</a>"
      expect {
        Timeout.timeout(2) do
          page.click('a')
        end
      }.not_to raise_error(Timeout::Error)
    end
  end

  it 'should click the button inside an iframe' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      page.content = '<div style="width:100px;height:100px">spacer</div>'
      attach_frame(page, 'button-test', '/input/button.html')

      frame = page.frames.last
      frame.query_selector('button').click
      expect(frame.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end

  it 'should click the button with deviceScaleFactor set' do
    with_test_state do |page:, server:, **|
      page.viewport = Puppeteer::Viewport.new(width: 400, height: 400, device_scale_factor: 5)
      unless page.evaluate('() => window.devicePixelRatio') == 5
        raise 'something wrong...'
      end

      page.goto(server.empty_page)
      page.content = '<div style="width:100px;height:100px">spacer</div>'
      attach_frame(page, 'button-test', '/input/button.html')

      frame = page.frames.last
      frame.query_selector('button').click
      expect(frame.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end
end
