require 'bundler/setup'
require 'puppeteer'

module SinatraRouting
  def sinatra(port: 4567, &block)
    require 'net/http'
    require 'sinatra/base'
    require 'timeout'

    sinatra_app = Sinatra.new(&block)

    around do |example|
      Thread.new { sinatra_app.run!(port: port) }
      Timeout.timeout(3) do
        loop do
          Net::HTTP.get(URI("http://127.0.0.1:#{port}/"))
          break
        rescue Errno::ECONNREFUSED
          sleep 0.1
        end
      end
      example.run
      sinatra_app.quit!
    end
  end
end

RSpec::Core::ExampleGroup.extend(SinatraRouting)

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  launch_options = {
    product: Puppeteer.env.product || 'chrome',
    executable_path: ENV['PUPPETEER_EXECUTABLE_PATH'],
  }.compact
  if Puppeteer.env.debug? && !Puppeteer.env.ci?
    launch_options[:headless] = false
  end

  config.around(:each, type: :puppeteer) do |example|
    if example.metadata[:puppeteer].to_s == 'browser'
      Puppeteer.launch(**launch_options) do |browser|
        @puppeteer_browser = browser
        example.run
      end
    else
      if Puppeteer.env.firefox?
        Puppeteer.launch(**launch_options) do |browser|
          # Firefox often fails page.focus by reusing the page with 'browser.pages.first'.
          # So create new page for each spec.
          @puppeteer_page = browser.new_page
          example.run
          @puppeteer_page.close
        end
      else
        Puppeteer.launch(**launch_options) do |browser|
          @puppeteer_page = browser.pages.first || new_page
          example.run
        end
      end
    end
  end

  config.define_derived_metadata(file_path: %r(/spec/integration/)) do |metadata|
    metadata[:type] = :puppeteer
  end

  module PuppeteerMethods
    def browser
      @puppeteer_browser or raise NoMethodError.new('undefined method "browser" (If you intended to use puppeteer#browser, you have to add `puppeteer: :browser` to metadata.)')
    end

    def page
      @puppeteer_page or raise NoMethodError.new('undefined method "page"')
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
