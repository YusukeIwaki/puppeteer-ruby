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

module Puppeteer::Launcher
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
end
