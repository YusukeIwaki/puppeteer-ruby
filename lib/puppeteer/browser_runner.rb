require 'fileutils'
require 'open3'
require 'timeout'

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

  attr_reader :proc, :connection

  class BrowserProcess
    def initialize(env, executable_path, args)
      stdin, @stdout, @stderr, @thread = Open3.popen3(env, executable_path, *args)
      stdin.close
    end

    def dispose
      [@stdout, @stderr].each{ |io| io.close unless io.closed? }
      @thread.join
    end

    attr_reader :stdout, :stderr
  end

  # @param {!(Launcher.LaunchOptions)=} options
  def start(
    executable_path: nil,
    ignore_default_args: nil,
    handle_SIGINT: nil,
    handle_SIGTERM: nil,
    handle_SIGHUP: nil,
    timeout: nil,
    dumpio: nil,
    env: nil,
    pipe: nil
  )
    @launch_options = Puppeteer::Launcher::LaunchOptions.new({
      executable_path: executable_path,
      ignore_default_args: ignore_default_args,
      handle_SIGINT: handle_SIGINT,
      handle_SIGTERM: handle_SIGTERM,
      handle_SIGHUP: handle_SIGHUP,
      timeout: timeout,
      dumpio: dumpio,
      env: env,
      pipe: pipe
    }.compact)
    @proc = BrowserProcess.new(
      @launch_options.env,
      @executable_path,
      @process_arguments
    )
    # if (dumpio) {
    #   this.proc.stderr.pipe(process.stderr);
    #   this.proc.stdout.pipe(process.stdout);
    # }
    @closed = false
    @process_closing = -> {
      @proc.dispose
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
    if !use_pipe
      browser_ws_endpoint = wait_for_ws_endpoint(@proc, timeout, preferred_revision)
      transport = Puppeteer::WebSocketTransport.create(browser_ws_endpoint)
      @connection = Puppeteer::Connection.new(browser_ws_endpoint, transport, slow_mo)
    else
      #   const transport = new PipeTransport(/** @type {!NodeJS.WritableStream} */(this.proc.stdio[3]), /** @type {!NodeJS.ReadableStream} */ (this.proc.stdio[4]));
      transport = PipeTransport.new()
      @connection = Connection.new('', transport, slow_mo)
    end

    @connection
  end

  private def wait_for_ws_endpoint(browser_process, timeout, preferred_revision)
    Timeout.timeout(timeout / 1000) do
      loop do
        line = browser_process.stderr.readline
        /^DevTools listening on (ws:\/\/.*)$/.match(line) do |m|
          return m[1]
        end
      end
    end
  rescue Timeout::Error
    raise Puppeteer::TimeoutError.new("Timed out after #{timeout} ms while trying to connect to the browser! Only Chrome at revision r#{preferredRevision} is guaranteed to work.")
  end
end
