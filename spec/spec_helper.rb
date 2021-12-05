require 'bundler/setup'
require 'puppeteer'
require 'rollbar'

Rollbar.configure do |config|
  if ENV['ROLLBAR_ACCESS_TOKEN']
    config.access_token = ENV['ROLLBAR_ACCESS_TOKEN']
  else
    config.enabled = false
  end
end

module PuppeteerEnvExtension
  # @return [String] chrome, firefox
  def product
    (%w(chrome firefox) & [ENV['PUPPETEER_PRODUCT_RSPEC']]).first || 'chrome'
  end

  def chrome?
    product == 'chrome'
  end

  def firefox?
    product == 'firefox'
  end
end

Puppeteer::Env.include(PuppeteerEnvExtension)

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with(:rspec) do |c|
    c.syntax = :expect
  end

  launch_options = {
    product: Puppeteer.env.product,
    executable_path: ENV['PUPPETEER_EXECUTABLE_PATH_RSPEC'],
  }.compact
  if Puppeteer.env.debug? && !Puppeteer.env.ci?
    launch_options[:headless] = false
  end
  if ENV['PUPPETEER_NO_SANDBOX_RSPEC']
    args = launch_options[:args] || []
    args << '--no-sandbox'
    launch_options[:args] = args
  end


  config.around(:each, type: :puppeteer) do |example|
    if ENV['PENDING_CHECK'] && !example.metadata[:pending]
      skip 'Pending check mode'
    end

    @default_launch_options = launch_options
    @puppeteer_headless = launch_options[:headless] != false

    # if example.metadata[:disable_web_security]
    #   # Enable cross-origin access for cookies_spec
    #   # ref: https://github.com/puppeteer/puppeteer/issues/4053
    #   launch_options[:args] = [
    #     '--disable-web-security',
    #     '--disable-features=IsolateOrigins,site-per-process',
    #   ]
    # end

    if example.metadata[:enable_site_per_process_flag]
      args = launch_options[:args] || []
      args << '--site-per-process'
      launch_options[:args] = args
    end

    if example.metadata[:puppeteer].to_s == 'browser'
      Puppeteer.launch(**launch_options) do |browser|
        @puppeteer_browser = browser
        example.run
      end
    elsif example.metadata[:browser_context].to_s == 'incognito'
      Puppeteer.launch(**launch_options) do |browser|
        @puppeteer_browser_context = browser.create_incognito_browser_context
        @puppeteer_page = @puppeteer_browser_context.new_page
        begin
          example.run
        ensure
          @puppeteer_page.close
        end
      end
    else
      if Puppeteer.env.firefox?
        Puppeteer.launch(**launch_options) do |browser|
          # Firefox often fails page.focus by reusing the page with 'browser.pages.first'.
          # So create new page for each spec.
          @puppeteer_page = browser.new_page
          begin
            example.run
          ensure
            @puppeteer_page.close
          end
        end
      else
        Puppeteer.launch(**launch_options) do |browser|
          @puppeteer_page = browser.new_page
          example.run
        end
      end
    end
  end

  # Unit test doesn't connect to internet. No need to wait for 30sec. Set it to 7.5sec.
  config.before(:each, type: :puppeteer) do
    stub_const("Puppeteer::TimeoutSettings::DEFAULT_TIMEOUT", 7500)
  end

  # Every browser automation test case should spend less than 15sec.
  if Puppeteer.env.ci?
    config.around(:each, type: :puppeteer) do |example|
      Timeout.timeout(15) { example.run }
    end
  end

  config.define_derived_metadata(file_path: %r(/spec/integration/)) do |metadata|
    metadata[:type] = :puppeteer
  end

  module PuppeteerMethods
    def headless?
      @puppeteer_headless
    end

    def browser
      @puppeteer_browser or raise NoMethodError.new('undefined method "browser" (If you intended to use puppeteer#browser, you have to add `puppeteer: :browser` to metadata.)')
    end

    def browser_context
      @puppeteer_browser_context or raise NoMethodError.new('undefined method "browser_context"')
    end

    def page
      @puppeteer_page or raise NoMethodError.new('undefined method "page"')
    end

    def default_launch_options
      @default_launch_options or raise NoMethodError.new('undefined method "default_launch_options"')
    end
  end
  config.include PuppeteerMethods, type: :puppeteer

  test_with_sinatra = Module.new do
    attr_reader :server_prefix, :server_cross_process_prefix, :server_empty_page, :sinatra
  end
  config.include(test_with_sinatra, sinatra: true)
  config.around(sinatra: true) do |example|
    require 'net/http'
    require 'sinatra/base'
    require 'timeout'

    sinatra_app = Sinatra.new
    sinatra_app.disable(:protection)
    sinatra_app.set(:quiet, true)
    sinatra_app.set(:public_folder, File.join(__dir__, 'assets'))
    sinatra_app.set(:logging, false)
    @server_prefix = "http://localhost:4567"
    @server_cross_process_prefix = "http://127.0.0.1:4567"
    @server_empty_page = "#{@server_prefix}/empty.html"

    sinatra_app.get('/_ping') { '_pong' }

    # Start server and wait for server ready.
    # FIXME should change port when Errno::EADDRINUSE
    Thread.new { sinatra_app.run!(port: 4567) }
    Timeout.timeout(3) do
      loop do
        Net::HTTP.get(URI("#{server_prefix}/_ping"))
        break
      rescue Errno::EADDRNOTAVAIL
        sleep 1
      rescue Errno::ECONNREFUSED
        sleep 0.1
      end
    end

    begin
      @sinatra = sinatra_app
      example.run
    ensure
      sinatra_app.quit!
    end
  end
end

module ItFailsFirefox
  def it_fails_firefox(*args, **kwargs, &block)
    if Puppeteer.env.firefox?
      if ENV['PENDING_CHECK']
        # Executed but not marked as failure.
        # Fails if pass.
        pending(*args, **kwargs, &block)
      else
        # Not executed, just skip.
        skip(*args, **kwargs, &block)
      end
    else
      it(*args, **kwargs, &block)
    end
  end
end

RSpec::Core::ExampleGroup.extend(ItFailsFirefox)

require_relative './golden_matcher'
require_relative './utils'
