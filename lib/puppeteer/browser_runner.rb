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
    @launch_options = Puppeteer::Launcher::LaunchOptions.new(options)
    @proc = spawn(
      launch_options.env,
      "#{@executable_path} #{@process_arguments.join(" ")}",
      out: :out,
      err: :err)
    @closed = false
    @process_closing = -> {
      Process.waitpid(@proc)
      @closed = true
      if @temp_directory
        FileUtils.rm_rf(@temp_directory)
      end
    }
    trap(:EXIT) do
      kill
    end

    if @launch_options.handle_SIGINT?
      trap(:INT) do
        kill
        exit 130
      end
    end

    if @launch_options.handle_SIGTERM?
      trap(:TERM) do
        close
      end
    end

    if @launch_options.handle_SIGHUP?
      trap(:HUP) do
        close
      end
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
  def setup_connection(use_pipe:, timeout:, slow_mo:, preferred_revision:)
    if !user_pipe
      browser_ws_endpoint = wait_for_ws_endpoint(@proc, timeout, preferred_revision)
      transport = WebSocketTransport.create(browser_ws_endpoint)
      @connection = Connection.new(browser_ws_endpoint, transport, slow_mo)
    else
      #   const transport = new PipeTransport(/** @type {!NodeJS.WritableStream} */(this.proc.stdio[3]), /** @type {!NodeJS.ReadableStream} */ (this.proc.stdio[4]));
      transport = PipeTransport.new()
      @connection = Connection.new('', transport, slow_mo)
    end

    @connection
  end
end
