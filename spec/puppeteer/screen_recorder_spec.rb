require 'spec_helper'
require 'stringio'

RSpec.describe Puppeteer::ScreenRecorder do
  describe '.count_frames' do
    fps = 30

    total_frames = lambda do |capture_fps, seconds, output_fps = fps|
      frames = (capture_fps * seconds).round
      total = 0
      previous = 0
      1.upto(frames) do |index|
        timestamp = index.fdiv(capture_fps)
        total += described_class.count_frames(0, previous, timestamp, output_fps)
        previous = timestamp
      end
      total
    end

    it 'keeps the total close to fps * duration for any capture rate' do
      [24, 30, 31, 48, 53, 60, 90, 120].each do |capture_fps|
        total = total_frames.call(capture_fps, 1)
        expect(total).to be_between(fps - 1, fps + 1)
      end
    end

    it 'does not inflate the count when captured faster than fps' do
      expect(total_frames.call(60, 1)).to be <= fps + 1
    end

    it 'does not drop all frames when captured much faster than fps' do
      expect(total_frames.call(120, 1)).to be >= fps - 1
    end

    it 'scales with the requested fps' do
      expect(total_frames.call(60, 1, 60)).to be_between(59, 61)
    end

    it 'returns zero for non-increasing timestamps' do
      expect(described_class.count_frames(0, 1, 1, fps)).to eq(0)
      expect(described_class.count_frames(0, 1, 0.5, fps)).to eq(0)
    end
  end

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
end
