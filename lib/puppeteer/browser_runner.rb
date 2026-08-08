require 'fileutils'
require 'fcntl'
require 'open3'
require 'socket'
# https://github.com/puppeteer/puppeteer/blob/master/lib/Launcher.js
class Puppeteer::BrowserRunner
  include Puppeteer::DebugPrint

  # @param {string} executablePath
  # @param {!Array<string>} processArguments
  # @param {string=} tempDirectory
  def initialize(executable_path, process_arguments, user_data_dir, using_temp_user_data_dir)
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
    def initialize(env, executable_path, args, pipe: false)
      @spawnargs =
        if args && !args.empty?
          [executable_path] + args
        else
          [executable_path]
        end

      if pipe
        browser_stdin, @stdin = IO.pipe
        @stdout, browser_stdout = IO.pipe
        @stderr, browser_stderr = IO.pipe
        if Puppeteer.env.windows?
          browser_pipe_read, @pipe_write = IO.pipe
          @pipe_read, browser_pipe_write = IO.pipe
        else
          browser_pipe_read, @pipe_write = UNIXSocket.pair
          browser_pipe_write, @pipe_read = UNIXSocket.pair
        end
        [browser_pipe_read, browser_pipe_write].each do |browser_pipe|
          flags = browser_pipe.fcntl(Fcntl::F_GETFL)
          browser_pipe.fcntl(Fcntl::F_SETFL, flags & ~Fcntl::O_NONBLOCK)
        end
        spawn_options = {
          in: browser_stdin,
          out: browser_stdout,
          err: browser_stderr,
          3 => browser_pipe_read,
          4 => browser_pipe_write,
        }
        spawn_options[:pgroup] = true unless Puppeteer.env.windows?
        @pid = Process.spawn(env, executable_path, *(args || []), spawn_options)
        @thread = Process.detach(@pid)
        [browser_stdin, browser_stdout, browser_stderr, browser_pipe_read, browser_pipe_write].each(&:close)
      else
        popen3_args = (args || []).dup
        spawn_options = {}
        spawn_options[:pgroup] = true unless Puppeteer.env.windows?
        popen3_args << spawn_options unless spawn_options.empty?
        stdin, @stdout, @stderr, @thread = Open3.popen3(env, executable_path, *popen3_args)
        stdin.close
        @pid = @thread.pid
      end
    rescue Errno::ENOENT => err
      raise LaunchError.new(err.message)
    end

    def kill
      Process.kill(:KILL, @pid)
    rescue Errno::ESRCH
      # already killed
    end

    def dispose
      [@stdin, @stdout, @stderr, @pipe_write, @pipe_read].compact.each do |io|
        io.close unless io.closed?
      end
      @thread.join
    end

    attr_reader :stdout, :stderr, :spawnargs, :pipe_write, :pipe_read
  end

  class LaunchError < Puppeteer::Error
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
      pipe: @launch_options.pipe?,
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

    if @using_temp_user_data_dir
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


  # @param {!({usePipe?: boolean, timeout: number, slowMo: number, preferredRevision: string, protocolTimeout: number?})} options
  # @return {!Promise<!Connection>}
  def setup_connection(use_pipe:, timeout:, slow_mo:, preferred_revision:, protocol_timeout: nil)
    if !use_pipe
      browser_ws_endpoint = wait_for_ws_endpoint(@proc, timeout, preferred_revision)
      transport = Puppeteer::WebSocketTransport.create(browser_ws_endpoint)
      @connection = Puppeteer::Connection.new(
        browser_ws_endpoint,
        transport,
        slow_mo,
        protocol_timeout: protocol_timeout,
      )
    else
      transport = Puppeteer::PipeTransport.new(@proc.pipe_write, @proc.pipe_read)
      @connection = Puppeteer::Connection.new(
        '',
        transport,
        slow_mo,
        protocol_timeout: protocol_timeout,
      )
    end

    @connection
  end

  private def wait_for_ws_endpoint(browser_process, timeout, preferred_revision)
    lines = []
    wait_for_endpoint = lambda do
      loop do
        line = browser_process.stderr.readline
        /^WebDriver BiDi listening on (ws:\/\/.*)$/.match(line) do |m|
          raise NotImplementedError.new('WebDriver BiDi support is not yet implemented')
        end

        /^DevTools listening on (ws:\/\/.*)$/.match(line) do |m|
          return m[1].gsub(/\r/, '')
        end
        lines << line
      end
    end

    if timeout && timeout > 0
      Puppeteer::AsyncUtils.async_timeout(timeout, wait_for_endpoint).wait
    else
      wait_for_endpoint.call
    end
  rescue EOFError
    raise LaunchError.new("\n#{lines.join("\n")}\nTROUBLESHOOTING: https://github.com/puppeteer/puppeteer/blob/main/docs/troubleshooting.md")
  rescue Async::TimeoutError
    raise Puppeteer::TimeoutError.new("Timed out after #{timeout} ms while trying to connect to the browser! Only Chrome at revision r#{preferred_revision} is guaranteed to work.")
  end
end
