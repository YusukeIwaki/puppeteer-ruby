require 'spec_helper'
require 'async'
require 'base64'
require 'stringio'
require 'tmpdir'

class FakeRecordingSession
  attr_reader :commands
  attr_accessor :read_chunks, :start_response

  def initialize
    @commands = []
    @read_chunks = []
    @start_response = { 'stream' => 'stream-1' }
    @listeners = {}
    @next_listener_id = 0
  end

  def send_message(method, params = {})
    @commands << { method: method, params: params }
    case method
    when 'Page.startScreenRecording'
      @start_response
    when 'Page.stopScreenRecording'
      {}
    when 'IO.read'
      @read_chunks.shift || { 'data' => '', 'base64Encoded' => false, 'eof' => true }
    when 'IO.close'
      {}
    else
      {}
    end
  end

  def once(_event, &block)
    @next_listener_id += 1
    @listeners[@next_listener_id] = block
    @next_listener_id
  end

  def remove_event_listener(*ids)
    ids.each { |id| @listeners.delete(id) }
  end

  def emit_disconnect
    @listeners.each_value(&:call)
  end
end

FakeRecordingFrame = Struct.new(:client)

# Minimal Page double exercising the real Page#record orchestration
# (validation, file handling, recorder lifecycle) against a fake CDP client,
# mirroring upstream's MockPage.
class MockRecordPage < Puppeteer::Page
  def initialize(client)
    @fake_client = client
  end

  def main_frame
    @fake_frame ||= FakeRecordingFrame.new(@fake_client)
  end

  def logger
    nil
  end
end

RSpec.describe Puppeteer::ScreenRecording do
  def build_recording(client, options = {})
    MockRecordPage.new(client).record(**options)
  end

  def base64_chunk(text, eof:)
    { 'data' => Base64.strict_encode64(text), 'base64Encoded' => true, 'eof' => eof }
  end

  it 'starts recording and reads all chunks on stop' do
    client = FakeRecordingSession.new
    client.read_chunks = [base64_chunk('chunk1', eof: false), base64_chunk('chunk2', eof: true)]

    recording = build_recording(client,
      audio: true, max_width: 1920, max_height: 1080, frame_rate: 60)

    expect(client.commands[0]).to eq(
      method: 'Page.startScreenRecording',
      params: { audio: true, maxWidth: 1920, maxHeight: 1080, frameRate: 60 },
    )

    dest = StringIO.new.binmode
    recording.pipe(dest)
    recording.stop

    expect(recording.data).to eq('chunk1chunk2'.b)
    expect(dest.string).to eq('chunk1chunk2'.b)
    expect(client.commands).to include(method: 'Page.stopScreenRecording', params: {})
    expect(client.commands).to include(method: 'IO.close', params: { handle: 'stream-1' })
  end

  it 'supports fps as alias for frameRate' do
    client = FakeRecordingSession.new

    recording = build_recording(client, fps: 24)

    expect(client.commands[0]).to eq(
      method: 'Page.startScreenRecording',
      params: { frameRate: 24 },
    )
    recording.stop
  end

  it 'validates options' do
    client = FakeRecordingSession.new

    expect { build_recording(client, max_width: 0) }.to raise_error(ArgumentError, '`max_width` must be greater than 0.')
    expect { build_recording(client, max_width: -10) }.to raise_error(ArgumentError, '`max_width` must be greater than 0.')
    expect { build_recording(client, max_height: 0) }.to raise_error(ArgumentError, '`max_height` must be greater than 0.')
    expect { build_recording(client, max_height: -10) }.to raise_error(ArgumentError, '`max_height` must be greater than 0.')
    expect { build_recording(client, frame_rate: 0) }.to raise_error(ArgumentError, '`frame_rate` must be greater than 0.')
    expect { build_recording(client, frame_rate: -5) }.to raise_error(ArgumentError, '`frame_rate` must be greater than 0.')
    expect { build_recording(client, fps: 0) }.to raise_error(ArgumentError, '`fps` must be greater than 0.')
    expect { build_recording(client, fps: -5) }.to raise_error(ArgumentError, '`fps` must be greater than 0.')
    expect(client.commands).to be_empty
  end

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

  it 'uses the stream handle returned from startScreenRecording' do
    client = FakeRecordingSession.new
    client.start_response = { 'stream' => 'stream-start' }
    client.read_chunks = [base64_chunk('hello', eof: true)]

    recording = build_recording(client)

    dest = StringIO.new.binmode
    recording.pipe(dest)
    recording.stop

    expect(recording.data).to eq('hello'.b)
    expect(dest.string).to eq('hello'.b)
    expect(client.commands).to include(method: 'IO.close', params: { handle: 'stream-start' })
  end

  it 'yields chunks as they arrive' do
    client = FakeRecordingSession.new
    client.read_chunks = [base64_chunk('chunkA', eof: false), base64_chunk('chunkB', eof: true)]

    recording = build_recording(client)

    received = []
    Async do |task|
      stop_task = task.async { recording.stop }
      recording.each_chunk { |chunk| received << chunk }
      stop_task.wait
    end.wait

    expect(received.join).to eq('chunkAchunkB')
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

  it 'stops on client disconnection and treats a second stop as no-op' do
    client = FakeRecordingSession.new

    recording = build_recording(client)

    client.emit_disconnect
    recording.stop

    stop_commands = client.commands.select { |command| command[:method] == 'Page.stopScreenRecording' }
    expect(stop_commands.length).to eq(1)
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

  it 'close stops the recording like async disposal' do
    client = FakeRecordingSession.new
    client.read_chunks = [base64_chunk('data', eof: true)]

    recording = build_recording(client)
    recording.close
    recording.close

    stop_commands = client.commands.select { |command| command[:method] == 'Page.stopScreenRecording' }
    expect(stop_commands.length).to eq(1)
  end
end
