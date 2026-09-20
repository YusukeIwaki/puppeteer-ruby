require 'spec_helper'
require 'async'
require 'base64'

# Fakes mirroring upstream's MockCDPSession/MockPage in
# cdp/ScreenRecording.test.ts, shared by the ported spec and the Ruby
# extension spec.
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

module RecordingSpecHelpers
  def build_recording(client, options = {})
    MockRecordPage.new(client).record(**options)
  end

  def base64_chunk(text, eof:)
    { 'data' => Base64.strict_encode64(text), 'base64Encoded' => true, 'eof' => eof }
  end
end
