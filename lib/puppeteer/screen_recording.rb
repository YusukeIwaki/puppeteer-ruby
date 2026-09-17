# frozen_string_literal: true
# rbs_inline: enabled

require 'base64'

# Video-stream-based screen recording via the CDP Page.startScreenRecording
# API (Chrome 153+). Unlike the FFmpeg-based ScreenRecorder, this requires no
# external dependencies and outputs MP4.
class Puppeteer::ScreenRecording
  # @rbs page: Puppeteer::Page -- Recorded page
  # @rbs options: Hash[Symbol, untyped] -- Recording options
  def initialize(page, options = {})
    validate_options(options)

    @page = page
    @options = options
    @destinations = []
    @destinations_mutex = Mutex.new
    @buffer = +''.b
    @stopped = false
    @stop_mutex = Mutex.new
    @stream_handle = nil

    client = @page.main_frame.client
    @disconnect_listener_id = client.once(CDPSessionEmittedEvents::Disconnected) do
      stop
    rescue StandardError => error
      warn(error.message) if ENV['DEBUG']
    end
  end

  # @rbs return: String -- Encoded bytes produced so far
  def data
    @buffer.dup
  end

  # Pipes recorded chunks to a destination IO (e.g. a File opened in binary
  # mode). The destination is closed when the recording stops.
  #
  # @rbs destination: IO -- Writable binary destination
  # @rbs return: IO -- The destination
  def pipe(destination)
    @destinations_mutex.synchronize { @destinations << destination }
    destination
  end

  # Starts the CDP screen recording. Called by Page#record.
  #
  # @rbs return: void -- No return value
  def start
    client = @page.main_frame.client
    frame_rate = @options[:frame_rate] || @options[:fps]
    params = {
      audio: @options[:audio],
      maxWidth: @options[:max_width],
      maxHeight: @options[:max_height],
      frameRate: frame_rate,
    }.compact
    result = client.send_message('Page.startScreenRecording', **params)
    @stream_handle = result['stream']
    nil
  end

  # Stops the recording, drains the remaining stream chunks, and closes piped
  # destinations. Safe to call multiple times.
  #
  # @rbs return: void -- No return value
  def stop
    should_stop = @stop_mutex.synchronize do
      next false if @stopped

      @stopped = true
      true
    end
    return unless should_stop

    begin
      client = @page.main_frame.client
      begin
        client.send_message('Page.stopScreenRecording')
      rescue StandardError => error
        warn(error.message) if ENV['DEBUG']
      end
      unless @stream_handle
        raise Puppeteer::Error.new('Screen recording stream handle is missing.')
      end
      drain_stream(client)
    ensure
      remove_disconnect_listener
      close_destinations
    end
    nil
  end

  private def validate_options(options)
    max_width = options[:max_width]
    raise ArgumentError.new('`max_width` must be greater than 0.') if !max_width.nil? && max_width <= 0

    max_height = options[:max_height]
    raise ArgumentError.new('`max_height` must be greater than 0.') if !max_height.nil? && max_height <= 0

    frame_rate = options[:frame_rate]
    raise ArgumentError.new('`frame_rate` must be greater than 0.') if !frame_rate.nil? && frame_rate <= 0

    fps = options[:fps]
    raise ArgumentError.new('`fps` must be greater than 0.') if !fps.nil? && fps <= 0
  end

  private def destinations
    @destinations_mutex.synchronize { @destinations.dup }
  end

  private def drain_stream(client)
    eof = false
    until eof
      response = client.send_message('IO.read', handle: @stream_handle)
      eof = response['eof']
      data = response['data']
      next if data.nil? || data.empty?

      chunk =
        if response['base64Encoded']
          Base64.decode64(data)
        else
          data.dup.force_encoding(Encoding::BINARY)
        end
      @buffer << chunk
      destinations.each { |destination| destination.write(chunk) }
    end
    begin
      client.send_message('IO.close', handle: @stream_handle)
    rescue StandardError => error
      warn(error.message) if ENV['DEBUG']
    end
  end

  private def remove_disconnect_listener
    @page.main_frame.client.remove_event_listener(@disconnect_listener_id)
  rescue StandardError
    # The page or its CDP session may already be gone.
  end

  private def close_destinations
    destinations.each do |destination|
      destination.close unless destination.closed?
    rescue StandardError
      # Ignore errors while closing destinations.
    end
  end
end
