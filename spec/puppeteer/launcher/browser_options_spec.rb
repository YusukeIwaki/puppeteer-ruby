require 'spec_helper'

RSpec.describe Puppeteer::Launcher::BrowserOptions do
  it 'issues_enabled defaults to true' do
    options = described_class.new({})
    expect(options.issues_enabled).to eq(true)
  end

  it 'accepts block_list array' do
    options = described_class.new(block_list: ['*://*:*/empty.html'])
    expect(options.block_list).to eq(['*://*:*/empty.html'])
  end

  it 'rejects non-array block_list' do
    expect do
      described_class.new(block_list: '*://*:*/empty.html')
    end.to raise_error(ArgumentError, 'block_list must be an Array of URL patterns')
  end
end
