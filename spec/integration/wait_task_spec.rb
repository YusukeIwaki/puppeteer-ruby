require 'spec_helper'

RSpec.describe Puppeteer::WaitTask do
  describe 'Page.waitFor', sinatra: true do
    it 'should wait for selector' do
      found = false
      wait_for = page.async_wait_for_selector('div').then { found = true }

      page.goto(server_empty_page)
      expect(found).to eq(false)

      page.goto("#{server_prefix}/grid.html")
      await wait_for
      expect(found).to eq(true)
    end

    it 'should wait for an xpath' do
      found = false
      wait_for = page.async_wait_for_xpath('//div').then { found = true }

      page.goto(server_empty_page)
      expect(found).to eq(false)

      page.goto("#{server_prefix}/grid.html")
      await wait_for
      expect(found).to eq(true)
    end
  end

  it 'should timeout' do
    start_time = Time.now
    page.wait_for_timeout(42)
    end_time = Time.now
    expect(end_time - start_time).to be >= 0.021
  end

  it 'should work with multiline body' do
    result = page.wait_for_function(<<~JAVASCRIPT)

    () => true

    JAVASCRIPT
    expect(result.json_value).to eq(true)
  end

  it 'should wait for predicate' do
    Timeout.timeout(1) do # assert not timeout.
      await_all(
        page.async_wait_for_function('() => window.innerWidth < 100'),
        future { page.viewport = Puppeteer::Viewport.new(width: 10, height: 10) },
      )
    end
  end

  it 'should wait for predicate with arguments' do
    Timeout.timeout(1) do # assert not timeout.
      page.wait_for_function('(arg1, arg2) => arg1 !== arg2', args: [1, 2])
    end
  end
end
