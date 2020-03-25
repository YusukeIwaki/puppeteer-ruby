require 'concurrent'

# Custom data types.
require 'puppeteer/device'
require 'puppeteer/errors'
require 'puppeteer/viewport'

# Modules
require 'puppeteer/async_await_behavior'
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
require 'puppeteer/frame'
require 'puppeteer/frame_manager'
require 'puppeteer/j_s_handle'
require 'puppeteer/keyboard'
require 'puppeteer/launcher'
require 'puppeteer/lifecycle_watcher'
require 'puppeteer/mouse'
require 'puppeteer/network_manager'
require 'puppeteer/page'
require 'puppeteer/remote_object'
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
                      preferred_revision: "706915",
                      is_puppeteer_core: true)
    end
  end

  # @param {string} projectRoot
  # @param {string} preferredRevision
  # @param {boolean} isPuppeteerCore
  def initialize(project_root:, preferred_revision:, is_puppeteer_core:)
    @project_root = project_root
    @preferred_revision = preferred_revision
    @is_puppeteer_core = is_puppeteer_core
  end

  # @param {!(Launcher.LaunchOptions & Launcher.ChromeArgOptions & Launcher.BrowserOptions & {product?: string, extraPrefsFirefox?: !object})=} options
  # @return {!Promise<!Puppeteer.Browser>}
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

  # @param {!(Launcher.BrowserOptions & {browserWSEndpoint?: string, browserURL?: string, transport?: !Puppeteer.ConnectionTransport})} options
  # @return {!Promise<!Puppeteer.Browser>}
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
    launcher.connect(options)
  end

  # @return {string}
  def executable_path
    launcher.executable_path
  end

  private def launcher
    @launcher ||= Puppeteer::Launcher.new(
                    project_root: @project_root,
                    preferred_revision: @preferred_revision,
                    is_puppeteer_core: @is_puppeteer_core,
                    product: @product_name)
  end

  # @return {string}
  def product
    launcher.product
  end

  # @return {Puppeteer::Devices}
  def devices
    Puppeteer::Devices
  end

  # # @return {Object}
  # def errors
  #   # ???
  # end

  # @param {!Launcher.ChromeArgOptions=} options
  # @return {!Array<string>}
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
