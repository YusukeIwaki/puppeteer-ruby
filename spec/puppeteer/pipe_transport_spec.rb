require 'spec_helper'
require 'socket'

RSpec.describe Puppeteer::PipeTransport do
  let(:write_pipe_pair) { UNIXSocket.pair }
  let(:read_pipe_pair) { UNIXSocket.pair }
  let(:browser_pipe_read) { write_pipe_pair[0] }
  let(:pipe_write) { write_pipe_pair[1] }
  let(:browser_pipe_write) { read_pipe_pair[0] }
  let(:pipe_read) { read_pipe_pair[1] }
  let(:transport) { described_class.new(pipe_write, pipe_read) }

  around do |example|
    Sync do
      transport
      example.run
    ensure
      transport.close
      [browser_pipe_read, browser_pipe_write].each do |pipe|
        pipe.close unless pipe.closed?
      end
    end
  end

  def wait_for_next_message
    promise = Async::Promise.new
    transport.on_message do |message|
      promise.resolve(message) unless promise.resolved?
    end
    promise
  end

  def wait_for_number_of_messages(count)
    messages = []
    promise = Async::Promise.new
    transport.on_message do |message|
      messages << message
      promise.resolve(messages) if messages.length == count
    end
    promise
  end

  it 'should dispatch messages in order handling microtasks for each message first' do
    log = []
    result = Async::Promise.new
    transport.on_message do |message|
      log << "message received #{message}"
      log << "microtask1 #{message}"
      log << "microtask2 #{message}"
      result.resolve(nil) if log.length == 6
    end
    browser_pipe_write.write("m1\0")
    browser_pipe_write.write("m2\0")
    result.wait

    expect(log).to eq([
      'message received m1',
      'microtask1 m1',
      'microtask2 m1',
      'message received m2',
      'microtask1 m2',
      'microtask2 m2',
    ])
  end

  describe 'message handling' do
    it 'should work with message with ending' do
      message = wait_for_next_message
      browser_pipe_write.write("m1\0")
      expect(message.wait).to eq('m1')

      message = wait_for_next_message
      browser_pipe_write.write("m2\0")
      expect(message.wait).to eq('m2')
    end

    it 'should work for messages ending in multiple lines' do
      message = wait_for_next_message
      browser_pipe_write.write('Hello wor')
      browser_pipe_write.write("ld!\0")

      expect(message.wait).to eq('Hello world!')
    end

    it 'should work with messages continuing from previous one' do
      message = wait_for_next_message
      browser_pipe_write.write('Hello wor')
      browser_pipe_write.write("ld!\0I started in ")
      expect(message.wait).to eq('Hello world!')

      message = wait_for_next_message
      browser_pipe_write.write("the previous message\0")
      expect(message.wait).to eq('I started in the previous message')
    end

    it 'should work with multiple messages in a single line' do
      messages = wait_for_number_of_messages(3)
      browser_pipe_write.write("First\0Second\0Third\0")

      expect(messages.wait).to eq(['First', 'Second', 'Third'])
    end
  end
end
