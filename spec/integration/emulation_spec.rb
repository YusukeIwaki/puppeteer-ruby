require 'spec_helper'

RSpec.describe 'Emulation' do
  let(:iPhone) { Puppeteer.devices.iPhone_6 }
  let(:iPhoneLandscape) { Puppeteer.devices.iPhone_6_landscape }

  describe 'Page.viewport' do
    it 'should get the proper viewport size' do
      viewport = page.viewport
      expect(viewport.width).to eq(800)
      expect(viewport.height).to eq(600)

      page.viewport = Puppeteer::Viewport.new(width: 123, height: 456)
      viewport = page.viewport
      expect(viewport.width).to eq(123)
      expect(viewport.height).to eq(456)
    end

    it 'should support mobile emulation', sinatra: true do
      page.goto("#{server_prefix}/mobile.html")
      expect(page.evaluate('() => window.innerWidth')).to eq(800)
      page.viewport = iPhone.viewport
      expect(page.evaluate('() => window.innerWidth')).to eq(375)
      page.viewport = Puppeteer::Viewport.new(width: 400, height: 300)
      expect(page.evaluate('() => window.innerWidth')).to eq(400)
    end

    it 'should support touch emulation', sinatra: true do
      page.goto("#{server_prefix}/mobile.html")
      expect(page.evaluate("() => 'ontouchstart' in window")).to eq(false)
      page.viewport = iPhone.viewport
      expect(page.evaluate("() => 'ontouchstart' in window")).to eq(true)

      dispatch_touch = <<~JAVASCRIPT
      () => {
        let fulfill;
        const promise = new Promise((x) => (fulfill = x));
        window.ontouchstart = () => {
          fulfill('Received touch');
        };
        window.dispatchEvent(new Event('touchstart'));

        fulfill('Did not receive touch');

        return promise;
      }
      JAVASCRIPT
      expect(page.evaluate(dispatch_touch)).to eq('Received touch')
      page.viewport = Puppeteer::Viewport.new(width: 100, height: 100)
      expect(page.evaluate("() => 'ontouchstart' in window")).to eq(false)
    end

    it 'should be detectable by Modernizr', sinatra: true do
      expect { page.viewport = iPhone.viewport }.to change {
        page.goto("#{server_prefix}/detect-touch.html")
        page.evaluate('() => document.body.textContent.trim()')
      }.from('NO').to('YES')
    end

    it 'should detect touch when applying viewport with touches', sinatra: true do
      page.viewport = Puppeteer::Viewport.new(width: 800, height: 600, has_touch: true)
      page.add_script_tag(url: "#{server_prefix}/modernizr.js")
      expect(page.evaluate('() => globalThis.Modernizr.touchevents')).to eq(true)
    end

    it_fails_firefox 'should support landscape emulation', sinatra: true do
      page.goto("#{server_prefix}/mobile.html")
      expect(page.evaluate('() => screen.orientation.type')).to eq('portrait-primary')
      page.viewport = iPhoneLandscape.viewport
      expect(page.evaluate('() => screen.orientation.type')).to eq('landscape-primary')
      page.viewport = Puppeteer::Viewport.new(width: 100, height: 100)
      expect(page.evaluate('() => screen.orientation.type')).to eq('portrait-primary')
    end
  end

  describe 'Page.emulate' do
    it 'should work', sinatra: true do
      page.goto("#{server_prefix}/mobile.html")
      page.emulate(iPhone)
      expect(page.evaluate('() => window.innerWidth')).to eq(375)
      expect(page.evaluate('() => navigator.userAgent')).to include('iPhone')
    end

    it 'should support clicking', sinatra: true do
      page.emulate(iPhone)
      page.goto("#{server_prefix}/input/button.html")
      button = page.query_selector('button')
      page.evaluate("(button) => button.style.marginTop = '200px'", button)
      button.click
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end

  describe 'Page.emulate_media_type' do
    it_fails_firefox 'should work' do
      expect(page.evaluate("() => matchMedia('screen').matches")).to eq(true)
      expect(page.evaluate("() => matchMedia('print').matches")).to eq(false)
      page.emulate_media_type('print')
      expect(page.evaluate("() => matchMedia('screen').matches")).to eq(false)
      expect(page.evaluate("() => matchMedia('print').matches")).to eq(true)
      page.emulate_media_type(nil)
      expect(page.evaluate("() => matchMedia('screen').matches")).to eq(true)
      expect(page.evaluate("() => matchMedia('print').matches")).to eq(false)
    end

    it 'should throw in case of bad argument' do
      expect { page.emulate_media_type('bad') }.to raise_error(/Unsupported media type: bad/)
    end
  end

  describe 'Page.emulate_media_features' do
    it_fails_firefox 'should work' do
      page.emulate_media_features([
        { name: 'prefers-reduced-motion', value: 'reduce' },
      ])
      expect(page.evaluate("() => matchMedia('(prefers-reduced-motion: reduce)').matches")).to eq(true)
      expect(page.evaluate("() => matchMedia('(prefers-reduced-motion: no-preference)').matches")).to eq(false)

      page.emulate_media_features([
        { name: 'prefers-color-scheme', value: 'light' },
      ])
      expect(page.evaluate("() => matchMedia('(prefers-color-scheme: light)').matches")).to eq(true)
      expect(page.evaluate("() => matchMedia('(prefers-color-scheme: dark)').matches")).to eq(false)
      page.emulate_media_features([
        { name: 'prefers-color-scheme', value: 'dark' },
      ])
      expect(page.evaluate("() => matchMedia('(prefers-color-scheme: light)').matches")).to eq(false)
      expect(page.evaluate("() => matchMedia('(prefers-color-scheme: dark)').matches")).to eq(true)

      page.emulate_media_features([
        { name: 'prefers-reduced-motion', value: 'reduce' },
        { name: 'prefers-color-scheme', value: 'light' },
      ])
      expect(page.evaluate("() => matchMedia('(prefers-reduced-motion: reduce)').matches")).to eq(true)
      expect(page.evaluate("() => matchMedia('(prefers-reduced-motion: no-preference)').matches")).to eq(false)
      expect(page.evaluate("() => matchMedia('(prefers-color-scheme: light)').matches")).to eq(true)
      expect(page.evaluate("() => matchMedia('(prefers-color-scheme: dark)').matches")).to eq(false)

      # 'color-gamut' is supported on Chrome >= 90
      aggregate_failures 'color-gamut' do
        page.emulate_media_features([
          { name: 'color-gamut', value: 'srgb' },
        ])
        expected = {
          p3: false,
          srgb: true,
          rec2020: false,
        }
        observed = expected.map do |key, _|
          [key, page.evaluate("() => matchMedia('(color-gamut: #{key})').matches")]
        end.to_h
        expect(observed).to eq(expected)

        page.emulate_media_features([
          { name: 'color-gamut', value: 'p3' },
        ])
        expected = {
          p3: true,
          srgb: true,
          rec2020: false,
        }
        observed = expected.map do |key, _|
          [key, page.evaluate("() => matchMedia('(color-gamut: #{key})').matches")]
        end.to_h
        expect(observed).to eq(expected)

        page.emulate_media_features([
          { name: 'color-gamut', value: 'rec2020' },
        ])
        expected = {
          p3: true,
          srgb: true,
          rec2020: true,
        }
        observed = expected.map do |key, _|
          [key, page.evaluate("() => matchMedia('(color-gamut: #{key})').matches")]
        end.to_h
        expect(observed).to eq(expected)
      end
    end

    it 'should throw in case of bad argument' do
      expect {
        page.emulate_media_features([
          { name: 'bad', value: '' },
        ])
      }.to raise_error(/Unsupported media feature: bad/)
    end
  end

  # describeFailsFirefox('Page.emulateTimezone', function () {
  #   it('should work', async () => {
  #     const { page } = getTestState();

  #     await page.evaluate(() => {
  #       globalThis.date = new Date(1479579154987);
  #     });
  #     await page.emulateTimezone('America/Jamaica');
  #     expect(await page.evaluate(() => globalThis.date.toString())).toBe(
  #       'Sat Nov 19 2016 13:12:34 GMT-0500 (Eastern Standard Time)'
  #     );

  #     await page.emulateTimezone('Pacific/Honolulu');
  #     expect(await page.evaluate(() => globalThis.date.toString())).toBe(
  #       'Sat Nov 19 2016 08:12:34 GMT-1000 (Hawaii-Aleutian Standard Time)'
  #     );

  #     await page.emulateTimezone('America/Buenos_Aires');
  #     expect(await page.evaluate(() => globalThis.date.toString())).toBe(
  #       'Sat Nov 19 2016 15:12:34 GMT-0300 (Argentina Standard Time)'
  #     );

  #     await page.emulateTimezone('Europe/Berlin');
  #     expect(await page.evaluate(() => globalThis.date.toString())).toBe(
  #       'Sat Nov 19 2016 19:12:34 GMT+0100 (Central European Standard Time)'
  #     );
  #   });

  #   it('should throw for invalid timezone IDs', async () => {
  #     const { page } = getTestState();

  #     let error = null;
  #     await page.emulateTimezone('Foo/Bar').catch((error_) => (error = error_));
  #     expect(error.message).toBe('Invalid timezone ID: Foo/Bar');
  #     await page.emulateTimezone('Baz/Qux').catch((error_) => (error = error_));
  #     expect(error.message).toBe('Invalid timezone ID: Baz/Qux');
  #   });
  # });

  # describeFailsFirefox('Page.emulateVisionDeficiency', function () {
  #   it('should work', async () => {
  #     const { page, server } = getTestState();

  #     await page.setViewport({ width: 500, height: 500 });
  #     await page.goto(server.PREFIX + '/grid.html');

  #     {
  #       await page.emulateVisionDeficiency('none');
  #       const screenshot = await page.screenshot();
  #       expect(screenshot).toBeGolden('screenshot-sanity.png');
  #     }

  #     {
  #       await page.emulateVisionDeficiency('achromatopsia');
  #       const screenshot = await page.screenshot();
  #       expect(screenshot).toBeGolden('vision-deficiency-achromatopsia.png');
  #     }

  #     {
  #       await page.emulateVisionDeficiency('blurredVision');
  #       const screenshot = await page.screenshot();
  #       expect(screenshot).toBeGolden('vision-deficiency-blurredVision.png');
  #     }

  #     {
  #       await page.emulateVisionDeficiency('deuteranopia');
  #       const screenshot = await page.screenshot();
  #       expect(screenshot).toBeGolden('vision-deficiency-deuteranopia.png');
  #     }

  #     {
  #       await page.emulateVisionDeficiency('protanopia');
  #       const screenshot = await page.screenshot();
  #       expect(screenshot).toBeGolden('vision-deficiency-protanopia.png');
  #     }

  #     {
  #       await page.emulateVisionDeficiency('tritanopia');
  #       const screenshot = await page.screenshot();
  #       expect(screenshot).toBeGolden('vision-deficiency-tritanopia.png');
  #     }

  #     {
  #       await page.emulateVisionDeficiency('none');
  #       const screenshot = await page.screenshot();
  #       expect(screenshot).toBeGolden('screenshot-sanity.png');
  #     }
  #   });

  #   it('should throw for invalid vision deficiencies', async () => {
  #     const { page } = getTestState();

  #     let error = null;
  #     await page
  #       // @ts-expect-error deliberately passign invalid deficiency
  #       .emulateVisionDeficiency('invalid')
  #       .catch((error_) => (error = error_));
  #     expect(error.message).toBe('Unsupported vision deficiency: invalid');
  #   });
  # });
end
