require 'spec_helper'

RSpec.describe Puppeteer::Extension do
  let(:extension_id) { 'extension-id' }
  let(:target) do
    double(
      Puppeteer::Target,
      type: target_type,
      url: "chrome-extension://#{extension_id}/background.js",
    )
  end
  let(:browser) { double(Puppeteer::Browser, targets: [target]) }
  let(:extension) do
    described_class.new(
      id: extension_id,
      version: '1.0',
      name: 'Test extension',
      path: '/test-extension',
      enabled: true,
      browser: browser,
    )
  end

  describe '#workers' do
    let(:target_type) { 'service_worker' }

    it 'ignores target closed errors' do
      error = Puppeteer::TargetCloseError.new(
        method: 'Target.attachToTarget',
        error_message: 'Target closed',
      )
      allow(target).to receive(:worker).and_raise(error)

      expect(extension.workers).to eq([])
    end

    it 'ignores errors when the target no longer exists' do
      error = Puppeteer::Connection::ProtocolError.new(
        method: 'Target.attachToTarget',
        error_message: 'No target with given id found',
      )
      allow(target).to receive(:worker).and_raise(error)

      expect(extension.workers).to eq([])
    end

    it 're-raises unexpected errors' do
      allow(target).to receive(:worker).and_raise(Puppeteer::Error, 'boom')

      expect { extension.workers }.to raise_error(Puppeteer::Error, 'boom')
    end
  end

  describe '#pages' do
    let(:target_type) { 'page' }

    it 're-raises unexpected errors' do
      allow(target).to receive(:as_page).and_raise(Puppeteer::Error, 'boom')

      expect { extension.pages }.to raise_error(Puppeteer::Error, 'boom')
    end
  end
end
