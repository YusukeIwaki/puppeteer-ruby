require 'spec_helper'

RSpec.describe Puppeteer::Launcher do
  describe 'Browser#disconnect', puppeteer: :browser do
    it 'should reject navigation when browser closes', sinatra: true do
      remote = Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint)
      page = remote.new_page

      # try to disconnect remote connection exactly during loading css.
      wait_for_css = resolvable_future
      sinatra.get('/_one-style.html') do
        "<link rel='stylesheet' href='./_one-style.css'><div>hello, world!</div>"
      end
      sinatra.get('/_one-style.css') do
        wait_for_css.fulfill(nil)
        sleep 30
        "body { background-color: pink; }"
      end
      navigation_promise = future { page.goto("#{server_prefix}/_one-style.html") }
      wait_for_css.then { sleep 0.02; remote.disconnect }

      expect { await navigation_promise }.to raise_error(/Navigation failed because browser has disconnected!/)
      browser.close
    end

    it 'should reject wait_for_selector when browser closes' do
      remote = Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint)
      page = remote.new_page

      watchdog = page.async_wait_for_selector('div')
      remote.disconnect

      expect { await watchdog }.to raise_error(/Protocol error/)
      browser.close
    end
  end

  describe 'Browser#close', puppeteer: :browser do
    it 'should terminate network waiters', sinatra: true do
      remote = Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint)

      new_page = remote.new_page

      wait_for_request = new_page.async_wait_for_request(url: server_empty_page)
      wait_for_response = new_page.async_wait_for_response(url: server_empty_page)

      browser.close
      expect { await wait_for_request }.to raise_error(/Target Closed/)
      expect { await wait_for_response }.to raise_error(/Target Closed/)
    end
  end

  describe 'Puppeteer#launch', puppeteer: :browser do
    it 'should reject all promises when browser is closed' do
      page = browser.new_page
      never_resolves = page.async_evaluate('() => new Promise(() => {})')

      sleep 0.004 # sleep a bit after page is created, before closing it.

      browser.close
      expect { await never_resolves }.to raise_error(/Protocol error/)
    end
  end

  describe 'Puppeteer#launch', puppeteer: :browser do
    it 'should reject if executable path is invalid' do
      options = default_launch_options.merge(
        executable_path: 'random-invalid-path',
      )

      expect { Puppeteer.launch(**options) }.to raise_error(/Failed to launch/)
    end

    it 'user_data_dir option' do
      Dir.mktmpdir do |user_data_dir|
        options = default_launch_options.merge(
          user_data_dir: user_data_dir,
        )

        Puppeteer.launch(**options) do |browser|
          # Open a page to make sure its functional.
          browser.new_page
          expect(Dir[File.join(user_data_dir, "*")].count).to be > 0
        end
        expect(Dir[File.join(user_data_dir, "*")].count).to be > 0
      end
    end

    it 'user_data_dir argument' do
      Dir.mktmpdir do |user_data_dir|
        options = default_launch_options.dup

        default_launch_option_args = default_launch_options[:args] || []
        if Puppeteer.env.firefox?
          options[:args] = default_launch_option_args + [
            '-profile',
            user_data_dir,
          ]
        else
          options[:args] = default_launch_option_args + [
            "--user-data-dir=#{user_data_dir}",
          ]
        end

        Puppeteer.launch(**options) do |browser|
          # Open a page to make sure its functional.
          browser.new_page
          expect(Dir[File.join(user_data_dir, "*")].count).to be > 0
        end
        expect(Dir[File.join(user_data_dir, "*")].count).to be > 0
      end
    end

    it 'user_data_dir option should restore state', sinatra: true do
      Dir.mktmpdir do |user_data_dir|
        options = default_launch_options.merge(
          user_data_dir: user_data_dir,
        )

        Puppeteer.launch(**options) do |browser|
          # Open a page to make sure its functional.
          page = browser.new_page
          page.goto(server_empty_page)
          page.evaluate("() => (localStorage.hey = 'hello')")
        end

        Puppeteer.launch(**options) do |browser|
          # Open a page to make sure its functional.
          page = browser.new_page
          page.goto(server_empty_page)
          expect(page.evaluate("() => localStorage.hey")).to eq('hello')
        end
      end
    end

    it_fails_firefox 'user_data_dir option should restore cookies', sinatra: true do
      Dir.mktmpdir do |user_data_dir|
        options = default_launch_options.merge(
          user_data_dir: user_data_dir,
        )

        Puppeteer.launch(**options) do |browser|
          # Open a page to make sure its functional.
          page = browser.new_page
          page.goto(server_empty_page)
          js = <<~JAVASCRIPT
          () =>
            (document.cookie =
              'doSomethingOnlyOnce=true; expires=Fri, 31 Dec 9999 23:59:59 GMT')
          JAVASCRIPT
          page.evaluate(js)
        end

        Puppeteer.launch(**options) do |browser|
          # Open a page to make sure its functional.
          page = browser.new_page
          page.goto(server_empty_page)
          expect(page.evaluate("() => document.cookie")).to eq('doSomethingOnlyOnce=true')
        end
      end
    end

    it 'should work with no default arguments' do
      options = default_launch_options.merge(
        ignore_default_args: true,
        args: ['--headless'], # without --headless, test is blocked by welcome dialog
      )

      Puppeteer.launch(**options) do |browser|
        page = browser.new_page
        expect(page.evaluate('11 * 11')).to eq(121)
        page.close
      end
    end

    it 'should filter out ignored default arguments' do
      # Make sure we launch with `--enable-automation` by default.
      default_args = Puppeteer.default_args.to_a
      options = default_launch_options.merge(
        # Ignore first and third default argument.
        ignore_default_args: [default_args[0], default_args[2]],
        args: ['--headless'],
      )

      Puppeteer.launch(**options) do |browser|
        args = browser.process.spawnargs
        expect(args).not_to include(default_args[0])
        expect(args).to include(default_args[1])
        expect(args).not_to include(default_args[2])
      end
    end

    it 'should have default URL when launching browser' do
      Puppeteer.launch(**default_launch_options) do |browser|
        pages = browser.pages.map(&:url)
        expect(pages).to contain_exactly('about:blank')
      end
    end

    it 'should have custom URL when launching browser', pending: Puppeteer.env.ci? && Puppeteer.env.firefox?, sinatra: true do
      options = default_launch_options.dup
      options[:args] ||= []
      options[:args] += [server_empty_page]

      Puppeteer.launch(**options) do |browser|
        expect(browser.pages.size).to eq(1)

        page = browser.pages.first
        unless page.url == server_empty_page
          await page.async_wait_for_navigation
        end

        expect(page.url).to eq(server_empty_page)
      end
    end

    it 'should set the default viewport' do
      options = default_launch_options.merge(
        default_viewport: Puppeteer::Viewport.new(
          width: 456,
          height: 789,
        ),
      )

      Puppeteer.launch(**options) do |browser|
        page = browser.new_page
        expect(page.evaluate('window.innerWidth')).to eq(456)
        expect(page.evaluate('window.innerHeight')).to eq(789)
      end
    end

    it 'should disable the default viewport' do
      options = default_launch_options.merge(
        default_viewport: nil,
      )

      Puppeteer.launch(**options) do |browser|
        page = browser.new_page
        expect(page.viewport).to be_nil
      end
    end

    it 'should take fullPage screenshots when defaultViewport is null', sinatra: true do
      options = default_launch_options.merge(
        default_viewport: nil,
      )

      Puppeteer.launch(**options) do |browser|
        page = browser.new_page
        page.goto("#{server_prefix}/grid.html")
        screenshot = page.screenshot(full_page: true)

        # FIXME: It would be better to check the height of this screenshot here.
        expect(screenshot.size).to be > 50000
      end
    end
  end

  describe 'Puppeteer#default_args', puppeteer: :browser do
    it 'returns default arguments' do
      if Puppeteer.env.firefox?
        expect(Puppeteer.default_args).to include(
          '--headless',
          '--no-remote',
          '--foreground',
        )
      else
        expect(Puppeteer.default_args).to include(
          '--no-first-run',
          '--headless',
        )
      end
    end

    it 'can override headless parameter' do
      if Puppeteer.env.firefox?
        expect(Puppeteer.default_args(headless: false)).not_to include('--headless')
      else
        expect(Puppeteer.default_args(headless: false)).not_to include('--headless')
      end
    end

    it 'can override user_data_dir parameter' do
      if Puppeteer.env.firefox?
        expect(Puppeteer.default_args(user_data_dir: 'foo')).to include(
          '--profile',
          'foo',
        )
      else
        expect(Puppeteer.default_args(user_data_dir: 'foo')).to include(
          '--user-data-dir=foo',
        )
      end
    end
  end

  describe '#product', puppeteer: :browser do
    subject { Puppeteer.product }

    if Puppeteer.env.firefox?
      it { is_expected.to eq('firefox') }
    else
      it { is_expected.to eq('chrome') }
    end
  end

