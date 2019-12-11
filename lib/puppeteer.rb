require 'puppeteer/devices'
require 'puppeteer/launcher'
require 'puppeteer/errors'
require 'puppeteer/version'

# ref: https://github.com/puppeteer/puppeteer/blob/master/lib/Puppeteer.js
class Puppeteer
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
    launcher.launch(options)
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
    @launcher ||= Launcher.new(
                    @project_root,
                    @preferred_revision,
                    @is_puppeteer_core,
                    @product_name)
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
