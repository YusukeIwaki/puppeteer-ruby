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
  class BrowserOptions
    # @property {boolean=} ignoreHTTPSErrors
    # @property {(?Puppeteer.Viewport)=} defaultViewport
    # @property {number=} slowMo
    def initialize(options)
      @ignore_https_errors = options[:ignore_https_errors] || false
      # `default_viewport: nil` must be respected here.
      @default_viewport = options.key?(:default_viewport) ? options[:default_viewport] : Puppeteer::Viewport.new(width: 800, height: 600)
      @slow_mo = options[:slow_mo] || 0

      # only for Puppeteer.connect
      @target_filter = options[:target_filter]
      if @target_filter && !@target_filter.respond_to?(:call)
        raise ArgumentError.new('target_filter must be a Proc (target_info => true/false)')
      end

      @is_page_target = options[:is_page_target]
      if @is_page_target && !@is_page_target.respond_to?(:call)
        raise ArgumentError.new('is_page_target must be a Proc (target_info => true/false)')
      end
    end

    attr_reader :default_viewport, :slow_mo, :target_filter, :is_page_target

    def ignore_https_errors?
      @ignore_https_errors
    end
  end
end
