require 'bundler/setup'
require 'chunky_png'
require 'puppeteer'

module SinatraRouting
  def sinatra(port: 4567, &block)
    require 'net/http'
    require 'sinatra/base'
    require 'timeout'

    sinatra_app = Sinatra.new(&block)

    let(:sinatra) { sinatra_app }
    around do |example|
      sinatra_app.get('/_ping') { '_pong' }
      Thread.new { sinatra_app.run!(port: port) }
      Timeout.timeout(3) do
        loop do
          Net::HTTP.get(URI("http://127.0.0.1:#{port}/_ping"))
          break
        rescue Errno::ECONNREFUSED
          sleep 0.1
        end
      end
      begin
        example.run
      ensure
        sinatra.quit!
      end
    end
  end
end

RSpec::Core::ExampleGroup.extend(SinatraRouting)

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

  config.around(:each, type: :puppeteer) do |example|
    @default_launch_options = launch_options
    @puppeteer_headless = launch_options[:headless] != false

    if example.metadata[:puppeteer].to_s == 'browser'
      Puppeteer.launch(**launch_options) do |browser|
        @puppeteer_browser = browser
        example.run
      end
    elsif example.metadata[:browser_context].to_s == 'incognito'
      Puppeteer.launch(**launch_options) do |browser|
        context = browser.create_incognito_browser_context
        @puppeteer_page = context.new_page
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
          @puppeteer_page = browser.pages.first || new_page
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
  config.around(:each, type: :puppeteer) do |example|
    Timeout.timeout(15) { example.run }
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

    def page
      @puppeteer_page or raise NoMethodError.new('undefined method "page"')
    end

    def default_launch_options
      @default_launch_options or raise NoMethodError.new('undefined method "default_launch_options"')
    end
  end
  config.include PuppeteerMethods, type: :puppeteer
end

module ItFailsFirefox
  def it_fails_firefox(*args, **kwargs, &block)
    if Puppeteer.env.firefox?
      pending(*args, **kwargs, &block)
    else
      it(*args, **kwargs, &block)
    end
  end
end

RSpec::Core::ExampleGroup.extend(ItFailsFirefox)

require_relative './utils'
