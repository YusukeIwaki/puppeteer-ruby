require 'spec_helper'

RSpec.describe "Legacy Drag n' Drop" do
  def drag_state(page)
    page.eval_on_selector('#drag-state', '(element) => element.innerHTML').to_i
  end

  it 'should emit a dragIntercepted event when dragged' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      expect(page.drag_interception_enabled?).to eq(false)
      page.drag_interception_enabled = true
      expect(page.drag_interception_enabled?).to eq(true)

      draggable = page.query_selector('#drag')
      data = draggable.drag(Puppeteer::ElementHandle::Point.new(x: 1, y: 1))

      expect(data).to be_a(Hash)
      expect(data['items'].length).to eq(1)
      expect(drag_state(page)).to eq(1)
    end
  end

  it 'should emit a dragEnter' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      expect(page.drag_interception_enabled?).to eq(false)
      page.drag_interception_enabled = true
      expect(page.drag_interception_enabled?).to eq(true)

      draggable = page.query_selector('#drag')
      data = draggable.drag(Puppeteer::ElementHandle::Point.new(x: 1, y: 1))
      expect(data).to be_a(Hash)
      dropzone = page.query_selector('#drop')
      dropzone.drag_enter(data)

      expect(drag_state(page)).to eq(12)
    end
  end

  it 'should emit a dragOver event' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      expect(page.drag_interception_enabled?).to eq(false)
      page.drag_interception_enabled = true
      expect(page.drag_interception_enabled?).to eq(true)

      draggable = page.query_selector('#drag')
      data = draggable.drag(Puppeteer::ElementHandle::Point.new(x: 1, y: 1))
      expect(data).to be_a(Hash)
      dropzone = page.query_selector('#drop')
      dropzone.drag_enter(data)
      dropzone.drag_over(data)

      expect(drag_state(page)).to eq(123)
    end
  end

  it 'can be dropped' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      expect(page.drag_interception_enabled?).to eq(false)
      page.drag_interception_enabled = true
      expect(page.drag_interception_enabled?).to eq(true)

      draggable = page.query_selector('#drag')
      dropzone = page.query_selector('#drop')
      data = draggable.drag(Puppeteer::ElementHandle::Point.new(x: 1, y: 1))
      expect(data).to be_a(Hash)
      dropzone.drag_enter(data)
      dropzone.drag_over(data)
      dropzone.drop(data)

      expect(drag_state(page)).to eq(12334)
    end
  end

  it 'can be dragged and dropped with a single function' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      expect(page.drag_interception_enabled?).to eq(false)
      page.drag_interception_enabled = true
      expect(page.drag_interception_enabled?).to eq(true)

      draggable = page.query_selector('#drag')
      dropzone = page.query_selector('#drop')
      draggable.drag_and_drop(dropzone)

      expect(drag_state(page)).to eq(12334)
    end
  end
end

RSpec.describe "Drag n' Drop" do
  def drag_state(page)
    page.eval_on_selector('#drag-state', '(element) => element.innerHTML').to_i
  end

  it 'should drop' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")

      draggable = page.query_selector('#drag')
      dropzone = page.query_selector('#drop')

      dropzone.drop(draggable)

      expect(drag_state(page)).to eq(1234)
    end
  end

  it 'should drop using mouse' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")

      draggable = page.query_selector('#drag')
      dropzone = page.query_selector('#drop')

      draggable.hover
      page.mouse.down
      dropzone.hover

      expect(drag_state(page)).to eq(123)

      page.mouse.up
      expect(drag_state(page)).to eq(1234)
    end
  end

  it 'should drag and drop' do
    # Upstream TestExpectations.json marks this FAIL on chrome/cdp: the
    # drop re-hovers the dropzone, appending a second dragover (12334, also
    # observed with upstream puppeteer-core 25.11.0 on this Chrome). Keep the
    # upstream assertion executing and record the known failure.
    pending('upstream FAIL expectation on chrome/cdp (TestExpectations.json)')
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")

      draggable = page.query_selector('#drag')
      dropzone = page.query_selector('#drop')

      draggable.drag(dropzone)
      dropzone.drop(draggable)

      expect(drag_state(page)).to eq(1234)
    end
  end

  it 'should release the mouse button when the drop fails' do
    with_test_state do |page:, **|
      # The page re-renders while the drag is in flight, which detaches the
      # dragged node, as a reactive list would. The drop then fails.
      page.set_content(<<~HTML)
        <div id="drag">drag me</div>
        <div id="drop">drop here</div>
        <script>
          let rerendered = false;
          document.addEventListener('mousemove', () => {
            if (rerendered) {
              return;
            }
            rerendered = true;
            const drag = document.getElementById('drag');
            drag.replaceWith(drag.cloneNode(true));
          });
        </script>
      HTML

      draggable = page.query_selector('#drag')
      dropzone = page.query_selector('#drop')

      draggable.drag(dropzone)
      expect { dropzone.drop(draggable) }.to raise_error(StandardError)

      # The drag pressed the mouse button down. If the failed drop leaves it
      # pressed, every later mouse event still carries it, and the next click
      # fires twice.
      page.evaluate(<<~JAVASCRIPT)
        () => {
          globalThis.buttons = undefined;
          document.addEventListener('mousemove', event => { globalThis.buttons = event.buttons; }, {once: true});
        }
      JAVASCRIPT
      page.mouse.move(20, 20)

      expect(page.evaluate('() => globalThis.buttons')).to eq(0)
    end
  end
end
