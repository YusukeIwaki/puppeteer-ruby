require 'spec_helper'

RSpec.describe Puppeteer::Browser do
  describe '#version and #user_agent' do
    it 'caches Browser.getVersion' do
      connection = double(Puppeteer::Connection)
      expect(connection).to receive(:send_message).with('Browser.getVersion').once.and_return({
        'product' => 'Chrome/150.0.0.0',
        'userAgent' => 'test user agent',
      })
      browser = described_class.allocate
      browser.instance_variable_set(:@connection, connection)
      browser.instance_variable_set(:@version_promise, nil)

      expect(browser.version).to eq('Chrome/150.0.0.0')
      expect(browser.user_agent).to eq('test user agent')
    end
  end

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

  describe '#launch_pwa' do
    it 'should apply the timeout while waiting for the page target' do
      connection = double(Puppeteer::Connection)
      browser = described_class.allocate
      browser.instance_variable_set(:@connection, connection)
      browser.instance_variable_set(:@has_network_restrictions, false)
      page = double(Puppeteer::Page)
      target = double(Puppeteer::Target, page: page)

      expect(connection).to receive(:send_message).with(
        'PWA.launch',
        { manifestId: 'https://example.com/' },
      ).and_return('targetId' => 'tab')
      expect(browser).to receive(:wait_for_target).with(
        predicate: kind_of(Proc),
        timeout: 123,
      ).and_return(target)

      result = browser.launch_pwa(
        manifest_id: 'https://example.com/',
        timeout: 123,
      )

      expect(result).to eq(page)
    end
  end
end
