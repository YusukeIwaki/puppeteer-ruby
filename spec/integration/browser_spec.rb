require 'spec_helper'

RSpec.describe Puppeteer::Browser, puppeteer: :browser do
  describe 'version' do
    it 'should return version' do
      expect(browser.version).to include('Chrome')
    end
  end

  describe 'user_agent' do
    it 'should include WebKit' do
      expect(browser.user_agent).to include('WebKit')
    end
  end

  describe 'target' do
    it 'should return browser target' do
      expect(browser.target.type).to eq('browser')
    end
  end

  describe 'connected?' do
    it 'should return the browser connected state' do
      ws_endpoint = browser.ws_endpoint
      new_browser = Puppeteer.connect(browser_ws_endpoint: ws_endpoint)
      expect(new_browser).to be_connected
      new_browser.disconnect
      expect(new_browser).not_to be_connected
      expect(browser).to be_connected
    end
  end
end
