# frozen_string_literal: true
# rbs_inline: enabled

require 'async'
require 'thread'

class Puppeteer::PipeTransport
  class ClosedError < Puppeteer::Error; end

  # @rbs pipe_write: IO -- Pipe used to write messages to Chrome
  # @rbs pipe_read: IO -- Pipe used to read messages from Chrome
  # @rbs return: void -- No return value
  def initialize(pipe_write, pipe_read)
    @pipe_write = pipe_write
    @pipe_read = pipe_read
    @pipe_write.binmode
    @pipe_read.binmode
    @write_mutex = Mutex.new
    @close_mutex = Mutex.new
    @closed = false
    @on_message = nil
    @on_close = nil
    @pending_message = +''.b

    @task = Async do
      receive_loop
    rescue Async::Stop
      # Task was stopped; ignore.
    ensure
      close
    end
  end

  # @rbs message: String -- CDP message to send
  # @rbs return: void -- No return value
  def send_text(message)
    raise ClosedError.new('`PipeTransport` is closed.') if closed?

    @write_mutex.synchronize do
      @pipe_write.write(message)
      @pipe_write.write("\0")
      @pipe_write.flush
    end
  rescue IOError, Errno::ECONNRESET, Errno::EPIPE
    close
    raise
  end

  # @rbs return: void -- No return value
  def close
    should_close = @close_mutex.synchronize do
      next false if @closed

      @closed = true
      true
    end
    return unless should_close

    [@pipe_write, @pipe_read].each do |pipe|
      pipe.close unless pipe.closed?
    rescue IOError
      # Pipe already closed; ignore.
    end
    @on_close&.call(nil, nil)
    @task&.stop unless @task.equal?(Async::Task.current?)
  rescue Async::Stop
    # Task was already stopping; ignore.
  end

  # @rbs &block: ^(untyped, untyped) -> untyped -- Close callback
  # @rbs return: void -- No return value
  def on_close(&block)
    @on_close = block
  end

  # @rbs &block: ^(String) -> untyped -- Message callback
  # @rbs return: void -- No return value
  def on_message(&block)
    @on_message = block
  end

  # @rbs return: bool -- Whether the transport is closed
  def closed?
    @close_mutex.synchronize { @closed }
  end

  private def receive_loop
    loop do
      buffer = @pipe_read.read_nonblock(65_536)
      dispatch(buffer)
    rescue IO::WaitReadable
      wait_for_io(@pipe_read, IO::READABLE)
      retry
    end
  rescue EOFError, IOError, Errno::ECONNRESET, Errno::EPIPE
    # Pipe closed; no-op.
  end

  # @rbs buffer: String -- Bytes received from Chrome
  # @rbs return: void -- No return value
  private def dispatch(buffer)
    raise ClosedError.new('`PipeTransport` is closed.') if closed?

    @pending_message << buffer
    while (ending = @pending_message.index("\0"))
      message = @pending_message.byteslice(0, ending)
      @pending_message = @pending_message.byteslice((ending + 1)..) || +''.b
      @on_message&.call(message.force_encoding(Encoding::UTF_8))
      Async::Task.current.sleep(0)
    end
  end

  private def wait_for_io(io, events)
    scheduler = Fiber.scheduler
    if scheduler
      scheduler.io_wait(io, events)
    else
      IO.select(
        events == IO::READABLE ? [io] : nil,
        events == IO::WRITABLE ? [io] : nil,
      )
    end
  end
end
