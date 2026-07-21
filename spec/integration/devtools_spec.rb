require 'spec_helper'

RSpec.describe 'DevTools' do
  it 'should support opening DevTools on a page' do
    with_browser(devtools: false) do |browser|
      page = browser.new_page
      page.goto('about:blank')
      devtools_page = page.open_dev_tools
      handle = devtools_page.wait_for_function(
        '() => Boolean(window.DevToolsAPI)',
        timeout: 5000,
      )
      expect(handle.json_value).to eq(true)
      handle.dispose
    end
  end

  it 'should return same object when calling openDevTools twice' do
    with_browser(devtools: false) do |browser|
      page = browser.new_page
      page.goto('about:blank')
      devtools_page = page.open_dev_tools
      devtools_page2 = page.open_dev_tools
      expect(devtools_page2).to eq(devtools_page)
    end
  end

  describe 'hasDevTools' do
    it 'should report correctly after DevTools is opened' do
      with_browser(devtools: false) do |browser|
        page = browser.new_page
        page.goto('about:blank')
        expect(page.has_dev_tools).to eq(false)
        page.open_dev_tools
        expect(page.has_dev_tools).to eq(true)
      end
    end

    it 'should report when DevTools is attached by default' do
      with_browser(devtools: true) do |browser|
        page = browser.new_page
        page.goto('about:blank')
        expect(page.has_dev_tools).to eq(true)
      end
    end

    it 'should report when DevTools has been attached to a page with devtools:false' do
      with_browser(devtools: false) do |browser|
        page = browser.new_page
        page.goto('about:blank')
        page.open_dev_tools
        expect(page.has_dev_tools).to eq(true)
      end
    end
  end
end
