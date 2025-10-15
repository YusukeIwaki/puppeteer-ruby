require 'spec_helper'

RSpec.describe Puppeteer::Frame do
  describe '#execution_context' do
    include Utils::AttachFrame

    it 'should work', sinatra: true do
      page.goto(server_empty_page)
      attach_frame(page, 'frame1', server_empty_page)
      expect(page.frames.size).to eq(2)

      frames = page.frames
      contexts = frames.map(&:execution_context)
      expect(contexts).to all(be_truthy)
      expect(contexts.first).not_to eq(contexts.last)

      contexts.each_with_index do |context, i|
        context.evaluate("() => (globalThis.a = #{i + 1})")
      end
      values = contexts.map { |context| context.evaluate('() => globalThis.a') }
      expect(values).to eq([1, 2])
    end
  end

  describe '#evaluate_handle' do
    it 'should work', sinatra: true do
      page.goto(server_empty_page)
      main_frame = page.main_frame
      window_handle = main_frame.evaluate_handle('() => window')
      expect(window_handle).to be_truthy
    end
  end

  describe '#evaluate' do
    include Utils::AttachFrame
    include Utils::DetachFrame

    it 'should throw for detached frames', sinatra: true do
      page.goto(server_empty_page)
      frame1 = attach_frame(page, 'frame1', server_empty_page)
      detach_frame(page, 'frame1')
      expect {
        frame1.evaluate('() => 7 * 8')
      }.to raise_error(/Execution Context is not available in detached frame|Cannot find context/)
    end
  end

  describe '#page' do
    it 'should retrieve the page from a frame', sinatra: true do
      page.goto(server_empty_page)
      expect(page.main_frame.page).to eq(page)
    end
  end

  describe 'Frame Management', sinatra: true do
    include Utils::AttachFrame
    include Utils::DetachFrame
    include Utils::DumpFrames
    include Utils::NavigateFrame

    it 'should handle nested frames' do
      page.goto("#{server_prefix}/frames/nested-frames.html")
      expect(dump_frames(page.main_frame)).to eq([
        'http://localhost:<PORT>/frames/nested-frames.html',
        '    http://localhost:<PORT>/frames/two-frames.html (2frames)',
        '        http://localhost:<PORT>/frames/frame.html (uno)',
        '        http://localhost:<PORT>/frames/frame.html (dos)',
        '    http://localhost:<PORT>/frames/frame.html (aframe)',
      ])
    end

    it_fails_firefox 'should send events when frames are manipulated dynamically' do
      page.goto(server_empty_page)

      # validate frameattached events
      attached_frames = []
      page.on('frameattached') do |frame|
        attached_frames << frame
      end

      attach_frame(page, 'frame1', './assets/frame.html')
      expect(attached_frames.size).to eq(1)
      expect(attached_frames.first.url).to include('/assets/frame.html')

      # validate framenavigated events
      navigated_frames = []
      page.on('framenavigated') do |frame|
        navigated_frames << frame
      end
      navigate_frame(page, 'frame1', './empty.html')
      expect(navigated_frames.size).to eq(1)
      expect(navigated_frames.first.url).to eq(server_empty_page)

      # validate framedetached events
      detached_frames = []
      page.on('framedetached') do |frame|
        detached_frames << frame
      end
      detach_frame(page, 'frame1')
      expect(detached_frames.size).to eq(1)
      expect(detached_frames.first).to be_detached
    end

    it 'should send "framenavigated" when navigating on anchor URLs' do
      page.goto(server_empty_page)
      Timeout.timeout(5) do
        framenavigated_promise = Concurrent::Promises.resolvable_future.tap do |future|
          page.once('framenavigated') { |frame| future.fulfill(frame) }
        end
        Puppeteer::ConcurrentRubyUtils.with_waiting_for_complete(framenavigated_promise) do
          page.goto("#{server_empty_page}#foo")
        end
        expect(page.url).to eq("#{server_empty_page}#foo")
      end
    end

    it 'should persist mainFrame on cross-process navigation' do
      page.goto(server_empty_page)
      main_frame = page.main_frame
      page.goto("#{server_cross_process_prefix}/empty.html")
      expect(page.main_frame).to eq(main_frame)
    end

    it 'should not send attach/detach events for main frame' do
      has_events = false
      page.on('frameattached') { has_events = true }
      page.on('framedetached') { has_events = true }

      page.goto(server_empty_page)
      expect(has_events).to eq(false)
    end

    it 'should detach child frames on navigation' do
      attached_frames = []
      detached_frames = []
      navigated_frames = []
      page.on('frameattached') { |frame| attached_frames << frame }
      page.on('framedetached') { |frame| detached_frames << frame }
      page.on('framenavigated') { |frame| navigated_frames << frame }

      page.goto("#{server_prefix}/frames/nested-frames.html")
      expect(attached_frames.size).to eq(4)
      expect(detached_frames.size).to eq(0)
      expect(navigated_frames.size).to eq(5)

      attached_frames.clear
      detached_frames.clear
      navigated_frames.clear

      page.goto(server_empty_page)
      expect(attached_frames.size).to eq(0)
      expect(detached_frames.size).to eq(4)
      expect(navigated_frames.size).to eq(1)
    end

    it 'should support framesets' do
      attached_frames = []
      detached_frames = []
      navigated_frames = []
      page.on('frameattached') { |frame| attached_frames << frame }
      page.on('framedetached') { |frame| detached_frames << frame }
      page.on('framenavigated') { |frame| navigated_frames << frame }

      page.goto("#{server_prefix}/frames/frameset.html")
      expect(attached_frames.size).to eq(4)
      expect(detached_frames.size).to eq(0)
      expect(navigated_frames.size).to eq(5)

      attached_frames.clear
      detached_frames.clear
      navigated_frames.clear

      page.goto(server_empty_page)
      expect(attached_frames.size).to eq(0)
      expect(detached_frames.size).to eq(4)
      expect(navigated_frames.size).to eq(1)
    end

    it 'should report frame from-inside shadow DOM' do
      page.goto("#{server_prefix}/shadow.html")
      js = <<~JAVASCRIPT
      async function (url) {
        const frame = document.createElement('iframe');
        frame.src = url;
        document.body.shadowRoot.appendChild(frame);
        await new Promise((x) => (frame.onload = x));
      }
      JAVASCRIPT
      page.evaluate(js, server_empty_page)
      expect(page.frames.size).to eq(2)
      expect(page.frames.last.url).to eq(server_empty_page)
    end


    it 'should report frame.name()' do
      page.goto(server_empty_page)
      attach_frame(page, 'theFrameId', '/')
      js = <<~JAVASCRIPT
      function (url) {
        const frame = document.createElement('iframe');
        frame.name = 'theFrameName';
        frame.src = url;
        document.body.appendChild(frame);
        return new Promise((x) => (frame.onload = x));
      }
      JAVASCRIPT
      page.evaluate(js, server_empty_page)
      expect(page.frames.map(&:name)).to eq(['', 'theFrameId', 'theFrameName'])
    end

    it 'should report frame.parent()' do
      attach_frame(page, 'frame1', server_empty_page)
      attach_frame(page, 'frame2', server_empty_page)
      expect(page.frames.map(&:parent_frame)).to eq([nil, page.main_frame, page.main_frame])
    end

    it_fails_firefox 'should report different frame instance when frame re-attaches' do
      frame1 = attach_frame(page, 'frame1', server_empty_page)
      js = <<~JAVASCRIPT
      () => {
        globalThis.frame = document.querySelector('#frame1');
        globalThis.frame.remove();
      }
      JAVASCRIPT
      page.evaluate(js)
      expect(frame1).to be_detached

      frameattached_promise = Concurrent::Promises.resolvable_future.tap do |future|
        page.once('frameattached') { |frame| future.fulfill(frame) }
      end
      frame2 = Puppeteer::ConcurrentRubyUtils.with_waiting_for_complete(frameattached_promise) do
        page.evaluate('() => document.body.appendChild(globalThis.frame)')
      end
      expect(frame2).not_to be_detached
      expect(frame1).not_to eq(frame2)
    end

    it 'should support url fragment' do
      page.goto("#{server_prefix}/frames/one-frame-url-fragment.html")

      expect(page.frames.size).to eq(2)
      expect(page.frames.last.url).to eq("#{server_prefix}/frames/frame.html?param=value#fragment")
    end

    it_fails_firefox 'should support lazy frames' do
      page.viewport = Puppeteer::Viewport.new(width: 1000, height: 1000)
      page.goto("#{server_prefix}/frames/lazy-frame.html")

      expect(page.frames.map { |frame| frame.has_started_loading? }).to eq([true, true, false])
    end
  end
end
