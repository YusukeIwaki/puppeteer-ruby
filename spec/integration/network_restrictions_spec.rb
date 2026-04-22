require 'spec_helper'

RSpec.describe 'Network Restrictions' do
  it 'should block page.goto when destination is in the blocklist', sinatra: true do
    with_browser(block_list: ['*://*:*/empty.html']) do |browser|
      with_test_state(browser: browser) do |page:, server:, **|
        allowed_url = "#{server.prefix}/title.html"
        blocked_url = "#{server.prefix}/empty.html"

        page.goto(allowed_url)
        expect { page.goto(blocked_url) }.to raise_error do |error|
          expect(
            error.message.include?('net::ERR_INTERNET_DISCONNECTED') ||
            error.message.include?('net::ERR_BLOCKED_BY_CLIENT'),
          ).to eq(true)
        end
      end
    end
  end

  it 'should detach from blocked targets when connecting to running browser', sinatra: true do
    with_test_state do |browser:, page:, server:, **|
      blocked_url = "#{server.prefix}/empty.html"
      page.goto(blocked_url)

      connected_browser = Puppeteer.connect(
        browser_ws_endpoint: browser.ws_endpoint,
        block_list: ['*://*:*/empty.html'],
      )
      begin
        blocked_target = connected_browser.targets.find { |target| target.url == blocked_url }
        expect(blocked_target).to be_nil
      ensure
        connected_browser.disconnect
      end
    end
  end
end
