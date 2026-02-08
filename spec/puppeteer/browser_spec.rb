require 'spec_helper'

RSpec.describe Puppeteer::Browser do
  describe '#set_permission' do
    it 'delegates to the default browser context' do
      browser = described_class.allocate
      default_context = instance_double(Puppeteer::BrowserContext)
      browser.instance_variable_set(:@default_context, default_context)

      expect(default_context).to receive(:set_permission).with(
        'https://example.test',
        { permission: { name: 'geolocation' }, state: 'denied' },
      )
      browser.set_permission(
        'https://example.test',
        { permission: { name: 'geolocation' }, state: 'denied' },
      )
    end
  end
end
