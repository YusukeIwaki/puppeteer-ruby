# frozen_string_literal: true
# rbs_inline: enabled

require 'base64'

# Video-stream-based screen recording via the CDP Page.startScreenRecording
# API (Chrome 153+). Unlike the FFmpeg-based ScreenRecorder, this requires no
# external dependencies and outputs MP4.
#
# Ruby adaptation notes (upstream api/ScreenRecording is a ReadableStream):
# - Iteration uses #each_chunk, which yields Binary chunks as they arrive.
# - #close stops the recording; it is the Ruby equivalent of upstream async
#   disposal.
# - #pipe accepts IO-like destinations (StringIO, File, or any object
#   responding to write/close); destinations are deduplicated like upstream.
class Puppeteer::ScreenRecording
  # Terminator pushed after the last chunk so chunk iteration can finish.
  END_OF_STREAM = Object.new.freeze
  private_constant :END_OF_STREAM

  # @rbs page: Puppeteer::Page -- Recorded page
  # @rbs options: Hash[Symbol, untyped] -- Recording options
  def initialize(page, options = {})
    @page = page
    @options = options
    @destinations = Set.new
    @destinations_mutex = Mutex.new
    @buffer = +''.b
    @chunk_queue = Async::Queue.new
    @stopped = false
    @stop_semaphore = Async::Semaphore.new(1)
    @stream_handle = nil

    client = @page.main_frame.client
    @disconnect_listener_id = client.once(CDPSessionEmittedEvents::Disconnected) do
      stop
    rescue StandardError => error
      log_error(error)
    end
  end

  # @rbs return: String -- Encoded bytes produced so far
  def data
    @buffer.dup
  end

  # Yields each recorded chunk as it arrives. When called without a block,
  # returns an Enumerator. This is the Ruby equivalent of async-iterating the
  # upstream ReadableStream.
  #
  # @rbs return: Enumerator[String, void] -- Chunk enumerator when no block is given
  def each_chunk(&block)
    return enum_for(:each_chunk) unless block

    loop do
      chunk = @chunk_queue.dequeue
      break if chunk.equal?(END_OF_STREAM)

      yield chunk
    end
    nil
  end

  # Pipes recorded chunks to a destination (e.g. a File opened in binary
  # mode, or any object responding to write and close). The same destination
  # is only registered once, mirroring upstream's Set. Evented destinations
  # responding to once are removed on unpipe/error/close/finish; other
  # destinations are dropped once closed or failing. The destination is
  # closed when the recording stops.
  #
  # @rbs destination: IO -- Writable binary destination
  # @rbs return: IO -- The destination
  def pipe(destination)
    @destinations_mutex.synchronize { @destinations.add(destination) }
    if destination.respond_to?(:once)
      %w[unpipe error close finish].each do |event|
        destination.once(event) { remove_destination(destination) }
      end
    end
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
  # destinations. Concurrent calls wait for the in-flight stop to finish
  # (mirroring upstream's @guarded), and further calls are no-ops.
  #
  # @rbs return: void -- No return value
  def stop
    @stop_semaphore.acquire do
      return if @stopped

      @stopped = true
      begin
        client = @page.main_frame.client
        begin
          client.send_message('Page.stopScreenRecording')
        rescue StandardError => error
          log_error(error)
        end
        unless @stream_handle
          raise Puppeteer::Error.new('Screen recording stream handle is missing.')
        end
        drain_stream(client)
      ensure
        @chunk_queue.enqueue(END_OF_STREAM)
        remove_disconnect_listener
        close_destinations
      end
    end
    nil
  end

  # Stops the recording and releases it. This is the Ruby equivalent of
  # upstream async disposal.
  #
  # @rbs return: void -- No return value
  def close
    stop
  end

  private def remove_destination(destination)
    @destinations_mutex.synchronize { @destinations.delete(destination) }
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
      @chunk_queue.enqueue(chunk)
      write_destinations(chunk)
    end
    begin
      client.send_message('IO.close', handle: @stream_handle)
    rescue StandardError => error
      log_error(error)
    end
  end

  private def write_destinations(chunk)
    destinations.each do |destination|
      if destination.respond_to?(:closed?) && destination.closed?
        remove_destination(destination)
        next
      end
      begin
        destination.write(chunk)
      rescue StandardError
        remove_destination(destination)
      end
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

  private def log_error(error)
    @page.logger&.call(Puppeteer::DebugPrefixes::ERROR)&.call(error)
    warn(error.message) if ENV['DEBUG']
  end
end
