require 'tmpdir'

# https://github.com/puppeteer/puppeteer/blob/master/lib/Launcher.js
module Puppeteer::Launcher
  class Chrome < Base
    # @param {!(Launcher.LaunchOptions & Launcher.ChromeArgOptions & Launcher.BrowserOptions)=} options
    # @return {!Promise<!Browser>}
    def launch(options = {})
      @chrome_arg_options = ChromeArgOptions.new(options)
      @launch_options = LaunchOptions.new(options)
      @browser_options = BrowserOptions.new(options)

      chrome_arguments =
        if !@launch_options.ignore_default_args
          default_args.to_a
        elsif @launch_options.ignore_default_args.is_a?(Enumerable)
          default_args.reject do |arg|
            @launch_options.ignore_default_args.include?(arg)
          end.to_a
        else
          @chrome_arg_options.args.dup
        end

      #
      # let temporaryUserDataDir = null;

      if chrome_arguments.none?{ |arg| arg.start_with?('--remote-debugging-') }
        if @launch_options.pipe?
          chrome_arguments << '--remote-debugging-pipe'
        else
          chrome_arguments << '--remote-debugging-port=0'
        end
      end

      temporary_user_data_dir = nil
      if chrome_arguments.none?{ |arg| arg.start_with?('--user-data-dir') }
        temporary_user_data_dir = Dir.mktmpdir('puppeteer_dev_profile-')
        chrome_arguments << "--user-data-dir=#{temporary_user_data_dir}"
      end

      chrome_executable = @launch_options.executable_path || resolve_executable_path
      use_pipe = chrome_arguments.include?('--remote-debugging-pipe')
      runner = Puppeteer::BrowserRunner.new(chrome_executable, chrome_arguments, temporary_user_data_dir)
      runner.start(
        handle_SIGHUP: @launch_options.handle_SIGHUP?,
        handle_SIGTERM: @launch_options.handle_SIGTERM?,
        handle_SIGINT: @launch_options.handle_SIGINT?,
        dumpio: @launch_options.dumpio?,
        env: @launch_options.env,
        pipe: use_pipe
      );

      begin
        connection = runner.setup_connection(
          use_pipe: use_pipe,
          timeout: @launch_options.timeout,
          slow_mo: @browser_options.slow_mo,
          preferred_revision: @preferred_revision
        )

        browser = Puppeteer::Browser.create(
          connection: connection,
          context_ids: [],
          ignore_https_errors: @browser_options.ignore_https_errors?,
          default_viewport: @browser_options.default_viewport,
          process: runner.proc,
          close_callback: ->{ runner.close }
        )

        browser.wait_for_target(predicate: ->(target) { target.type == 'page' })

        browser
      rescue
        runner.kill
        raise
      end
    end

    class DefaultArgs
      include Enumerable

      # @param options [Launcher::ChromeArgOptions]
      def initialize(chrome_arg_options)
        chrome_arguments = [
          '--disable-background-networking',
          '--enable-features=NetworkService,NetworkServiceInProcess',
          '--disable-background-timer-throttling',
          '--disable-backgrounding-occluded-windows',
          '--disable-breakpad',
          '--disable-client-side-phishing-detection',
          '--disable-component-extensions-with-background-pages',
          '--disable-default-apps',
          '--disable-dev-shm-usage',
          '--disable-extensions',
          '--disable-features=TranslateUI',
          '--disable-hang-monitor',
          '--disable-ipc-flooding-protection',
          '--disable-popup-blocking',
          '--disable-prompt-on-repost',
          '--disable-renderer-backgrounding',
          '--disable-sync',
          '--force-color-profile=srgb',
          '--metrics-recording-only',
          '--no-first-run',
          '--enable-automation',
          '--password-store=basic',
          '--use-mock-keychain',
        ]

        if chrome_arg_options.user_data_dir
          chrome_arguments << "--user-data-dir=#{chrome_arg_options.user_data_dir}"
        end

        if chrome_arg_options.devtools?
          chrome_arguments << '--auto-open-devtools-for-tabs'
        end

        if (chrome_arg_options.headless?)
          chrome_arguments.concat([
            '--headless',
            '--hide-scrollbars',
            '--mute-audio'
          ])
        end

        if chrome_arg_options.args.all?{ |arg| arg.start_with?('-') }
          chrome_arguments << 'about:blank'
        end

        chrome_arguments.concat(chrome_arg_options.args)

        @chrome_arguments = chrome_arguments
      end

      def each(&block)
        @chrome_arguments.each do |opt|
          block.call(opt)
        end
      end
    end

    def default_args
      @default_args ||= DefaultArgs.new(@chrome_arg_options)
    end

    # @param {!(Launcher.BrowserOptions & {browserWSEndpoint?: string, browserURL?: string, transport?: !Puppeteer.ConnectionTransport})} options
    # @return {!Promise<!Browser>}
    def connect(options)
    end

    # @return {string}
    def executable_path
      resolve_executable_path
    end

    private def product
      'chrome'
    end
  end
end
