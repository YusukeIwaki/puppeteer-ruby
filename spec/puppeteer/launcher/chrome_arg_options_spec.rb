require 'spec_helper'

RSpec.describe Puppeteer::Launcher::ChromeArgOptions do
  describe 'default value' do
    subject { Puppeteer::Launcher::ChromeArgOptions.new({}) }

    it 'headless:true' do
      expect(subject.headless?).to eq(true)
    end

    it 'devtools:false' do
      expect(subject.devtools?).to eq(false)
    end

    it 'enable_extensions:false' do
      expect(subject.enable_extensions).to eq(false)
    end
  end

  describe 'enable_extensions option' do
    it 'accepts true' do
      options = Puppeteer::Launcher::ChromeArgOptions.new(enable_extensions: true)
      expect(options.enable_extensions).to eq(true)
    end

    it 'accepts extension path list' do
      options = Puppeteer::Launcher::ChromeArgOptions.new(enable_extensions: ['tmp/ext'])
      expect(options.enable_extensions).to eq(['tmp/ext'])
    end
  end
end
