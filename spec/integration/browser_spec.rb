require 'spec_helper'

RSpec.describe Puppeteer::Browser, puppeteer: :browser do
  describe 'version' do
    it 'should indicate we are in headless' do
      expect(@browser.version).to start_with('Headless')
    end
  end

  describe 'user_agent' do
    it 'should include WebKit' do
      expect(@browser.user_agent).to include('WebKit')
    end
  end

  describe 'target' do
    it 'should return browser target' do
      expect(@browser.target.type).to eq('browser')
    end
  end
end