#   describe('Puppeteer.launch', function () {
#     let productName;

#     before(async () => {
#       const { puppeteer } = getTestState();
#       productName = puppeteer._productName;
#     });

#     after(async () => {
#       const { puppeteer } = getTestState();
#       // @ts-expect-error launcher is a private property that users can't
#       // touch, but for testing purposes we need to reset it.
#       puppeteer._lazyLauncher = undefined;
#       puppeteer._productName = productName;
#     });

#     itOnlyRegularInstall('should be able to launch Chrome', async () => {
#       const { puppeteer } = getTestState();
#       const browser = await puppeteer.launch({ product: 'chrome' });
#       const userAgent = await browser.userAgent();
#       await browser.close();
#       expect(userAgent).toContain('Chrome');
#     });

#     it('falls back to launching chrome if there is an unknown product but logs a warning', async () => {
#       const { puppeteer } = getTestState();
#       const consoleStub = sinon.stub(console, 'warn');
#       // @ts-expect-error purposeful bad input
#       const browser = await puppeteer.launch({ product: 'SO_NOT_A_PRODUCT' });
#       const userAgent = await browser.userAgent();
#       await browser.close();
#       expect(userAgent).toContain('Chrome');
#       expect(consoleStub.callCount).toEqual(1);
#       expect(consoleStub.firstCall.args).toEqual([
#         'Warning: unknown product name SO_NOT_A_PRODUCT. Falling back to chrome.',
#       ]);
#     });

