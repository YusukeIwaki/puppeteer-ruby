# https://github.com/puppeteer/puppeteer/blob/master/lib/Launcher.js
class Puppeteer::ChromeLauncher
  # @param {string} projectRoot
  # @param {string} preferredRevision
  def initialize(project_root:, preferred_revision:, is_puppeteer_core:)
    @project_root = project_root
    @preferred_revision = preferred_revision
    @is_puppeteer_core = is_puppeteer_core
  end


  # @param {!(Launcher.LaunchOptions & Launcher.ChromeArgOptions & Launcher.BrowserOptions)=} options
  # @return {!Promise<!Browser>}
  def launch(options = {})
    @chrome_arg_options = Launcher::ChromeArgOptions.new(options)
    @launch_options = Launcher::LaunchOptions.new(options)
    @browser_options = Launcher::BrowserOptions.new(options)

    chrome_arguments =
      if !@launch_options.ignore_default_args
        default_args.to_a
      elsif @launch_options.ignore_default_args.is_a?(Enumerable)
        default_args.reject do |arg|
          @launch_options.ignore_default_args.include?(arg)
        end.to_a
      else
        @chrome_arg_options.args
      end

    #
    # let temporaryUserDataDir = null;

    # if (!chromeArguments.some(argument => argument.startsWith('--remote-debugging-')))
    #   chromeArguments.push(pipe ? '--remote-debugging-pipe' : '--remote-debugging-port=0');
    # if (!chromeArguments.some(arg => arg.startsWith('--user-data-dir'))) {
    #   temporaryUserDataDir = await mkdtempAsync(profilePath);
    #   chromeArguments.push(`--user-data-dir=${temporaryUserDataDir}`);
    # }

    # let chromeExecutable = executablePath;
    # if (!executablePath) {
    #   const {missingText, executablePath} = resolveExecutablePath(this);
    #   if (missingText)
    #     throw new Error(missingText);
    #   chromeExecutable = executablePath;
    # }

    # const usePipe = chromeArguments.includes('--remote-debugging-pipe');
    # const runner = new BrowserRunner(chromeExecutable, chromeArguments, temporaryUserDataDir);
    # runner.start({handleSIGHUP, handleSIGTERM, handleSIGINT, dumpio, env, pipe: usePipe});

    # try {
    #   const connection = await runner.setupConnection({usePipe, timeout, slowMo, preferredRevision: this._preferredRevision});
    #   const browser = await Browser.create(connection, [], ignoreHTTPSErrors, defaultViewport, runner.proc, runner.close.bind(runner));
    #   await browser.waitForTarget(t => t.type() === 'page');
    #   return browser;
    # } catch (error) {
    #   runner.kill();
    #   throw error;
    # }
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

      if (chrome_arg_options.headless?) {
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

  def executable_path
  end

  # @return [String]
  private def executable_path
    ENV["PUPPETEER_EXECUTABLE_PATH"]
  end

  private def product
    'chrome'
  end
end
