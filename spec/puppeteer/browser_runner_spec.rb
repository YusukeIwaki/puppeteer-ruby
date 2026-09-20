require 'spec_helper'
require 'fileutils'
require 'tmpdir'

class FakeExitEmitter
  def initialize
    @listeners = []
  end

  def listener_count
    @listeners.size
  end

  def once(_event, listener = nil, &block)
    @listeners << (listener || block)
  end

  def off(_event, listener)
    @listeners.delete(listener)
  end

  def emit(_event)
    @listeners.dup.each(&:call)
    @listeners.clear
  end
end

RSpec.describe Puppeteer::BrowserRunner::ProcessExitCleanup do
  let(:logger) { ->(_prefix) { } }

  def make_temp_dir
    directory = Dir.mktmpdir('puppeteer-process-exit-cleanup-')
    File.binwrite(File.join(directory, 'profile'), 'profile')
    directory
  end

  it 'removes a temporary profile synchronously on process exit' do
    user_data_dir = make_temp_dir
    emitter = FakeExitEmitter.new

    described_class.new(emitter).register(user_data_dir, logger)
    emitter.emit('exit')

    expect(File.exist?(user_data_dir)).to eq(false)
  end

  it 'can unregister cleanup after the browser process exits' do
    user_data_dir = make_temp_dir
    emitter = FakeExitEmitter.new

    unregister = described_class.new(emitter).register(user_data_dir, logger)
    unregister.call
    emitter.emit('exit')

    expect(File.exist?(user_data_dir)).to eq(true)
    FileUtils.rm_rf(user_data_dir)
  end

  it 'uses one process-exit listener for multiple temporary profiles' do
    first_dir = make_temp_dir
    second_dir = make_temp_dir
    emitter = FakeExitEmitter.new

    registry = described_class.new(emitter)
    registry.register(first_dir, logger)
    registry.register(second_dir, logger)
    expect(emitter.listener_count).to eq(1)

    emitter.emit('exit')

    expect(File.exist?(first_dir)).to eq(false)
    expect(File.exist?(second_dir)).to eq(false)
  end
end