#     /* We think there's a bug in the FF Windows launcher, or some
#      * combo of that plus it running on CI, but it's hard to track down.
#      * See comment here: https://github.com/puppeteer/puppeteer/issues/5673#issuecomment-670141377.
#      */
#     itFailsWindows('should be able to launch Firefox', async function () {
#       this.timeout(FIREFOX_TIMEOUT);
#       const { puppeteer } = getTestState();
#       const browser = await puppeteer.launch({ product: 'firefox' });
#       const userAgent = await browser.userAgent();
#       await browser.close();
#       expect(userAgent).toContain('Firefox');
#     });
#   });

  describe 'Puppeteer.connect', puppeteer: :browser do
    include Utils::DumpFrames

    it 'should be able to connect multiple times to the same browser' do
      other_browser = Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint)

      page = other_browser.new_page
      expect(page.evaluate('() => 7 * 8')).to eq(56)
      other_browser.disconnect

      second_page = browser.new_page
      expect(second_page.evaluate('() => 7 * 6')).to eq(42)
    end

    it 'should be able to close remote browser' do
      remote_browser = Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint)

      Timeout.timeout(3) do
        await_all(
          resolvable_future { |f| browser.once('disconnected') { f.fulfill(nil) } },
          future { remote_browser.close },
        )
      end
    end

    #     it('should support ignoreHTTPSErrors option', async () => {
    #       const {
    #         httpsServer,
    #         puppeteer,
    #         defaultBrowserOptions,
    #       } = getTestState();

    #       const originalBrowser = await puppeteer.launch(defaultBrowserOptions);
    #       const browserWSEndpoint = originalBrowser.wsEndpoint();

    #       const browser = await puppeteer.connect({
    #         browserWSEndpoint,
    #         ignoreHTTPSErrors: true,
    #       });
    #       const page = await browser.newPage();
    #       let error = null;
    #       const [serverRequest, response] = await Promise.all([
    #         httpsServer.waitForRequest('/empty.html'),
    #         page.goto(httpsServer.EMPTY_PAGE).catch((error_) => (error = error_)),
    #       ]);
    #       expect(error).toBe(null);
    #       expect(response.ok()).toBe(true);
    #       expect(response.securityDetails()).toBeTruthy();
    #       const protocol = serverRequest.socket.getProtocol().replace('v', ' ');
    #       expect(response.securityDetails().protocol()).toBe(protocol);
    #       await page.close();
    #       await browser.close();
    #     });

    it_fails_firefox 'should be able to reconnect to a disconnected browser', sinatra: true do
      ws_endpoint = browser.ws_endpoint

      page = browser.new_page
      page.goto("#{server_prefix}/frames/nested-frames.html")
      browser.disconnect

      Puppeteer.connect(browser_ws_endpoint: ws_endpoint) do |remote_browser|
        restored_page = remote_browser.pages.find do |page|
          page.url == "#{server_prefix}/frames/nested-frames.html"
        end

        expect(dump_frames(restored_page.main_frame)).to eq([
          'http://localhost:<PORT>/frames/nested-frames.html',
          '    http://localhost:<PORT>/frames/two-frames.html (2frames)',
          '        http://localhost:<PORT>/frames/frame.html (uno)',
          '        http://localhost:<PORT>/frames/frame.html (dos)',
          '    http://localhost:<PORT>/frames/frame.html (aframe)',
        ])
        expect(restored_page.evaluate('() => 7 * 8')).to eq(56)
      end
    end

    # This spec sometimes (but not always) fails in Firefox.
    # @see https://github.com/puppeteer/puppeteer/issues/4197#issuecomment-481793410
    it 'should be able to connect to the same page simultaneously', skip: Puppeteer.env.ci? && Puppeteer.env.firefox? do
      browser2 = Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint)

      pages = await_all(
        resolvable_future { |f| browser.once('targetcreated') { |target| f.fulfill(target.page) } },
        future { browser2.new_page },
      )
      expect(pages.first.evaluate('() => 7 * 8')).to eq(56)
      expect(pages.last.evaluate('() => 7 * 6')).to eq(42)
    end
  end

  describe 'Puppeteer.executablePath', puppeteer: :browser do
    subject(:executable_path) { Puppeteer.executable_path }

    it 'returns browser executable path', pending: Puppeteer.env.ci? && Puppeteer.env.firefox? do
      # @see .circleci/config.yml
      # firefox is not installed in /usr/bin/ in CI
      expect(File.exist?(executable_path)).to eq(true)
    end

    it 'is not a symbolic link', pending: Puppeteer.env.ci? do
      # CircleCI image has symbolic link.
      #
      #     Failures:
      #
      # 1) Puppeteer::Launcher Puppeteer.executablePath should work
      #    Failure/Error: expect(File.realpath(executable_path)).to eq(executable_path)
      #
      #      expected: "/usr/bin/google-chrome"
      #           got: "/opt/google/chrome/google-chrome"
      expect(File.realpath(executable_path)).to eq(executable_path)
    end
  end

  describe 'Browser target events', puppeteer: :browser do
    it 'should work', sinatra: true do
      events = []
      browser.on('targetcreated') { events << 'CREATED' }
      browser.on('targetchanged') { events << 'CHANGED' }
      browser.on('targetdestroyed') { events << 'DESTROYED' }

      page = browser.new_page
      page.goto(server_empty_page)
      page.close

      if Puppeteer.env.firefox?
        # Firefox doesn't fire targetchanged.
        expect(events).to eq(%w(CREATED DESTROYED))
      else
        expect(events).to eq(%w(CREATED CHANGED DESTROYED))
      end
    end
  end

  describe 'Browser.Events.disconnected', puppeteer: :browser do
    it 'should be emitted when: browser gets closed, disconnected or underlying websocket gets closed' do
      original_browser = browser
      browser_ws_endpoint = original_browser.ws_endpoint
      remote_browser1 = Puppeteer.connect(browser_ws_endpoint: browser_ws_endpoint)
      remote_browser2 = Puppeteer.connect(browser_ws_endpoint: browser_ws_endpoint)

      disconnected_original = 0
      disconnected_remote1 = 0
      disconnected_remote2 = 0
      original_browser.on('disconnected') { disconnected_original += 1 }
      remote_browser1.on('disconnected') { disconnected_remote1 += 1 }
      remote_browser2.on('disconnected') { disconnected_remote2 += 1 }

      await_all(
        resolvable_future { |f| remote_browser2.once('disconnected') { |frame| f.fulfill(frame) } },
        future { remote_browser2.disconnect },
      )

      expect(disconnected_original).to eq(0)
      expect(disconnected_remote1).to eq(0)
      expect(disconnected_remote2).to eq(1)

      await_all(
        resolvable_future { |f| remote_browser1.once('disconnected') { |frame| f.fulfill(frame) } },
        resolvable_future { |f| original_browser.once('disconnected') { |frame| f.fulfill(frame) } },
        future { original_browser.close },
      )

      expect(disconnected_original).to eq(1)
      expect(disconnected_remote1).to eq(1)
      expect(disconnected_remote2).to eq(1)
    end
  end
end
