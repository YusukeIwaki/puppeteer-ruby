require 'tmpdir'

# https://github.com/puppeteer/puppeteer/blob/main/src/node/Launcher.ts
module Puppeteer::Launcher
  class Firefox
    def initialize(project_root:, preferred_revision:, is_puppeteer_core:)
      @project_root = project_root
      @preferred_revision = preferred_revision
      @is_puppeteer_core = is_puppeteer_core
    end

    # @param {!(Launcher.LaunchOptions & Launcher.ChromeArgOptions & Launcher.BrowserOptions)=} options
    # @return {!Promise<!Browser>}
    def launch(options = {})
      @chrome_arg_options = ChromeArgOptions.new(options)
      @launch_options = LaunchOptions.new(options)
      @browser_options = BrowserOptions.new(options)

      firefox_arguments =
        if !@launch_options.ignore_default_args
          default_args(options).to_a
        elsif @launch_options.ignore_default_args.is_a?(Enumerable)
          default_args(options).reject do |arg|
            @launch_options.ignore_default_args.include?(arg)
          end.to_a
        else
          @chrome_arg_options.args.dup
        end

      if firefox_arguments.none? { |arg| arg.start_with?('--remote-debugging-') }
        firefox_arguments << "--remote-debugging-port=#{@chrome_arg_options.debugging_port}"
      end

      profile_arg_index = firefox_arguments.index { |arg| arg.start_with?('--profile') || arg.start_with?('-profile') }
      if profile_arg_index
        using_temp_user_data_dir = false
        user_data_dir = firefox_arguments[profile_arg_index + 1]
        unless File.exist?(user_data_dir)
          raise ArgumentError.new("Firefox profile not found at '#{user_data_dir}'")
        end
        prefs = default_preferences(@launch_options.extra_prefs_firefox)
        write_preferences(prefs, user_data_dir)
      else
        using_temp_user_data_dir = true
        user_data_dir = create_profile(@launch_options.extra_prefs_firefox)
        firefox_arguments << "--profile"
        firefox_arguments << user_data_dir
      end

      firefox_executable =
        if @launch_options.channel
          executable_path_for_channel(@launch_options.channel.to_s)
        else
          @launch_options.executable_path || fallback_executable_path
        end
      runner = Puppeteer::BrowserRunner.new(
        true,
        firefox_executable,
        firefox_arguments,
        user_data_dir,
        using_temp_user_data_dir,
      )
      runner.start(
        handle_SIGHUP: @launch_options.handle_SIGHUP?,
        handle_SIGTERM: @launch_options.handle_SIGTERM?,
        handle_SIGINT: @launch_options.handle_SIGINT?,
        dumpio: @launch_options.dumpio?,
        env: @launch_options.env,
        pipe: @launch_options.pipe?,
      )

      browser =
        begin
          connection = runner.setup_connection(
            use_pipe: @launch_options.pipe?,
            timeout: @launch_options.timeout,
            slow_mo: @browser_options.slow_mo,
            preferred_revision: @preferred_revision,
          )

          Puppeteer::Browser.create(
            product: product,
            connection: connection,
            context_ids: [],
            ignore_https_errors: @browser_options.ignore_https_errors?,
            default_viewport: @browser_options.default_viewport,
            process: runner.proc,
            close_callback: -> { runner.close },
            target_filter_callback: nil,
            is_page_target_callback: nil,
          )
        rescue
          runner.kill
          raise
        end

      begin
        browser.wait_for_target(
          predicate: ->(target) { target.type == 'page' },
          timeout: @launch_options.timeout,
        )
      rescue
        browser.close
        raise
      end

      browser
    end

    # @return {string}
    def executable_path(channel: nil)
      if channel
        executable_path_for_channel(channel.to_s)
      else
        fallback_executable_path
      end
    end

    private def fallback_executable_path
      executable_path_for_channel('firefox')
    end

    FIREFOX_EXECUTABLE_PATHS = {
      windows: "#{ENV['PROGRAMFILES']}\\Firefox Nightly\\firefox.exe",
      darwin: -> {
        ['Firefox Nightly.app', 'Firefox Developer Edition.app'].map do |app|
          "/Applications/#{app}/Contents/MacOS/firefox"
        end.find { |path| File.exist?(path) }
      },
      linux: -> { Puppeteer::ExecutablePathFinder.new('firefox').find_first },
    }.freeze

    # @param channel [String]
    private def executable_path_for_channel(channel)
      allowed = ['firefox', 'firefox-nightly', 'nightly']
      unless allowed.include?(channel)
        raise ArgumentError.new("Invalid channel: '#{channel}'. Allowed channel is #{allowed}")
      end

      firefox_path =
        if Puppeteer.env.windows?
          FIREFOX_EXECUTABLE_PATHS[:windows]
        elsif Puppeteer.env.darwin?
          FIREFOX_EXECUTABLE_PATHS[:darwin]
        else
          FIREFOX_EXECUTABLE_PATHS[:linux]
        end
      if firefox_path.is_a?(Proc)
        firefox_path = firefox_path.call
      end

      if !firefox_path || !File.exist?(firefox_path)
        raise "Nightly version of Firefox is not installed on this system.\nExpected path: #{firefox_path}"
      end

      firefox_path
    end

    def product
      'firefox'
    end

    class DefaultArgs
      include Enumerable

      # @param options [Launcher::ChromeArgOptions]
      def initialize(chrome_arg_options)
        firefox_arguments = []

        if Puppeteer.env.darwin?
          firefox_arguments << '--foreground'
        elsif Puppeteer.env.windows?
          firefox_arguments << '--wait-for-browser'
        end

        if chrome_arg_options.user_data_dir
          firefox_arguments << "--profile"
          firefox_arguments << chrome_arg_options.user_data_dir
        end

        if chrome_arg_options.headless?
          firefox_arguments << '--headless'
        end

        if chrome_arg_options.devtools?
          firefox_arguments << '--devtools'
        end

        if chrome_arg_options.args.all? { |arg| arg.start_with?('-') }
          firefox_arguments << 'about:blank'
        end

        firefox_arguments.concat(chrome_arg_options.args)

        @firefox_arguments = firefox_arguments
      end

      def each(&block)
        @firefox_arguments.each do |opt|
          block.call(opt)
        end
      end
    end

    # @return [DefaultArgs]
    def default_args(options = nil)
      DefaultArgs.new(ChromeArgOptions.new(options || {}))
    end

    private def default_preferences(extra_prefs)
      server = 'dummy.test'
      default_preferences = {
        # Make sure Shield doesn't hit the network.
        'app.normandy.api_url': '',
        # Disable Firefox old build background check
        'app.update.checkInstallTime': false,
        # Disable automatically upgrading Firefox
        'app.update.disabledForTesting': true,

        # Increase the APZ content response timeout to 1 minute
        'apz.content_response_timeout': 60000,

        # Prevent various error message on the console
        # jest-puppeteer asserts that no error message is emitted by the console
        'browser.contentblocking.features.standard': '-tp,tpPrivate,cookieBehavior0,-cm,-fp',

        # Enable the dump function: which sends messages to the system
        # console
        # https://bugzilla.mozilla.org/show_bug.cgi?id=1543115
        'browser.dom.window.dump.enabled': true,
        # Disable topstories
        'browser.newtabpage.activity-stream.feeds.system.topstories': false,
        # Always display a blank page
        'browser.newtabpage.enabled': false,
        # Background thumbnails in particular cause grief: and disabling
        # thumbnails in general cannot hurt
        'browser.pagethumbnails.capturing_disabled': true,

        # Disable safebrowsing components.
        'browser.safebrowsing.blockedURIs.enabled': false,
        'browser.safebrowsing.downloads.enabled': false,
        'browser.safebrowsing.malware.enabled': false,
        'browser.safebrowsing.phishing.enabled': false,

        # Disable updates to search engines.
        'browser.search.update': false,
        # Do not restore the last open set of tabs if the browser has crashed
        'browser.sessionstore.resume_from_crash': false,
        # Skip check for default browser on startup
        'browser.shell.checkDefaultBrowser': false,

        # Disable newtabpage
        'browser.startup.homepage': 'about:blank',
        # Do not redirect user when a milstone upgrade of Firefox is detected
        'browser.startup.homepage_override.mstone': 'ignore',
        # Start with a blank page about:blank
        'browser.startup.page': 0,

        # Do not allow background tabs to be zombified on Android: otherwise for
        # tests that open additional tabs: the test harness tab itself might get
        # unloaded
        'browser.tabs.disableBackgroundZombification': false,
        # Do not warn when closing all other open tabs
        'browser.tabs.warnOnCloseOtherTabs': false,
        # Do not warn when multiple tabs will be opened
        'browser.tabs.warnOnOpen': false,

        # Do not automatically offer translations, as tests do not expect this.
        'browser.translations.automaticallyPopup': false,

        # Disable the UI tour.
        'browser.uitour.enabled': false,
        # Turn off search suggestions in the location bar so as not to trigger
        # network connections.
        'browser.urlbar.suggest.searches': false,
        # Disable first run splash page on Windows 10
        'browser.usedOnWindows10.introURL': '',
        # Do not warn on quitting Firefox
        'browser.warnOnQuit': false,

        # Defensively disable data reporting systems
        'datareporting.healthreport.documentServerURI': "http://#{server}/dummy/healthreport/",
        'datareporting.healthreport.logging.consoleEnabled': false,
        'datareporting.healthreport.service.enabled': false,
        'datareporting.healthreport.service.firstRun': false,
        'datareporting.healthreport.uploadEnabled': false,

        # Do not show datareporting policy notifications which can interfere with tests
        'datareporting.policy.dataSubmissionEnabled': false,
        'datareporting.policy.dataSubmissionPolicyBypassNotification': true,

        # DevTools JSONViewer sometimes fails to load dependencies with its require.js.
        # This doesn't affect Puppeteer but spams console (Bug 1424372)
        'devtools.jsonview.enabled': false,

        # Disable popup-blocker
        'dom.disable_open_during_load': false,

        # Enable the support for File object creation in the content process
        # Required for |Page.setFileInputFiles| protocol method.
        'dom.file.createInChild': true,

        # Disable the ProcessHangMonitor
        'dom.ipc.reportProcessHangs': false,

        # Disable slow script dialogues
        'dom.max_chrome_script_run_time': 0,
        'dom.max_script_run_time': 0,

        # Only load extensions from the application and user profile
        # AddonManager.SCOPE_PROFILE + AddonManager.SCOPE_APPLICATION
        'extensions.autoDisableScopes': 0,
        'extensions.enabledScopes': 5,

        # Disable metadata caching for installed add-ons by default
        'extensions.getAddons.cache.enabled': false,

        # Disable installing any distribution extensions or add-ons.
        'extensions.installDistroAddons': false,

        # Disabled screenshots extension
        'extensions.screenshots.disabled': true,

        # Turn off extension updates so they do not bother tests
        'extensions.update.enabled': false,

        # Turn off extension updates so they do not bother tests
        'extensions.update.notifyUser': false,

        # Make sure opening about:addons will not hit the network
        'extensions.webservice.discoverURL': "http://#{server}/dummy/discoveryURL",

        # Allow the application to have focus even it runs in the background
        'focusmanager.testmode': true,

        # Disable useragent updates
        'general.useragent.updates.enabled': false,

        # Always use network provider for geolocation tests so we bypass the
        # macOS dialog raised by the corelocation provider
        'geo.provider.testing': true,

        # Do not scan Wifi
        'geo.wifi.scan': false,

        # No hang monitor
        'hangmonitor.timeout': 0,

        # Show chrome errors and warnings in the error console
        'javascript.options.showInConsole': true,

        # Disable download and usage of OpenH264: and Widevine plugins
        'media.gmp-manager.updateEnabled': false,

        # Disable the GFX sanity window
        'media.sanity-test.disabled': true,

        # Disable experimental feature that is only available in Nightly
        'network.cookie.sameSite.laxByDefault': false,

        # Do not prompt for temporary redirects
        'network.http.prompt-temp-redirect': false,

        # Disable speculative connections so they are not reported as leaking
        # when they are hanging around
        'network.http.speculative-parallel-limit': 0,

        # Do not automatically switch between offline and online
        'network.manage-offline-status': false,

        # Make sure SNTP requests do not hit the network
        'network.sntp.pools': server,

        # Disable Flash.
        'plugin.state.flash': 0,

        'privacy.trackingprotection.enabled': false,

        # Can be removed once Firefox 89 is no longer supported
        # https://bugzilla.mozilla.org/show_bug.cgi?id=1710839
        'remote.enabled': true,

        # Don't do network connections for mitm priming
        'security.certerrors.mitm.priming.enabled': false,

        # Local documents have access to all other local documents,
        # including directory listings
        'security.fileuri.strict_origin_policy': false,

        # Do not wait for the notification button security delay
        'security.notification_enable_delay': 0,

        # Ensure blocklist updates do not hit the network
        'services.settings.server': "http://#{server}/dummy/blocklist/",

        # Do not automatically fill sign-in forms with known usernames and
        # passwords
        'signon.autofillForms': false,

        # Disable password capture, so that tests that include forms are not
        # influenced by the presence of the persistent doorhanger notification
        'signon.rememberSignons': false,

        # Disable first-run welcome page
        'startup.homepage_welcome_url': 'about:blank',

        # Disable first-run welcome page
        'startup.homepage_welcome_url.additional': '',

        # Disable browser animations (tabs, fullscreen, sliding alerts)
        'toolkit.cosmeticAnimations.enabled': false,

        # Prevent starting into safe mode after application crashes
        'toolkit.startup.max_resumed_crashes': -1,
      }.merge({
        # Do not close the window when the last tab gets closed
        'browser.tabs.closeWindowWithLastTab': false,
        # Prevent various error message on the console
        # jest-puppeteer asserts that no error message is emitted by the console
        'network.cookie.cookieBehavior': 0,
        # Temporarily force disable BFCache in parent (https://bit.ly/bug-1732263)
        'fission.bfcacheInParent': false,
        # Only enable the CDP protocol
        'remote.active-protocols': 2,
      }).merge({
        # Force all web content to use a single content process. TODO: remove
        # this once Firefox supports mouse event dispatch from the main frame
        # context. Once this happens, webContentIsolationStrategy should only
        # be set for CDP. See
        # https://bugzilla.mozilla.org/show_bug.cgi?id=1773393
        'fission.webContentIsolationStrategy': 0,
      })

      default_preferences.merge(extra_prefs)
    end

    private def write_preferences(prefs, profile_path)
      File.open(File.join(profile_path, 'user.js'), 'w') do |f|
        prefs.each do |key, value|
          f.write("user_pref(#{JSON.generate(key)}, #{JSON.generate(value)});\n")
        end
      end
      IO.write(File.join(profile_path, 'prefs.js'), "")
    end

    private def create_profile(extra_prefs)
      Dir.mktmpdir('puppeteer_dev_firefox_profile-', ENV['PUPPETEER_TMP_DIR']).tap do |profile_path|
        prefs = default_preferences(extra_prefs)
        write_preferences(prefs, profile_path)
      end
    end
  end
end
