require 'spec_helper'

RSpec.describe Puppeteer::NetworkManager do
  it 'should reset the accept-language override for every client' do
    primary_client = double(Puppeteer::CDPSession).as_null_object
    secondary_client = double(Puppeteer::CDPSession).as_null_object
    commands_by_client = Hash.new { |hash, key| hash[key] = [] }
    [primary_client, secondary_client].each do |client|
      allow(client).to receive(:send_message) do |method, params = nil|
        commands_by_client[client] << [method, params]
      end
    end

    browser = double(Puppeteer::Browser, user_agent: 'browser-user-agent')
    page = double(Puppeteer::Page, browser: browser)
    frame_manager = double(Puppeteer::FrameManager, page: page).as_null_object
    manager = described_class.new(primary_client, false, frame_manager)
    manager.add_client(secondary_client)

    manager.init
    manager.set_accept_language('fr-FR')
    manager.set_accept_language(nil)

    commands_by_client.each_value do |commands|
      user_agent_commands = commands.select do |method, _|
        method == 'Network.setUserAgentOverride'
      end
      expect(user_agent_commands).to eq([
        [
          'Network.setUserAgentOverride',
          { userAgent: 'browser-user-agent', acceptLanguage: 'fr-FR' },
        ],
        [
          'Network.setUserAgentOverride',
          { userAgent: 'browser-user-agent' },
        ],
      ])
    end
  end
end
