# frozen_string_literal: true
# rbs_inline: enabled

require 'fileutils'
require 'open3'
require 'etc'

class Puppeteer::ScreenRecorder
  DEFAULT_FPS = 30
  DEFAULT_QUALITY = 30
  STOP = Object.new.freeze

  # @rbs start_timestamp: Numeric -- First CDP frame timestamp
  # @rbs previous_timestamp: Numeric -- Previous CDP frame timestamp
  # @rbs timestamp: Numeric -- Current CDP frame timestamp
  # @rbs fps: Numeric -- Output frame rate
  # @rbs return: Integer -- Frames to emit for this interval
  def self.count_frames(start_timestamp, previous_timestamp, timestamp, fps)
    finish = ((timestamp - start_timestamp) * fps).round
    start = ((previous_timestamp - start_timestamp) * fps).round
    [0, finish - start].max
  end

  # @rbs page: Puppeteer::Page -- Recorded page
  # @rbs width: Numeric -- Native viewport width
  # @rbs height: Numeric -- Native viewport height
  # @rbs options: Hash[Symbol, untyped] -- Recorder options
  def initialize(page, width, height, options = {})
    @page = page
    @fps = options.fetch(:fps, DEFAULT_FPS)
    @format = (options[:format] || 'webm').to_s
    @path = options[:path]
    @stopped = false
    @stop_mutex = Mutex.new
    @finished = false
    @finish_mutex = Mutex.new
    @frame_queue = Queue.new
    @output = +''.b
    @last_buffer = ''.b
    @last_written_at = monotonic_time
    @start_timestamp = nil
    @previous_timestamp = nil
    @previous_buffer = nil

    ensure_output_directory
    command = build_command(width, height, options)
    @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(*command)
    @stdin.binmode
    @stdout.binmode

    @writer_thread = Thread.new { write_frames }
    @stdout_thread = Thread.new { read_output }
    @stderr_thread = Thread.new { read_stderr }

    @client = @page.main_frame.client
    @frame_listener_id = @client.add_event_listener('Page.screencastFrame') do |event|
      handle_frame(event)
    end
    @disconnect_listener_id = @client.once(CDPSessionEmittedEvents::Disconnected) do
      stop
    rescue StandardError => error
      warn(error.message) if ENV['DEBUG']
    end
  end

  # @rbs return: String -- Encoded bytes produced so far
  def data
    @output.dup
  end

  # @rbs return: void -- Stop recording and flush FFmpeg
  def stop
    should_stop = @stop_mutex.synchronize do
      next false if @stopped

      @stopped = true
      true
    end
    unless should_stop
      finish_process
      return
    end

    begin
      @page._stop_screencast
    rescue StandardError
      # The page or its CDP session may already be gone.
    end
    enqueue_last_frame
    finish_process
  end

  private def ensure_output_directory
    return unless @path

    FileUtils.mkdir_p(File.dirname(File.expand_path(@path)))
  end

  private def build_command(width, height, options)
    ffmpeg_path = options[:ffmpeg_path] || 'ffmpeg'
    speed = options[:speed]
    scale = options[:scale]
    crop = options[:crop]
    loop_count = options[:loop]
    loop_count = -1 if loop_count.nil? || loop_count.zero?
    delay = options.fetch(:delay, -1)
    quality = options.fetch(:quality, DEFAULT_QUALITY)
    colors = options.fetch(:colors, 256)

    filters = [
      "crop='min(#{width},iw):min(#{height},ih):0:0'",
      "pad=#{width}:#{height}:0:0",
    ]
    filters << "setpts=#{1.0 / speed}*PTS" if speed
    if crop
      filters << "crop=#{crop[:width]}:#{crop[:height]}:#{crop[:x]}:#{crop[:y]}"
    end
    filters << "scale=iw*#{scale}:-1:flags=lanczos" if scale

    format_args = format_args(@format, @fps, loop_count, delay, quality, colors)
    if (vf_index = format_args.index('-vf'))
      filters << format_args.slice!(vf_index, 2).last
    end

    [
      ffmpeg_path,
      '-loglevel', 'error',
      '-avioflags', 'direct',
      '-fpsprobesize', '0',
      '-probesize', '32',
      '-analyzeduration', '0',
      '-fflags', 'nobuffer',
      # -framerate is an input option and must precede -i.
      '-framerate', @fps.to_s,
      '-f', 'image2pipe',
      '-vcodec', 'png',
      '-i', 'pipe:0',
      '-an',
      '-threads', '1',
      '-b:v', '0',
      *format_args,
      '-vf', filters.join(','),
      options.fetch(:overwrite, true) ? '-y' : '-n',
      'pipe:1'
    ]
  end

  private def format_args(format, fps, loop_count, delay, quality, colors)
    cpu_used = [Etc.nprocessors / 2.0, 8].min
    cpu_used = cpu_used.to_i if cpu_used.to_i == cpu_used
    libvpx = [
      '-vcodec', 'vp9',
      '-crf', quality.to_s,
      '-deadline', 'realtime',
      '-cpu-used', cpu_used.to_s
    ]
    case format
    when 'webm'
      [*libvpx, '-f', 'webm']
    when 'gif'
      gif_fps = fps == DEFAULT_FPS ? 20 : 'source_fps'
      gif_loop = loop_count.infinite? ? 0 : loop_count
      gif_delay = delay == -1 ? -1 : delay / 10.0
      [
        '-vf',
        "fps=#{gif_fps},split[s0][s1];" \
        "[s0]palettegen=stats_mode=diff:max_colors=#{colors}[p];" \
        '[s1][p]paletteuse=dither=bayer',
        '-loop', gif_loop.to_s,
        '-final_delay', gif_delay.to_s,
        '-f', 'gif'
      ]
    when 'mp4'
      [*libvpx, '-movflags', 'hybrid_fragmented', '-f', 'mp4']
    else
      raise ArgumentError.new("Unknown screencast format: #{format}")
    end
  end

  private def handle_frame(event)
    @client.async_send_message(
      'Page.screencastFrameAck',
      sessionId: event['sessionId'],
    )
    timestamp = event.dig('metadata', 'timestamp')
    return unless timestamp

    buffer = Base64.decode64(event['data'])
    if @previous_timestamp
      @start_timestamp ||= @previous_timestamp
      count = self.class.count_frames(
        @start_timestamp,
        @previous_timestamp,
        timestamp,
        @fps,
      )
      count.times { @frame_queue << @previous_buffer }
      unless count.zero?
        @last_buffer = @previous_buffer
        @last_written_at = monotonic_time
      end
    end
    @previous_timestamp = timestamp
    @previous_buffer = buffer
  end

  private def enqueue_last_frame
    buffer = @last_buffer
    return if buffer.empty?

    remaining = [1, (@fps * (monotonic_time - @last_written_at)).round].max
    remaining.times { @frame_queue << buffer }
  end

  private def finish_process
    @finish_mutex.synchronize do
      return if @finished

      begin
        @client&.remove_event_listener(@frame_listener_id, @disconnect_listener_id)
        @frame_queue << STOP if @writer_thread&.alive?
        @writer_thread&.join
        @stdin&.close unless @stdin&.closed?
        @wait_thread&.join
        @stdout_thread&.join
        @stderr_thread&.join
        File.binwrite(@path, @output) if @path
        unless @wait_thread&.value&.success?
          raise Puppeteer::Error.new("ffmpeg exited unsuccessfully: #{@ffmpeg_error}")
        end
      ensure
        @finished = true
      end
    end
    nil
  end

  private def write_frames
    loop do
      buffer = @frame_queue.pop
      break if buffer.equal?(STOP)

      @stdin.write(buffer)
    end
  rescue Errno::EPIPE, IOError
    nil
  ensure
    @stdin.close unless @stdin.closed?
  end

  private def read_output
    while (chunk = @stdout.read(16 * 1024)) && !chunk.empty?
      @output << chunk
    end
  rescue IOError
    nil
  end

  private def read_stderr
    @ffmpeg_error = @stderr.read.to_s
    warn(@ffmpeg_error) if ENV['DEBUG'] && !@ffmpeg_error.empty?
  rescue IOError
    nil
  end

  private def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
