require 'spec_helper'
require 'stringio'
require_relative '../support/fake_screen_recording'

# Ported from upstream cdp/ScreenRecording.test.ts (8 cases, same order).
# Ruby adaptations: Page#record takes snake_case options, chunks are read
# through #each_chunk, and IO objects take the WritableDestination path.
RSpec.describe Puppeteer::ScreenRecording do
  include RecordingSpecHelpers

  it 'should start screen recording and read all chunks on stop' do
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

    expect(dest.string).to eq('chunk1chunk2'.b)
    expect(client.commands).to include(method: 'Page.stopScreenRecording', params: {})
    expect(client.commands).to include(method: 'IO.close', params: { handle: 'stream-1' })
  end

  it 'should support fps as alias for frameRate' do
    client = FakeRecordingSession.new

    recording = build_recording(client, fps: 24)

    expect(client.commands[0]).to eq(
      method: 'Page.startScreenRecording',
      params: { frameRate: 24 },
    )
    recording.stop
  end

  it 'should validate options' do
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

  it 'should support stream handle returned from startScreenRecording' do
    client = FakeRecordingSession.new
    client.start_response = { 'stream' => 'stream-start' }
    client.read_chunks = [base64_chunk('hello', eof: true)]

    recording = build_recording(client)

    dest = StringIO.new.binmode
    recording.pipe(dest)
    recording.stop

    expect(dest.string).to eq('hello'.b)
    expect(client.commands).to include(method: 'IO.close', params: { handle: 'stream-start' })
  end

  it 'should support async iteration' do
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

  it 'should support piping to a writable stream' do
    # Upstream pipes to a web WritableStream; Ruby IO objects take the
    # WritableDestination path, so exercise a real IO stream here.
    client = FakeRecordingSession.new
    client.start_response = { 'stream' => 'stream-web' }
    client.read_chunks = [base64_chunk('web-stream-data', eof: true)]

    recording = build_recording(client)

    reader, writer = IO.pipe
    writer.binmode
    recording.pipe(writer)
    recording.stop

    expect(reader.read).to eq('web-stream-data'.b)
  ensure
    writer.close if writer && !writer.closed?
    reader.close if reader && !reader.closed?
  end

  it 'should stop on client disconnection' do
    client = FakeRecordingSession.new

    recording = build_recording(client)

    client.emit_disconnect
    # Calling stop again should be a no-op
    recording.stop

    stop_commands = client.commands.select { |command| command[:method] == 'Page.stopScreenRecording' }
    expect(stop_commands.length).to eq(1)
  end

  it 'should stop the recording on close like async disposal' do
    client = FakeRecordingSession.new

    recording = build_recording(client)
    recording.close

    stop_commands = client.commands.select { |command| command[:method] == 'Page.stopScreenRecording' }
    expect(stop_commands.length).to eq(1)
  end
end
