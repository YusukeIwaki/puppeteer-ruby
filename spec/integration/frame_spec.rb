require 'spec_helper'

RSpec.describe Puppeteer::Frame do
  context 'with empty page' do
    sinatra do
      get('/') do
        '<html><body>Hello puppeteer!</body></html>'
      end
    end

    describe '#execution_context' do
      include Utils::AttachFrame

      it 'should work' do
        page.goto('http://127.0.0.1:4567/')
        attach_frame(page, 'frame1', '/')
        expect(page.frames.size).to eq(2)

        frames = page.frames
        contexts = frames.map(&:execution_context)
        expect(contexts).to all(be_truthy)
        expect(contexts.first).not_to eq(contexts.last)
        expect(contexts.map(&:frame)).to eq(frames)

        contexts.each_with_index do |context, i|
          context.evaluate("() => (globalThis.a = #{i + 1})")
        end
        values = contexts.map { |context| context.evaluate('() => globalThis.a') }
        expect(values).to eq([1, 2])
      end
    end

    describe '#evaluate_handle' do
      it 'should work' do
        page.goto('http://127.0.0.1:4567/')
        main_frame = page.main_frame
        window_handle = main_frame.evaluate_handle('() => window')
        expect(window_handle).to be_truthy
      end
    end

    describe '#evaluate' do
      include Utils::AttachFrame
      include Utils::DetachFrame

      it 'should throw for detached frames' do
        page.goto('http://127.0.0.1:4567/')
        frame1 = attach_frame(page, 'frame1', '/')
        detach_frame(page, 'frame1')
        expect {
          frame1.evaluate('() => 7 * 8')
        }.to raise_error(/Execution Context is not available in detached frame/)
      end
    end
  end

  context 'with nested frames page' do
    sinatra do
      get('/nested-frames.html') do
        <<~HTML
        <style>
        body {
            display: flex;
        }

        body iframe {
            flex-grow: 1;
            flex-shrink: 1;
        }
        ::-webkit-scrollbar{
            display: none;
        }
        html { /* for Firefox */
          scrollbar-width: none;
        }
        </style>
        <script>
        async function attachFrame(frameId, url) {
            var frame = document.createElement('iframe');
            frame.src = url;
            frame.id = frameId;
            document.body.appendChild(frame);
            await new Promise(x => frame.onload = x);
            return 'kazakh';
        }
        </script>
        <iframe src='./two-frames.html' name='2frames'></iframe>
        <iframe src='./frame.html' name='aframe'></iframe>
        HTML
      end
      get('/two-frames.html') do
        <<~HTML
        <style>
        body {
            display: flex;
            flex-direction: column;
        }

        body iframe {
            flex-grow: 1;
            flex-shrink: 1;
        }

        html { /* for Firefox */
          scrollbar-width: none;
        }
        </style>
        <iframe src='./frame.html' name='uno'></iframe>
        <iframe src='./frame.html' name='dos'></iframe>
        HTML
      end
      get('/frame.html') do
        <<~HTML
        <script src='./script.js' type='text/javascript'></script>
        <style>
        div {
          color: blue;
          line-height: 18px;
        }
        </style>
        <div>Hi, I'm frame</div>
        HTML
      end
      get('/empty.html') do
        ''
      end
    end

    include Utils::DumpFrames

    it 'should handle nested frames' do
      page.goto('http://127.0.0.1:4567/nested-frames.html')
      expect(dump_frames(page.main_frame)).to eq([
        'http://127.0.0.1:<PORT>/nested-frames.html',
        '    http://127.0.0.1:<PORT>/two-frames.html (2frames)',
        '        http://127.0.0.1:<PORT>/frame.html (uno)',
        '        http://127.0.0.1:<PORT>/frame.html (dos)',
        '    http://127.0.0.1:<PORT>/frame.html (aframe)',
      ])
    end

    it_fails_firefox 'should detach child frames on navigation' do
      attached_frames = []
      detached_frames = []
      navigated_frames = []
      page.on('frameattached') { |frame| attached_frames << frame }
      page.on('framedetached') { |frame| detached_frames << frame }
      page.on('framenavigated') { |frame| navigated_frames << frame }

      page.goto('http://127.0.0.1:4567/nested-frames.html')
      expect(attached_frames.size).to eq(4)
      expect(detached_frames.size).to eq(0)
      expect(navigated_frames.size).to eq(5)

      attached_frames.clear
      detached_frames.clear
      navigated_frames.clear

      page.goto('http://127.0.0.1:4567/empty.html')
      expect(attached_frames.size).to eq(0)
      expect(detached_frames.size).to eq(4)
      expect(navigated_frames.size).to eq(1)
    end
  end

  context 'with frame page' do
    include Utils::AttachFrame
    include Utils::DetachFrame
    include Utils::NavigateFrame

    sinatra do
      get('/') do
        '<html><body>Hello puppeteer!</body></html>'
      end
      get('/frame.html') do
        <<~HTML
        <script src='./script.js' type='text/javascript'></script>
        <style>
        div {
          color: blue;
          line-height: 18px;
        }
        </style>
        <div>Hi, I'm frame</div>
        HTML
      end
    end

    it_fails_firefox 'should send events when frames are manipulated dynamically' do
      page.goto('http://127.0.0.1:4567/')

      # validate frameattached events
      attached_frames = []
      page.on('frameattached') do |frame|
        attached_frames << frame
      end

      attach_frame(page, 'frame1', '/frame.html')
      expect(attached_frames.size).to eq(1)
      expect(attached_frames.first.url).to eq('http://127.0.0.1:4567/frame.html')

      # validate framenavigated events
      navigated_frames = []
      page.on('framenavigated') do |frame|
        navigated_frames << frame
      end
      navigate_frame(page, 'frame1', '/')
      expect(navigated_frames.size).to eq(1)
      expect(navigated_frames.first.url).to eq('http://127.0.0.1:4567/')

      # validate framedetached events
      detached_frames = []
      page.on('framedetached') do |frame|
        detached_frames << frame
      end
      detach_frame(page, 'frame1')
      expect(detached_frames.size).to eq(1)
      expect(detached_frames.first).to be_detached
    end
  end

  context 'with empty page' do
    include Utils::AttachFrame

    sinatra do
      get('/') do
        '<html><body>Hello puppeteer!</body></html>'
      end
    end

    it_fails_firefox 'should send "framenavigated" when navigating on anchor URLs' do
      page.goto('http://127.0.0.1:4567/')
      Timeout.timeout(5) do
        await_all(
          future { page.goto('http://127.0.0.1:4567/#foo') },
          resolvable_future { |f| page.once('framenavigated') { |frame| f.fulfill(frame) } },
        )
        expect(page.url).to eq('http://127.0.0.1:4567/#foo')
      end
    end

    it 'should not send attach/detach events for main frame' do
      has_events = false
      page.on('frameattached') { has_events = true }
      page.on('framedetached') { has_events = true }

      page.goto('http://127.0.0.1:4567/')
      expect(has_events).to eq(false)
    end
  end

  context 'with frameset page' do
    sinatra do
      get('/frames/frameset.html') do
        <<~HTML
        <frameset>
          <frameset>
            <frame src='./frame.html'></frame>
            <frame src='about:blank'></frame>
          </frameset>
          <frame src='/empty.html'></frame>
          <frame></frame>
        </frameset>
        HTML
      end
      get('/empty.html') do
        ''
      end
      get('/frame.html') do
        <<~HTML
        <link rel='stylesheet' href='./style.css'>
        <script src='./script.js' type='text/javascript'></script>
        <style>
        div {
          line-height: 18px;
        }
        </style>
        <div>Hi, I'm frame</div>
        HTML
      end
    end

    it_fails_firefox 'should support framesets' do
      attached_frames = []
      detached_frames = []
      navigated_frames = []
      page.on('frameattached') { |frame| attached_frames << frame }
      page.on('framedetached') { |frame| detached_frames << frame }
      page.on('framenavigated') { |frame| navigated_frames << frame }

      page.goto('http://127.0.0.1:4567/frames/frameset.html')
      expect(attached_frames.size).to eq(4)
      expect(detached_frames.size).to eq(0)
      expect(navigated_frames.size).to eq(5)

      attached_frames.clear
      detached_frames.clear
      navigated_frames.clear

      page.goto('http://127.0.0.1:4567/empty.html')
      expect(attached_frames.size).to eq(0)
      expect(detached_frames.size).to eq(4)
      expect(navigated_frames.size).to eq(1)
    end
  end

  context 'with shadow page' do
    sinatra do
      get('/shadow.html') do
        <<~HTML
        <script>
        let h1 = null;
        window.button = null;
        window.clicked = false;

        window.addEventListener('DOMContentLoaded', () => {
          const shadowRoot = document.body.attachShadow({mode: 'open'});
          h1 = document.createElement('h1');
          h1.textContent = 'Hellow Shadow DOM v1';
          button = document.createElement('button');
          button.textContent = 'Click';
          button.addEventListener('click', () => clicked = true);
          shadowRoot.appendChild(h1);
          shadowRoot.appendChild(button);
        });
        </script>
        HTML
      end
      get('/empty') do
        '<html><body>Hello puppeteer!</body></html>'
      end
    end

    before { page.goto('http://127.0.0.1:4567/shadow.html') }

    it 'should report frame from-inside shadow DOM' do
      js = <<~JAVASCRIPT
      async function (url) {
        const frame = document.createElement('iframe');
        frame.src = url;
        document.body.shadowRoot.appendChild(frame);
        await new Promise((x) => (frame.onload = x));
      }
      JAVASCRIPT
      page.evaluate(js, '/empty')
      expect(page.frames.size).to eq(2)
      expect(page.frames.last.url).to eq('http://127.0.0.1:4567/empty')
    end
  end

  context 'with empty page' do
    include Utils::AttachFrame

    sinatra do
      get('/') do
        '<html><body>Hello puppeteer!</body></html>'
      end
    end

    before { page.goto('http://127.0.0.1:4567/') }

    it 'should report frame.name()' do
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
      page.evaluate(js, '/')
      expect(page.frames.map(&:name)).to eq(['', 'theFrameId', 'theFrameName'])
    end

    it 'should report frame.parent()' do
      attach_frame(page, 'frame1', '/')
      attach_frame(page, 'frame2', '/')
      expect(page.frames.map(&:parent_frame)).to eq([nil, page.main_frame, page.main_frame])
    end

    it 'should report different frame instance when frame re-attaches' do
      frame1 = attach_frame(page, 'frame1', '/')
      js = <<~JAVASCRIPT
      () => {
        globalThis.frame = document.querySelector('#frame1');
        globalThis.frame.remove();
      }
      JAVASCRIPT
      page.evaluate(js)
      expect(frame1).to be_detached

      frame2 = await_all(
        resolvable_future { |f| page.once('frameattached') { |frame| f.fulfill(frame) } },
        page.async_evaluate('() => document.body.appendChild(globalThis.frame)'),
      ).first
      expect(frame2).not_to be_detached
      expect(frame1).not_to eq(frame2)
    end
  end

  context 'with one-frame-url-fragment page' do
    sinatra do
      get('/one-frame-url-fragment.html') do
        "<iframe src='./frame.html?param=value#fragment'></iframe>"
      end
      get('/frame.html') do
        <<~HTML
        <link rel='stylesheet' href='./style.css'>
        <script src='./script.js' type='text/javascript'></script>
        <style>
        div {
          line-height: 18px;
        }
        </style>
        <div>Hi, I'm frame</div>
        HTML
      end
    end

    it 'should support url fragment' do
      page.goto('http://127.0.0.1:4567/one-frame-url-fragment.html')

      expect(page.frames.size).to eq(2)
      expect(page.frames.last.url).to eq('http://127.0.0.1:4567/frame.html?param=value#fragment')
    end
  end
end
