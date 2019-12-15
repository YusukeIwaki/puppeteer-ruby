# https://github.com/puppeteer/puppeteer/blob/master/lib/Launcher.js
class Puppeteer::Launcher
  class Base
    # @param {string} projectRoot
    # @param {string} preferredRevision
    def initialize(project_root:, preferred_revision:, is_puppeteer_core:)
      @project_root = project_root
      @preferred_revision = preferred_revision
      @is_puppeteer_core = is_puppeteer_core
    end

    class ExecutablePathNotFound < StandardError ; end

    # @returns [String] Chrome Executable file path.
    # @raise [ExecutablePathNotFound]
    def resolve_executable_path
      if !@is_puppeteer_core
        # puppeteer-core doesn't take into account PUPPETEER_* env variables.
        executable_path = ENV['PUPPETEER_EXECUTABLE_PATH']
        if FileTest.exist?(executable_path)
          return executable_path
        end
        raise ExecutablePathNotFound.new(
          "Tried to use PUPPETEER_EXECUTABLE_PATH env variable to launch browser but did not find any executable at: #{executablePath}"
        )
      end
      # const browserFetcher = new BrowserFetcher(launcher._projectRoot);
      # if (!launcher._isPuppeteerCore) {
      #   const revision = process.env['PUPPETEER_CHROMIUM_REVISION'];
      #   if (revision) {
      #     const revisionInfo = browserFetcher.revisionInfo(revision);
      #     const missingText = !revisionInfo.local ? 'Tried to use PUPPETEER_CHROMIUM_REVISION env variable to launch browser but did not find executable at: ' + revisionInfo.executablePath : null;
      #     return {executablePath: revisionInfo.executablePath, missingText};
      #   }
      # }
      # const revisionInfo = browserFetcher.revisionInfo(launcher._preferredRevision);
      # const missingText = !revisionInfo.local ? `Browser is not downloaded. Run "npm install" or "yarn install"` : null;
      # return {executablePath: revisionInfo.executablePath, missingText};
    end
  end

  # @param {string} projectRoot
  # @param {string} preferredRevision
  # @param {boolean} isPuppeteerCore
  # @param {string=} product
  # @return {!Puppeteer.ProductLauncher}
  def self.new(project_root:, preferred_revision:, is_puppeteer_core:, product:)
    if product == 'firefox'
      raise NotImplementedError.new("FirefoxLauncher is not implemented yet.")
    end

    Puppeteer::ChromeLauncher.new(
      project_root: project_root,
      preferred_revision: preferred_revision,
      is_puppeteer_core: is_puppeteer_core
    )
  end

  # const {
  #   ignoreDefaultArgs = false,
  #   args = [],
  #   dumpio = false,
  #   executablePath = null,
  #   pipe = false,
  #   env = process.env,
  #   handleSIGINT = true,
  #   handleSIGTERM = true,
  #   handleSIGHUP = true,
  #   ignoreHTTPSErrors = false,
  #   defaultViewport = {width: 800, height: 600},
  #   slowMo = 0,
  #   timeout = 30000
  # } = options;
  # const {
  #   devtools = false,
  #   headless = !devtools,
  #   args = [],
  #   userDataDir = null
  # } = options;

  class ChromeArgOptions
    # * @property {boolean=} headless
    # * @property {Array<string>=} args
    # * @property {string=} userDataDir
    # * @property {boolean=} devtools
    def initialize(options)
      @args = options[:args] || []
      @user_data_dir = options[:user_data_dir]
      @devtools = options[:devtools] || false
      @headless = options[:headless] || !@devtools
    end

    attr_reader :args, :user_data_dir

    def headless?
      @headless
    end

    def devtools?
      @devtools
    end
  end

  class LaunchOptions
    # @property {string=} executablePath
    # @property {boolean|Array<string>=} ignoreDefaultArgs
    # @property {boolean=} handleSIGINT
    # @property {boolean=} handleSIGTERM
    # @property {boolean=} handleSIGHUP
    # @property {number=} timeout
    # @property {boolean=} dumpio
    # @property {!Object<string, string | undefined>=} env
    # @property {boolean=} pipe
    def initialize(options)
      @executable_path = options[:executable_path]
      @ignore_default_args = options[:ignore_default_args] || false
      @handle_SIGINT = options[:handle_SIGINT] || true
      @handle_SIGTERM = options[:handle_SIGTERM] || true
      @handle_SIGHUP = options[:handle_SIGHUP] || true
      @timeout = options[:timeout] || 30000
      @dumpio = options[:dumpio] || false
      @env = options[:env] || ENV
      @pipe = options[:pipe] || false
    end

    attr_reader :executable_path, :ignore_default_args, :timeout, :env

    def handle_SIGINT?
      @handle_SIGINT
    end

    def handle_SIGTERM?
      @handle_SIGTERM
    end

    def handle_SIGHUP?
      @handle_SIGHUP
    end

    def dumpio?
      @dumpio
    end

    def pipe?
      @pipe
    end
  end

  class BrowserOptions
    # @property {boolean=} ignoreHTTPSErrors
    # @property {(?Puppeteer.Viewport)=} defaultViewport
    # @property {number=} slowMo
    def initialize(options)
      @ignore_https_errors = options[:ignore_https_errors] || false
      @default_viewport = options[:default_viewport] || Puppeteer::Viewport.new(width: 800, height: 600)
      @slow_mo = options[:slow_mo] || 0
    end

    attr_reader :default_viewport, :slow_mo

    def ignore_https_errors?
      @ignore_https_errors
    end
  end
end
