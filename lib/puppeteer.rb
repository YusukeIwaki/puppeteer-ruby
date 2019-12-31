# Custom data types.
require 'puppeteer/device'
require 'puppeteer/errors'
require 'puppeteer/viewport'

require 'puppeteer/debug_print'

# Classes & values.
require 'puppeteer/browser'
require 'puppeteer/browser_context'
require 'puppeteer/browser_runner'
require 'puppeteer/connection'
require 'puppeteer/devices'
require 'puppeteer/launcher'
require 'puppeteer/page'
require 'puppeteer/target'
require 'puppeteer/version'
require 'puppeteer/web_socket'
require 'puppeteer/web_socket_transport'

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
                      is_puppeteer_core: true
                    )
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
  def launch(options = {}) # TODO: あとでキーワード引数にする
    @product_name ||= options[:product]
    browser = launcher.launch(options)
    if block_given?
      yield(browser)
    else
      browser
    end
  end

  # @param {!(Launcher.BrowserOptions & {browserWSEndpoint?: string, browserURL?: string, transport?: !Puppeteer.ConnectionTransport})} options
  # @return {!Promise<!Puppeteer.Browser>}
  def connect(options = {}) # TODO: あとでキーワード引数にする
    launcher.connect(options)
  end

  # @return {string}
  def executable_path
    @launcher.executable_path
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
  def default_args(options = {}) # TODO: あとでキーワード引数にする
    launcher.default_args(options)
  end

  # @param {!BrowserFetcher.Options=} options
  # @return {!BrowserFetcher}
  def createBrowserFetcher(options = {})
    BrowserFetcher.new(@project_root, options)
  end
end
