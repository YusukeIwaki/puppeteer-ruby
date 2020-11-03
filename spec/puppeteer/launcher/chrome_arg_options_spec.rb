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
  end
end
