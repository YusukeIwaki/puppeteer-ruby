require 'concurrent'

class Puppeteer; end

# Custom data types.
require 'puppeteer/device'
require 'puppeteer/errors'
require 'puppeteer/viewport'

# Modules
require 'puppeteer/concurrent_ruby_utils'
require 'puppeteer/define_async_method'
require 'puppeteer/debug_print'
require 'puppeteer/event_callbackable'
require 'puppeteer/if_present'

# Classes & values.
require 'puppeteer/browser'
require 'puppeteer/browser_context'
require 'puppeteer/browser_runner'
require 'puppeteer/cdp_session'
require 'puppeteer/connection'
require 'puppeteer/console_message'
require 'puppeteer/devices'
require 'puppeteer/dom_world'
require 'puppeteer/emulation_manager'
require 'puppeteer/execution_context'
require 'puppeteer/file_chooser'
require 'puppeteer/frame'
require 'puppeteer/frame_manager'
require 'puppeteer/js_handle'
require 'puppeteer/keyboard'
require 'puppeteer/launcher'
require 'puppeteer/lifecycle_watcher'
require 'puppeteer/mouse'
require 'puppeteer/network_manager'
require 'puppeteer/page'
require 'puppeteer/remote_object'
require 'puppeteer/request'
require 'puppeteer/response'
require 'puppeteer/target'
require 'puppeteer/timeout_settings'
require 'puppeteer/touch_screen'
require 'puppeteer/version'
require 'puppeteer/wait_task'
require 'puppeteer/web_socket'
require 'puppeteer/web_socket_transport'

# subclasses
require 'puppeteer/element_handle'

# ref: https://github.com/puppeteer/puppeteer/blob/master/lib/Puppeteer.js
class Puppeteer
  class << self
    def method_missing(method, *args, **kwargs, &block)
      instance.send(method, *args, **kwargs, &block)
    end

    def instance
      @instance ||= Puppeteer.new(
        project_root: __dir__,
        preferred_revision: '706915',
        is_puppeteer_core: true,
      )
    end
  end

  # @param project_root [String]
  # @param prefereed_revision [String]
  # @param is_puppeteer_core [String]
  def initialize(project_root:, preferred_revision:, is_puppeteer_core:)
    @project_root = project_root
    @preferred_revision = preferred_revision
    @is_puppeteer_core = is_puppeteer_core
  end

  # @param product [String]
  # @param executable_path [String]
  # @param ignore_default_args [Array<String>|nil]
  # @param handle_SIGINT [Boolean]
  # @param handle_SIGTERM [Boolean]
  # @param handle_SIGHUP [Boolean]
  # @param timeout [Integer]
  # @param dumpio [Boolean]
  # @param env [Hash]
  # @param pipe [Boolean]
  # @param args [Array<String>]
  # @param user_data_dir [String]
  # @param devtools [Boolean]
  # @param headless [Boolean]
  # @param ignore_https_errors [Boolean]
  # @param default_viewport [Puppeteer::Viewport|nil]
  # @param slow_mo [Integer]
  # @return [Puppeteer::Browser]
  def launch(
    product: nil,
    executable_path: nil,
    ignore_default_args: nil,
    handle_SIGINT: nil,
    handle_SIGTERM: nil,
    handle_SIGHUP: nil,
    timeout: nil,
    dumpio: nil,
    env: nil,
    pipe: nil,
    args: nil,
    user_data_dir: nil,
    devtools: nil,
    headless: nil,
    ignore_https_errors: nil,
    default_viewport: nil,
    slow_mo: nil
  )
    options = {
      executable_path: executable_path,
      ignore_default_args: ignore_default_args,
      handle_SIGINT: handle_SIGINT,
      handle_SIGTERM: handle_SIGTERM,
      handle_SIGHUP: handle_SIGHUP,
      timeout: timeout,
      dumpio: dumpio,
      env: env,
      pipe: pipe,
      args: args,
      user_data_dir: user_data_dir,
      devtools: devtools,
      headless: headless,
      ignore_https_errors: ignore_https_errors,
      default_viewport: default_viewport,
      slow_mo: slow_mo,
    }.compact

    @product_name ||= product
    browser = launcher.launch(options)
    if block_given?
      begin
        yield(browser)
      ensure
        browser.close
      end
    else
      browser
    end
  end

  # @param browser_ws_endpoint [String]
  # @param browser_url [String]
  # @param transport [Puppeteer::WebSocketTransport]
  # @param ignore_https_errors [Boolean]
  # @param default_viewport [Puppeteer::Viewport|nil]
  # @param slow_mo [Integer]
  # @return [Puppeteer::Browser]
  def connect(
    browser_ws_endpoint: nil,
    browser_url: nil,
    transport: nil,
    ignore_https_errors: nil,
    default_viewport: nil,
    slow_mo: nil
  )
    options = {
      browser_ws_endpoint: browser_ws_endpoint,
      browser_url: browser_url,
      transport: transport,
      ignore_https_errors: ignore_https_errors,
      default_viewport: default_viewport,
      slow_mo: slow_mo,
    }.compact
    browser = launcher.connect(options)
    if block_given?
      yield(browser)
    else
      browser
    end
  end

  # @return [String]
  def executable_path
    launcher.executable_path
  end

  private def launcher
    @launcher ||= Puppeteer::Launcher.new(
      project_root: @project_root,
      preferred_revision: @preferred_revision,
      is_puppeteer_core: @is_puppeteer_core,
      product: @product_name,
    )
  end

  # @return [String]
  def product
    launcher.product
  end

  # @return [Puppeteer::Devices]
  def devices
    Puppeteer::Devices
  end

  # # @return {Object}
  # def errors
  #   # ???
  # end

  # @param args [Array<String>]
  # @param user_data_dir [String]
  # @param devtools [Boolean]
  # @param headless [Boolean]
  # @return [Array<String>]
  def default_args(args: nil, user_data_dir: nil, devtools: nil, headless: nil)
    options = {
      args: args,
      user_data_dir: user_data_dir,
      devtools: devtools,
      headless: headless,
    }.compact
    launcher.default_args(options)
  end

  # @param {!BrowserFetcher.Options=} options
  # @return {!BrowserFetcher}
  def createBrowserFetcher(options = {})
    BrowserFetcher.new(@project_root, options)
  end
end
