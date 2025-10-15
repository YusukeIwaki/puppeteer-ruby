require 'spec_helper'

RSpec.describe 'Screenshots' do
  include GoldenMatcher

  describe 'Page#screenshot', skip: ENV['CI'], sinatra: true do
    before {
      page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
      page.goto("#{server_prefix}/grid.html")
    }

    it 'should work' do
      expect(page.screenshot).to be_golden('screenshot-sanity.png')
    end

    it 'should clip rect' do
      screenshot = page.screenshot(
        clip: {
          x: 50,
          y: 100,
          width: 150,
          height: 100,
        },
      )
      expect(screenshot).to be_golden('screenshot-clip-rect.png')
    end

    it 'should clip elements to the viewport' do
      screenshot = page.screenshot(
        clip: {
          x: 50,
          y: 600,
          width: 100,
          height: 100,
        },
      )
      expect(screenshot).to be_golden('screenshot-offscreen-clip.png')
    end

    it_fails_firefox 'should use scale for clip' do
      screenshot = page.screenshot(
        clip: {
          x: 50,
          y: 100,
          width: 150,
          height: 100,
          scale: 2,
        },
      )
      expect(screenshot).to be_golden('screenshot-clip-rect-scale2.png')
    end

    it 'should run in parallel' do
      promises = 3.times.map do |index|
        Concurrent::Promises.future(index,
          &Puppeteer::ConcurrentRubyUtils.future_with_logging do |i|
            page.screenshot(
              clip: {
                x: 50 * i,
                y: 0,
                width: 50,
                height: 50,
              },
            )
          end
        )
      end
      screenshots = Concurrent::Promises.zip(*promises).value!
      expect(screenshots[1]).to be_golden('grid-cell-1.png')
    end

    it 'should take fullPage screenshots' do
      screenshot = page.screenshot(full_page: true)
      expect(screenshot).to be_golden('screenshot-grid-fullpage.png')
    end

    # it('should run in parallel in multiple pages', async () => {
    #   const { server, context } = getTestState();

    #   const N = 2;
    #   const pages = await Promise.all(
    #     Array(N)
    #       .fill(0)
    #       .map(async () => {
    #         const page = await context.newPage();
    #         await page.goto(server.PREFIX + '/grid.html');
    #         return page;
    #       })
    #   );
    #   const promises = [];
    #   for (let i = 0; i < N; ++i)
    #     promises.push(
    #       pages[i].screenshot({
    #         clip: { x: 50 * i, y: 0, width: 50, height: 50 },
    #       })
    #     );
    #   const screenshots = await Promise.all(promises);
    #   for (let i = 0; i < N; ++i)
    #     expect(screenshots[i]).toBeGolden(`grid-cell-${i}.png`);
    #   await Promise.all(pages.map((page) => page.close()));
    # });
    # itFailsFirefox('should allow transparency', async () => {
    #   const { page, server } = getTestState();

    #   await page.setViewport({ width: 100, height: 100 });
    #   await page.goto(server.EMPTY_PAGE);
    #   const screenshot = await page.screenshot({ omitBackground: true });
    #   expect(screenshot).toBeGolden('transparent.png');
    # });
    # itFailsFirefox('should render white background on jpeg file', async () => {
    #   const { page, server } = getTestState();

    #   await page.setViewport({ width: 100, height: 100 });
    #   await page.goto(server.EMPTY_PAGE);
    #   const screenshot = await page.screenshot({
    #     omitBackground: true,
    #     type: 'jpeg',
    #   });
    #   expect(screenshot).toBeGolden('white.jpg');
    # });

    it_fails_firefox 'should work with webp' do
      screenshot = page.screenshot(type: :webp)
      expect(screenshot.length).to be >= 1000
      Dir.mktmpdir do |tmpdir|
        path = File.join(tmpdir, 'image.webp')
        page.screenshot(path: path)
      end
    end

    # it('should work with odd clip size on Retina displays', async () => {
    #   const { page } = getTestState();

    #   const screenshot = await page.screenshot({
    #     clip: {
    #       x: 0,
    #       y: 0,
    #       width: 11,
    #       height: 11,
    #     },
    #   });
    #   expect(screenshot).toBeGolden('screenshot-clip-odd-size.png');
    # });
    # itFailsFirefox('should return base64', async () => {
    #   const { page, server } = getTestState();

    #   await page.setViewport({ width: 500, height: 500 });
    #   await page.goto(server.PREFIX + '/grid.html');
    #   const screenshot = await page.screenshot({
    #     encoding: 'base64',
    #   });
    #   // TODO (@jackfranklin): improve the screenshot types.
    #   // - if we pass encoding: 'base64', it returns a string
    #   // - else it returns a buffer.
    #   // If we can fix that we can avoid this "as string" here.
    #   expect(Buffer.from(screenshot as string, 'base64')).toBeGolden(
    #     'screenshot-sanity.png'
    #   );
    # });

    it 'should work in "fromSurface: false" mode' do
      skip if headless?

      page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
      page.goto("#{server_prefix}/grid.html")

      screenshot = page.screenshot(from_surface: false)
      expect(screenshot.length).to be >= 1000
    end
  end

  # Regression spec for # https://github.com/YusukeIwaki/puppeteer-ruby/issues/96
  describe 'full_page', sinatra: true do
    shared_examples 'keep input value' do
      it {
        page.goto("#{server_prefix}/input/textarea.html")
        page.type_text('textarea', 'my value')
        page.screenshot(full_page: true)
        expect(page.eval_on_selector('textarea', 'input => input.value')).to eq('my value')
      }
      it {
        page.content = <<~HTML
        <html><body>#{1000.times.map(&:to_s).join('<br/>')}</body></html>
        HTML
        screenshot = page.screenshot(full_page: false)
        expect(screenshot.length).to be < 100000
      }
    end

    context 'with Mobile viewport' do
      before {
        page.viewport = Puppeteer::Devices.iPhone_6.viewport
      }

      it_behaves_like 'keep input value'
    end

    context 'with 1200x1200 viewport' do
      before {
        page.viewport = Puppeteer::Viewport.new(width: 1200, height: 1200)
      }

      it_behaves_like 'keep input value'
    end
  end

  describe 'ElementHandle#screenshot', skip: ENV['CI'], sinatra: true do
    before {
      page.viewport = Puppeteer::Viewport.new(width: 500, height: 500)
      page.goto("#{server_prefix}/grid.html")
    }

    it 'should work' do
      page.evaluate('() => window.scrollBy(50, 100)')
      element_handle = page.S('.box:nth-of-type(3)')
      expect(element_handle.screenshot).to be_golden('screenshot-element-bounding-box.png')
    end

    it 'should take into account padding and border' do
      page.set_content <<-CONTENT
        something above
        <style>div {
          border: 2px solid blue;
          background: green;
          width: 50px;
          height: 50px;
        }
        </style>
        <div></div>
        CONTENT

      elementHandle = page.S('div')
      expect(elementHandle.screenshot).to be_golden('screenshot-element-padding-border.png')
    end

    it 'should capture full element when larger than viewport' do
      page.set_content <<-CONTENT
        something above
        <style>
        div.to-screenshot {
          border: 1px solid blue;
          width: 600px;
          height: 600px;
          margin-left: 50px;
        }
        ::-webkit-scrollbar{
          display: none;
        }
        </style>
        <div class="to-screenshot"></div>
        CONTENT

      element_handle = page.S('div.to-screenshot')
      expect(element_handle.screenshot).to be_golden('screenshot-element-larger-than-viewport.png')

      expect(
        page.evaluate('() => ({ w: window.innerWidth, h: window.innerHeight}))')
      ).to eq({ w: 500, h: 500 })
    end

    it 'should scroll element into view' do
      page.set_content <<-CONTENT
        something above
        <style>div.above {
          border: 2px solid blue;
          background: red;
          height: 1500px;
        }
        div.to-screenshot {
          border: 2px solid blue;
          background: green;
          width: 50px;
          height: 50px;
        }
        </style>
        <div class="above"></div>
        <div class="to-screenshot"></div>
        CONTENT
      element_handle = page.S('div.to-screenshot')
      expect(element_handle.screenshot).to be_golden('screenshot-element-scrolled-into-view.png')
    end

    it_fails_firefox 'should work with a rotated element' do
      page.set_content <<-CONTENT
        <div style="position:absolute;
        top: 100px;
        left: 100px;
        width: 100px;
        height: 100px;
        background: green;
        transform: rotateZ(200deg);">&nbsp;</div>
        CONTENT
      element_handle = page.S('div')
      expect(element_handle.screenshot).to be_golden('screenshot-element-rotate.png')
    end

    it_fails_firefox 'should fail to screenshot a detached element' do
      page.set_content('<h1>remove this</h1>')
      element_handle = page.S('h1')
      page.evaluate('(element) => element.remove()', element_handle)
      begin
        element_handle.screenshot
      rescue => error
        screenshot_error = error
      end
      expect(screenshot_error.message).to eq('Node is either not visible or not an HTMLElement')
    end

    it 'should work for an element with fractional dimensions' do
      page.set_content '<div style="width:48.51px;height:19.8px;border:1px solid black;"></div>'
      element_handle = page.S('div')
      expect(element_handle.screenshot).to be_golden('screenshot-element-fractional.png')
    end

    it_fails_firefox 'should work for an element with an offset' do
      page.set_content '<div style="position:absolute; top: 10.3px; left: 20.4px;width:50.3px;height:20.2px;border:1px solid black;"></div>'
      element_handle = page.S('div')
      expect(element_handle.screenshot).to be_golden('screenshot-element-fractional-offset.png')
    end
  end
end
