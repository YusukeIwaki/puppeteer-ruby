require 'spec_helper'

RSpec.describe 'Input.drag' do
  it 'should throw an exception if not enabled before usage' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      draggable = page.query_selector('#drag')

      expect { draggable.drag(x: 1, y: 1) }.to raise_error(/Drag Interception is not enabled!/)
    end
  end

  it 'should emit a dragIntercepted event when dragged' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      expect(page.drag_interception_enabled?).to eq(false)
      page.drag_interception_enabled = true
      expect(page.drag_interception_enabled?).to eq(true)

      draggable = page.query_selector('#drag')
      data = draggable.drag(x: 1, y: 1)
      expect(data['items'].size).to eq(1)
      expect(page.evaluate('() => globalThis.didDragStart')).to eq(true)
    end
  end

  it 'should emit a dragEnter' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      page.drag_interception_enabled = true

      draggable = page.query_selector('#drag')
      dropzone = page.query_selector('#drop')
      data = draggable.drag(x: 1, y: 1)
      dropzone.drag_enter(data)

      expect(page.evaluate('() => globalThis.didDragStart')).to eq(true)
      expect(page.evaluate('() => globalThis.didDragEnter')).to eq(true)
    end
  end

  it 'should emit a dragOver event' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      page.drag_interception_enabled = true

      draggable = page.query_selector('#drag')
      dropzone = page.query_selector('#drop')
      data = draggable.drag(x: 1, y: 1)
      dropzone.drag_enter(data)
      dropzone.drag_over(data)

      expect(page.evaluate('() => globalThis.didDragStart')).to eq(true)
      expect(page.evaluate('() => globalThis.didDragEnter')).to eq(true)
      expect(page.evaluate('() => globalThis.didDragOver')).to eq(true)
    end
  end

  it 'can be dropped' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      page.drag_interception_enabled = true

      draggable = page.query_selector('#drag')
      dropzone = page.query_selector('#drop')
      data = draggable.drag(x: 1, y: 1)
      dropzone.drag_enter(data)
      dropzone.drag_over(data)
      dropzone.drop(data)

      expect(page.evaluate('() => globalThis.didDragStart')).to eq(true)
      expect(page.evaluate('() => globalThis.didDragEnter')).to eq(true)
      expect(page.evaluate('() => globalThis.didDragOver')).to eq(true)
      expect(page.evaluate('() => globalThis.didDrop')).to eq(true)
    end
  end

  it 'can be dragged and dropped with a single function' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      page.drag_interception_enabled = true

      draggable = page.query_selector('#drag')
      dropzone = page.query_selector('#drop')
      draggable.drag_and_drop(dropzone)

      expect(page.evaluate('() => globalThis.didDragStart')).to eq(true)
      expect(page.evaluate('() => globalThis.didDragEnter')).to eq(true)
      expect(page.evaluate('() => globalThis.didDragOver')).to eq(true)
      expect(page.evaluate('() => globalThis.didDrop')).to eq(true)
    end
  end

  it 'can be disabled' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/drag-and-drop.html")
      page.drag_interception_enabled = true

      draggable = page.query_selector('#drag')
      draggable.drag(x: 1, y: 1)
      page.drag_interception_enabled = false
      expect { draggable.drag(x: 1, y: 1) }.to raise_error(/Drag Interception is not enabled!/)
    end
  end
end
