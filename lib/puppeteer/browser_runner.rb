require 'fileutils'
require 'open3'
require 'timeout'

# https://github.com/puppeteer/puppeteer/blob/master/lib/Launcher.js
class Puppeteer::BrowserRunner
  include Puppeteer::DebugPrint

  # @param {string} executablePath
  # @param {!Array<string>} processArguments
  # @param {string=} tempDirectory
  def initialize(for_firefox, executable_path, process_arguments, user_data_dir, using_temp_user_data_dir)
    @for_firefox = for_firefox
    @executable_path = executable_path
    @process_arguments = process_arguments
    @user_data_dir = user_data_dir
    @using_temp_user_data_dir = using_temp_user_data_dir
    @proc = nil
    @connection = nil
    @closed = true
  end

  attr_reader :proc, :connection

  class BrowserProcess
    def initialize(env, executable_path, args)
      @spawnargs =
        if args && !args.empty?
          [executable_path] + args
        else
          [executable_path]
        end

      popen3_args = args || []
      popen3_args << { pgroup: true } unless Puppeteer.env.windows?
      stdin, @stdout, @stderr, @thread = Open3.popen3(env, executable_path, *popen3_args)
      stdin.close
      @pid = @thread.pid
    rescue Errno::ENOENT => err
      raise LaunchError.new(err.message)
    end

    def kill
      Process.kill(:KILL, @pid)
    rescue Errno::ESRCH
      # already killed
    end

    def dispose
      [@stdout, @stderr].each { |io| io.close unless io.closed? }
      @thread.join
    end

    attr_reader :stdout, :stderr, :spawnargs
  end

  class LaunchError < StandardError
    def initialize(reason)
      super("Failed to launch browser! #{reason}")
    end
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
      pipe: pipe,
    }.compact)
    @proc = BrowserProcess.new(
      @launch_options.env,
      @executable_path,
      @process_arguments,
    )
    # if (dumpio) {
    #   this.proc.stderr.pipe(process.stderr);
    #   this.proc.stdout.pipe(process.stdout);
    # }
    @closed = false
    @process_closing = -> {
      @proc.dispose
      @closed = true
      if @using_temp_user_data_dir
        FileUtils.rm_rf(@user_data_dir)
      end
    }
    at_exit do
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

    if @launch_options.handle_SIGHUP? && !Puppeteer.env.windows?
      trap(:HUP) do
        close
      end
    end
  end

  # @return {Promise}
  def close
    return if @closed

    if @using_temp_user_data_dir && !@for_firefox
      kill
    elsif @connection
      begin
        @connection.send_message('Browser.close')
      rescue
        kill
      end
    end

    @process_closing.call
  end

  # @return {Promise}
  def kill
    # If the process failed to launch (for example if the browser executable path
    # is invalid), then the process does not get a pid assigned. A call to
    # `proc.kill` would error, as the `pid` to-be-killed can not be found.
    @proc&.kill

    # Attempt to remove temporary profile directory to avoid littering.
    begin
      if @using_temp_user_data_dir
        FileUtils.rm_rf(@user_data_dir)
      end
    rescue => err
      debug_puts(err)
    end
  end


  # @param {!({usePipe?: boolean, timeout: number, slowMo: number, preferredRevision: string})} options
  # @return {!Promise<!Connection>}
  def setup_connection(use_pipe:, timeout:, slow_mo:, preferred_revision:)
    if !use_pipe
      browser_ws_endpoint = wait_for_ws_endpoint(@proc, timeout, preferred_revision)
      transport = Puppeteer::WebSocketTransport.create(browser_ws_endpoint)
      @connection = Puppeteer::Connection.new(browser_ws_endpoint, transport, slow_mo)
    else
      raise NotImplementedError.new('PipeTransport is not yet implemented')
    end

    @connection
  end

  private def wait_for_ws_endpoint(browser_process, timeout, preferred_revision)
    lines = []
    Timeout.timeout(timeout / 1000.0) do
      loop do
        line = browser_process.stderr.readline
        /^DevTools listening on (ws:\/\/.*)$/.match(line) do |m|
          return m[1]
        end
        lines << line
      end
    end
  rescue EOFError
    raise LaunchError.new("\n#{lines.join("\n")}\nTROUBLESHOOTING: https://github.com/puppeteer/puppeteer/blob/main/docs/troubleshooting.md")
  rescue Timeout::Error
    raise Puppeteer::TimeoutError.new("Timed out after #{timeout} ms while trying to connect to the browser! Only Chrome at revision r#{preferred_revision} is guaranteed to work.")
  end
end
