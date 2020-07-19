require 'spec_helper'

RSpec.describe Puppeteer::Page do
  describe 'goto' do
    it 'can fetch title soon after goto.' do
      page.goto("https://github.com/YusukeIwaki/puppeteer-ruby")
      expect(page.title).to include("YusukeIwaki/puppeteer-ruby")
    end
  end
end
