require 'spec_helper'
require 'stringio'
require 'tmpdir'
require_relative '../support/fake_screen_recording'

# Ruby-specific boundary coverage for ScreenRecording: behaviors the
# upstream unit suite implies but does not pin down (validation ordering,
# stop serialization, destination Set semantics, stream termination, and
# destination close contracts).
RSpec.describe 'ScreenRecording (boundary contracts)' do
  include RecordingSpecHelpers

  it 'rejects invalid options before truncating an existing file' do
    client = FakeRecordingSession.new
    Dir.mktmpdir('puppeteer-record-') do |directory|
      path = File.join(directory, 'existing.mp4')
      File.binwrite(path, 'KEEP EXISTING RECORDING')

      expect { build_recording(client, path: path, max_width: 0) }.to raise_error(ArgumentError)

      expect(File.binread(path)).to eq('KEEP EXISTING RECORDING')
      expect(client.commands).to be_empty
    end
  end

  it 'decodes non-base64 chunks' do
    client = FakeRecordingSession.new
    client.read_chunks = [{ 'data' => 'plain', 'base64Encoded' => false, 'eof' => true }]

    recording = build_recording(client)
    recording.stop

    expect(recording.data).to eq('plain'.b)
  end

  it 'raises when the stream handle is missing' do
    client = FakeRecordingSession.new
    client.start_response = {}

    recording = build_recording(client)
    expect { recording.stop }.to raise_error(Puppeteer::Error, 'Screen recording stream handle is missing.')
  end

  it 'waits for the in-flight stop before a concurrent stop returns' do
    client = FakeRecordingSession.new

    Async do |task|
      entered = Async::Queue.new
      release = Async::Queue.new
      client.define_singleton_method(:send_message) do |method, params = {}|
        client.commands << { method: method, params: params }
        case method
        when 'Page.startScreenRecording'
          { 'stream' => 'stream-1' }
        when 'IO.read'
          entered.enqueue(true)
          release.dequeue
          { 'data' => Base64.strict_encode64('payload'), 'base64Encoded' => true, 'eof' => true }
        else
          {}
        end
      end

      recording = build_recording(client)
      dest = StringIO.new.binmode
      recording.pipe(dest)

      first = task.async { recording.stop }
      entered.dequeue
      second = task.async { recording.stop }
      # Give the second stop time to run: with proper serialization it must
      # still be waiting when checked.
      20.times do
        break if second.finished?
        task.sleep(0.01)
      end
      second_returned_before_output_closed = second.finished? && !dest.closed?
      release.enqueue(true)
      first.wait
      second.wait

      expect(second_returned_before_output_closed).to eq(false)
      expect(dest.string).to eq('payload')
    end.wait
  end

  it 'does not duplicate bytes when the same destination is piped twice' do
    client = FakeRecordingSession.new
    client.read_chunks = [base64_chunk('payload', eof: true)]

    recording = build_recording(client)
    dest = StringIO.new.binmode
    recording.pipe(dest)
    recording.pipe(dest)
    recording.stop

    expect(dest.string).to eq('payload')
  end

  it 'drops destinations that fail while writing' do
    client = FakeRecordingSession.new
    client.read_chunks = [base64_chunk('payload', eof: true)]

    recording = build_recording(client)
    broken = StringIO.new.binmode
    broken.close
    recording.pipe(broken)
    recording.stop

    expect(recording.data).to eq('payload')
  end

  it 'closes piped destinations on stop' do
    client = FakeRecordingSession.new
    client.read_chunks = [base64_chunk('data', eof: true)]

    recording = build_recording(client)
    dest = StringIO.new.binmode
    recording.pipe(dest)
    recording.stop

    expect(dest).to be_closed
  end

  it 'closes a destination implementing only write and close' do
    client = FakeRecordingSession.new
    client.read_chunks = [base64_chunk('data', eof: true)]

    recording = build_recording(client)
    written = +''.b
    closed = false
    destination = Object.new
    destination.define_singleton_method(:write) do |chunk|
      written << chunk
      chunk.bytesize
    end
    destination.define_singleton_method(:close) { closed = true }
    recording.pipe(destination)
    recording.stop

    expect(written).to eq('data'.b)
    expect(closed).to eq(true)
  end

  it 'finishes re-iteration after the stream has been consumed' do
    client = FakeRecordingSession.new
    client.read_chunks = [base64_chunk('payload', eof: true)]

    recording = build_recording(client)
    recording.stop

    Async do |task|
      expect(recording.each_chunk.to_a).to eq(['payload'])
      # A second iteration must end immediately like upstream's closed
      # ReadableStream instead of waiting for more chunks.
      expect(task.with_timeout(5) { recording.each_chunk.to_a }).to eq([])
    end.wait
  end
end
