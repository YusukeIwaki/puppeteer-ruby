require 'spec_helper'
require 'stringio'

class FakeScreencastSession
  def add_event_listener(*_args)
    1
  end

  def once(*_args)
    2
  end

  def remove_event_listener(*_args)
    nil
  end
end

FakeScreencastFrame = Struct.new(:client)

class FakeScreencastPage
  attr_writer :stop_gate

  def initialize
    @main_frame = FakeScreencastFrame.new(FakeScreencastSession.new)
    @stop_gate = nil
  end

  attr_reader :main_frame

  def logger
    nil
  end

  def _stop_screencast
    if @stop_gate
      entered, release = @stop_gate
      entered << true
      release.pop
    end
    nil
  end
end

RSpec.describe Puppeteer::ScreenRecorder do
  describe '#read_output' do
    it 'forwards an available chunk without waiting for a full buffer or EOF' do
      reader, writer = IO.pipe
      reader.binmode
      output = StringIO.new.binmode
      recorder = described_class.allocate
      recorder.instance_variable_set(:@stdout, reader)
      recorder.instance_variable_set(:@output_io, output)
      recorder.instance_variable_set(:@output, +''.b)
      worker = Thread.new { recorder.send(:read_output) }
      begin
        writer.write('small encoded frame')
        writer.flush
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.01 while output.string.empty? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline

        expect(output.string).to eq('small encoded frame')
      ensure
        writer.close unless writer.closed?
        worker.join(5)
        reader.close unless reader.closed?
      end
    end
  end

  describe '#stop' do
    it 'waits for the in-flight stop before a concurrent stop finishes' do
      page = FakeScreencastPage.new
      entered = Queue.new
      release = Queue.new
      page.stop_gate = [entered, release]
      recorder = described_class.new(page, 800, 600)
      finished = []
      recorder.define_singleton_method(:finish_process) do
        finished << :started
        super()
      ensure
        finished << :done
      end

      first_result = Queue.new
      first = Thread.new do
        recorder.stop
        first_result << nil
      rescue StandardError => error
        first_result << error
      end
      second_done = Queue.new
      second_result = Queue.new
      second = nil
      begin
        Timeout.timeout(20) { entered.pop }
        second = Thread.new do
          recorder.stop
          second_done << true
          second_result << nil
        rescue StandardError => error
          second_done << true
          second_result << error
        end
        sleep 0.3
        # With proper serialization the second stop must still be waiting and
        # process finalization must not have started while gated.
        expect(finished).to eq([])
        expect(second_done.empty?).to eq(true)
      ensure
        release << true
        Timeout.timeout(20) do
          first.join
          second.join if second
        end
      end
      expect(second_done.pop).to eq(true)
      first_error = first_result.pop
      if first_error
        # No frames were fed, so FFmpeg exits unsuccessfully; the stop
        # serialization under test is unaffected. Permit only that expected
        # failure, not arbitrary errors.
        expect(first_error).to be_a(Puppeteer::Error)
        expect(first_error.message).to start_with('ffmpeg exited unsuccessfully')
      end
      expect(second_result.pop).to be_nil
    end
  end
end
