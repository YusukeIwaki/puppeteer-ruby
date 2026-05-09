# frozen_string_literal: true

require 'bundler/setup'
require 'fileutils'
require 'securerandom'
require 'time'
require 'timeout'
require 'rack/utils'

require 'smartest/autorun'
require 'puppeteer'

module SmartestTestCaseLineRangePatch
  private def inferred_end_lineno
    [super, location.lineno].max
  end
end

Smartest::TestCase.prepend(SmartestTestCaseLineRangePatch)

require_relative '../spec/support/test_server'
require_relative '../spec/support/ws_http2_test_server'
require_relative '../spec/utils'
require_relative 'support/sinatra_adapter'
require_relative 'support/rspec_like_dsl'

module PuppeteerEnvExtension
  def product
    value = ENV['PUPPETEER_PRODUCT_RSPEC'] || ENV['PUPPETEER_PRODUCT_SMARTEST']
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

$default_launch_options = {
  product: Puppeteer.env.product,
  channel: ENV['PUPPETEER_CHANNEL_RSPEC'] || ENV['PUPPETEER_CHANNEL_SMARTEST'],
  executable_path: ENV['PUPPETEER_EXECUTABLE_PATH_RSPEC'] || ENV['PUPPETEER_EXECUTABLE_PATH_SMARTEST'],
}.compact
$default_launch_options[:headless] = !%w[0 false].include?(ENV['HEADLESS'])
$default_launch_options[:ignore_https_errors] = true
if ENV['PUPPETEER_NO_SANDBOX_RSPEC'] || ENV['PUPPETEER_NO_SANDBOX_SMARTEST']
  args = $default_launch_options[:args] || []
  args << '--no-sandbox'
  $default_launch_options[:args] = args
end

Dir[File.join(__dir__, 'fixtures', '**', '*.rb')].sort.each do |fixture_file|
  require fixture_file
end

Dir[File.join(__dir__, 'matchers', '**', '*.rb')].sort.each do |matcher_file|
  require matcher_file
end

module BrowserTestHelpers
  include Utils::AttachFrame
  include Utils::DetachFrame
  include Utils::NavigateFrame
  include Utils::DumpFrames
  include Utils::Favicon
  include Utils::WaitEvent
  include SmartestRSpecLikeDSL::ExecutionHelpers

  def headless?
    !%w[0 false].include?(ENV['HEADLESS'])
  end

  def default_launch_options
    $default_launch_options or raise NoMethodError.new('undefined method "default_launch_options"')
  end

  def asset_path(relative_path)
    File.expand_path(File.join('..', 'spec', 'assets', relative_path), __dir__)
  end

  def with_browser(**options, &block)
    options = default_launch_options.merge(options)
    Puppeteer.launch(**options, &block)
  end

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

  def with_test_state(incognito: nil, create_page: true, browser: nil, &block)
    browser ||= BrowserFixture.ensure_browser!
    server = $shared_test_server
    https_server = $shared_https_test_server

    initial_context_ids = browser.browser_contexts.map(&:id)

    incognito = create_page if incognito.nil?

    context =
      if incognito
        browser.create_incognito_browser_context
      else
        browser.default_browser_context
      end
    initial_pages = context.pages
    page = create_page ? context.new_page : nil

    begin
      block.call(page: page, server: server, https_server: https_server, browser: browser, context: context)
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

  def ws_http2_server
    $ws_http2_test_server or raise 'WebSocket HTTP/2 test server not started'
  end
end

around_suite do |suite|
  use_fixture BrowserFixture
  use_fixture ServerFixture
  use_matcher PredicateMatcher
  use_matcher RSpecCompatMatchers
  use_matcher GoldenMatcher

  around_test do |test|
    use_helper BrowserTestHelpers

    timeout_sec = (ENV['PUPPETEER_TIMEOUT_RSPEC'] || ENV['PUPPETEER_TIMEOUT_SMARTEST'] || 15).to_i
    if timeout_sec > 0
      Timeout.timeout(timeout_sec) { test.run }
    else
      test.run
    end
  end

  suite.run
end
