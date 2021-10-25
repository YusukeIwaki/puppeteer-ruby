require 'spec_helper'

RSpec.describe Puppeteer::Launcher::LaunchOptions do
  describe 'default value' do
    subject { Puppeteer::Launcher::LaunchOptions.new({}) }

    it 'channel: nil' do
      expect(subject.channel).to eq(nil)
    end

    it 'executable_path: nil' do
      expect(subject.executable_path).to eq(nil)
    end

    it 'ignore_default_args: false' do
      expect(subject.ignore_default_args).to eq(false)
    end

    it 'handle_SIGINT: true' do
      expect(subject.handle_SIGINT?).to eq(true)
    end

    it 'handle_SIGTERM: true' do
      expect(subject.handle_SIGTERM?).to eq(true)
    end

    it 'handle_SIGHUP: true' do
      expect(subject.handle_SIGHUP?).to eq(true)
    end

    it 'timeout: 30000' do
      expect(subject.timeout).to eq(30000)
    end

    it 'dumpio: false' do
      expect(subject.dumpio?).to eq(false)
    end

    it 'env: ENV' do
      expect(subject.env).to eq(ENV)
    end

    it 'pipe: false' do
      expect(subject.pipe?).to eq(false)
    end
  end

  describe "disabled signal handlers" do
    it 'handle_SIGINT can be disabled' do
      opts = Puppeteer::Launcher::LaunchOptions.new({handle_SIGINT: false})
      expect(opts.handle_SIGINT?).to eq(false)
    end

    it 'handle_SIGTERM can be disabled' do
      opts = Puppeteer::Launcher::LaunchOptions.new({handle_SIGTERM: false})
      expect(opts.handle_SIGTERM?).to eq(false)
    end

    it 'handle_SIGHUP can be disabled' do
      opts = Puppeteer::Launcher::LaunchOptions.new({handle_SIGHUP: false})
      expect(opts.handle_SIGHUP?).to eq(false)
    end
  end
end
