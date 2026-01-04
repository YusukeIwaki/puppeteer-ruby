require 'bundler/setup'
require 'puppeteer'
require 'rollbar'
require 'timeout'

require_relative 'support/test_server'

class TestServerSinatraAdapter
  class SinatraRequest
    def initialize(route_request)
      @route_request = route_request
      @env = build_env(route_request.headers)
    end

    attr_reader :env

    private def build_env(headers)
      env = {}
      headers.each do |key, value|
        name = "HTTP_#{key.upcase.tr('-', '_')}"
        env[name] = value
      end
      env
    end
  end

  class RouteContext
    def initialize(request)
      @headers = {}
      @status = 200
      @body = nil
      @request = request
    end

    attr_reader :headers

    def status(value = nil)
      return @status if value.nil?

      @status = value
    end

    def headers(values = nil)
      return @headers if values.nil?

      @headers.merge!(values)
    end

    def body(value = nil)
      return @body if value.nil?

      @body = value
    end

    def request
      @request
    end
  end

  def initialize(server)
    @server = server
  end

  def get(path, &block)
    @server.set_route(path) do |route_request, writer|
      route = RouteContext.new(SinatraRequest.new(route_request))
      result = route.instance_exec(&block)

      status, headers, body =
        if result.is_a?(Array) && result.size == 3
          result
        else
          [route.status, route.headers, route.body || result]
        end

      writer.status = status if status
      headers&.each { |key, value| writer.add_header(key, value) }
      writer.write(body.to_s) if body
      writer.finish
    end
  end
end

Rollbar.configure do |config|
  if ENV['ROLLBAR_ACCESS_TOKEN']
    config.access_token = ENV['ROLLBAR_ACCESS_TOKEN']
  else
    config.enabled = false
  end
end

module PuppeteerEnvExtension
  # @return [String] chrome
  def product
    value = ENV['PUPPETEER_PRODUCT_RSPEC']
    if value && value != 'chrome'
      raise ArgumentError.new("PUPPETEER_PRODUCT_RSPEC only supports 'chrome'.")
    end
    'chrome'
  end

  def chrome?
    product == 'chrome'
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

  config.define_derived_metadata(file_path: %r(/spec/integration/)) do |metadata|
    metadata[:type] = :integration
  end

  default_launch_options = {
    product: Puppeteer.env.product,
    channel: ENV['PUPPETEER_CHANNEL_RSPEC'],
    executable_path: ENV['PUPPETEER_EXECUTABLE_PATH_RSPEC'],
  }.compact
  default_launch_options[:headless] = !%w[0 false].include?(ENV['HEADLESS'])
  default_launch_options[:ignore_https_errors] = true
  if ENV['PUPPETEER_NO_SANDBOX_RSPEC']
    args = default_launch_options[:args] || []
    args << '--no-sandbox'
    default_launch_options[:args] = args
  end
  $default_launch_options = default_launch_options

  config.before(:suite) do
    if RSpec.configuration.files_to_run.any? { |f| f.include?('spec/integration') }
      $shared_browser = Puppeteer.launch(**$default_launch_options)
      $shared_test_server = TestServer::Server.new
      $shared_https_test_server = TestServer::Server.new(
        scheme: 'https',
        ssl_context: TestServer.ssl_context,
      )
      $shared_test_server.start
      $shared_https_test_server.start
    end
  end

  config.after(:suite) do
    $shared_browser&.close
    $shared_test_server&.stop
    $shared_https_test_server&.stop
  end

  # Every browser automation test case should spend less than 15sec.
  timeout_sec = (ENV['PUPPETEER_TIMEOUT_RSPEC'] || 15).to_i

  config.around(:each, type: :integration) do |example|
    if timeout_sec > 0
      Timeout.timeout(timeout_sec) { example.run }
    else
      example.run
    end
  end

  # Clean up custom routes after each test.
  config.after(:each, type: :integration) do
    $shared_test_server&.clear_routes
    $shared_https_test_server&.clear_routes
  end

  # Unit test doesn't connect to internet. No need to wait for 30sec. Set it to 7.5sec.
  config.before(:each, type: :integration) do
    stub_const('Puppeteer::TimeoutSettings::DEFAULT_TIMEOUT', 7500)
  end

  module AsyncSpecHelpers
    def async_promise(&block)
      promise = Async::Promise.new
      Thread.new do
        Async::Promise.fulfill(promise, &Puppeteer::AsyncUtils.future_with_logging(&block))
      end
      promise
    end

    def await_promises(*promises)
      Puppeteer::AsyncUtils.await_promise_all(*promises)
    end

    def await_with_trigger(promise, &block)
      await_promises(promise, block).first
    end
  end
  config.include AsyncSpecHelpers

  helper_module = Module.new do
    def headless?
      !%w[0 false].include?(ENV['HEADLESS'])
    end

    def default_launch_options
      $default_launch_options or raise NoMethodError.new('undefined method "default_launch_options"')
    end

    def with_browser(**options, &block)
      options = default_launch_options.merge(options)
      Puppeteer.launch(**options, &block)
    end

    def with_test_state(incognito: false, create_page: true, browser: nil)
      browser ||= $shared_browser or raise 'Shared browser not started'
      server = $shared_test_server
      https_server = $shared_https_test_server

      initial_context_ids = browser.browser_contexts.map(&:id)

      context =
        if incognito
          browser.create_incognito_browser_context
        else
          browser.default_browser_context
        end
      initial_pages = context.pages
      page = create_page ? context.new_page : nil

      begin
        yield(page: page, server: server, https_server: https_server, browser: browser, context: context)
      ensure
        page&.close unless page&.closed?

        (context.pages - initial_pages).each do |extra_page|
          extra_page.close unless extra_page.closed?
        end

        if incognito && browser.browser_contexts.include?(context) && !context.closed?
          context.close
        end

        browser.browser_contexts.each do |ctx|
          next if initial_context_ids.include?(ctx.id)
          next if ctx.id.nil?
          ctx.close
        end
      end
    end
  end
  config.include helper_module, type: :integration

  RSpec.shared_context('with test state') do
    around do |example|
      incognito = example.metadata[:browser_context].to_s == 'incognito'
      create_page = example.metadata[:puppeteer].to_s != 'browser'

      run_example = lambda do |page:, server:, https_server:, browser:, context:|
        @page = page
        @server = server
        @https_server = https_server
        @browser = browser
        @browser_context = context

        example.run
      ensure
        @page = nil
        @server = nil
        @https_server = nil
        @browser = nil
        @browser_context = nil
      end

      if example.metadata[:enable_site_per_process_flag]
        args = (default_launch_options[:args] || []) + [
          '--site-per-process',
          '--host-rules=MAP * 127.0.0.1',
        ]
        options = default_launch_options.merge(args: args)
        Puppeteer.launch(**options) do |isolated_browser|
          with_test_state(
            incognito: incognito,
            create_page: create_page,
            browser: isolated_browser,
            &run_example
          )
        end
      else
        with_test_state(
          incognito: incognito,
          create_page: create_page,
          &run_example
        )
      end
    end

    let(:page) { @page }
    let(:browser) { @browser }
    let(:browser_context) { @browser_context }
    let(:server) { @server }
    let(:https_server) { @https_server }
    let(:sinatra) { TestServerSinatraAdapter.new(server) }
    let(:server_prefix) { server&.prefix }
    let(:server_cross_process_prefix) { server&.cross_process_prefix }
    let(:server_empty_page) { server&.empty_page }
  end
end

require_relative './golden_matcher'
require_relative './utils'
