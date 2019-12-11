require 'fileutils'

# https://github.com/puppeteer/puppeteer/blob/master/lib/Launcher.js
class Puppeteer::BrowserRunner
  # @param {string} executablePath
  # @param {!Array<string>} processArguments
  # @param {string=} tempDirectory
  def initialize(executable_path, process_arguments, temp_directory)
    @executable_path = executable_path
    @process_arguments = process_arguments
    @temp_directory = temp_directory
    @proc = nil
    @connection = nil
    @closed = true
    @listeners = []
  end

  # @param {!(Launcher.LaunchOptions)=} options
  def start(options = {}) # TODO: あとでキーワード引数にする
    env = options[:env] || {}
    @proc = spawn(env, "#{@executable_path} #{@process_arguments.join(" ")}")
    @closed = false
    @process_closing = -> {
      Process.waitpid(@proc)
      @closed = true
      if @temp_directory
        FileUtils.rm_rf(@temp_directory)
      end
    }
    trap(:INT) do
      kill
      exit 130
    end
    trap(:TERM) do
      close
    end
    trap(:HUP) do
      close
    end
  end

  # @return {Promise}
  def close
    return if @closed

    if @temp_directory
      kill
    elsif @connection
      @connection.sendCommand("Browser.close")
    end
  end

  # @return {Promise}
  def kill
  end


  # @param {!({usePipe?: boolean, timeout: number, slowMo: number, preferredRevision: string})} options
  # @return {!Promise<!Connection>}
  def setup_connection(options = {})

  end
end

class Puppeteer::ChromeLauncher
  # @param {string} projectRoot
  # @param {string} preferredRevision
  def initialize(project_root:, preferred_revision:, is_puppeteer_core:)
    @project_root = project_root
    @preferred_revision = preferred_revision
    @is_puppeteer_core = is_puppeteer_core
  end


  # @param {!(Launcher.LaunchOptions & Launcher.ChromeArgOptions & Launcher.BrowserOptions)=} options
  # @return {!Promise<!Browser>}
  def launch(options = {}) # TODO: あとでキーワード引数にする
  end

  # @param {!Launcher.ChromeArgOptions=} options
  # @return {!Array<string>}
  def default_args(options = {}) # TODO: あとでキーワード引数にする
  end

  # @param {!(Launcher.BrowserOptions & {browserWSEndpoint?: string, browserURL?: string, transport?: !Puppeteer.ConnectionTransport})} options
  # @return {!Promise<!Browser>}
  def connect(options)
  end

  def executable_path
  end

  # @return [String]
  private def executable_path
    ENV["PUPPETEER_EXECUTABLE_PATH"]
  end

  private def product
    'chrome'
  end
end

class FirefoxLauncher
end

class Launcher
  # @param {string} projectRoot
  # @param {string} preferredRevision
  # @param {boolean} isPuppeteerCore
  # @param {string=} product
  # @return {!Puppeteer.ProductLauncher}
  def self.new()

  end
end
