require 'spec_helper'
require 'base64'
require 'stringio'

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
FakeRecordingPage = Struct.new(:main_frame, :logger)

RSpec.describe Puppeteer::ScreenRecording do
  def build_recording(client, options = {})
    page = FakeRecordingPage.new(FakeRecordingFrame.new(client))
    described_class.new(page, options)
  end

  def base64_chunk(text, eof:)
    { 'data' => Base64.strict_encode64(text), 'base64Encoded' => true, 'eof' => eof }
  end

  it 'starts recording and reads all chunks on stop' do
    client = FakeRecordingSession.new
    client.read_chunks = [base64_chunk('chunk1', eof: false), base64_chunk('chunk2', eof: true)]

    recording = build_recording(client,
      audio: true, max_width: 1920, max_height: 1080, frame_rate: 60)
    recording.start

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
    recording.start

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
  end

  it 'uses the stream handle returned from startScreenRecording' do
    client = FakeRecordingSession.new
    client.start_response = { 'stream' => 'stream-start' }
    client.read_chunks = [base64_chunk('hello', eof: true)]

    recording = build_recording(client)
    recording.start
    recording.stop

    expect(recording.data).to eq('hello'.b)
    expect(client.commands).to include(method: 'IO.close', params: { handle: 'stream-start' })
  end

  it 'decodes non-base64 chunks' do
    client = FakeRecordingSession.new
    client.read_chunks = [{ 'data' => 'plain', 'base64Encoded' => false, 'eof' => true }]

    recording = build_recording(client)
    recording.start
    recording.stop

    expect(recording.data).to eq('plain'.b)
  end

  it 'raises when the stream handle is missing' do
    client = FakeRecordingSession.new
    client.start_response = {}

    recording = build_recording(client)
    recording.start
    expect { recording.stop }.to raise_error(Puppeteer::Error, 'Screen recording stream handle is missing.')
  end

  it 'stops on client disconnection and treats a second stop as no-op' do
    client = FakeRecordingSession.new

    recording = build_recording(client)
    recording.start

    client.emit_disconnect
    recording.stop

    stop_commands = client.commands.select { |command| command[:method] == 'Page.stopScreenRecording' }
    expect(stop_commands.length).to eq(1)
  end

  it 'closes piped destinations on stop' do
    client = FakeRecordingSession.new
    client.read_chunks = [base64_chunk('data', eof: true)]

    recording = build_recording(client)
    recording.start
    dest = StringIO.new.binmode
    recording.pipe(dest)
    recording.stop

    expect(dest).to be_closed
  end
end
