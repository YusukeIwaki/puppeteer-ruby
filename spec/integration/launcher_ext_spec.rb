require 'spec_helper'

# Ruby-specific coverage for the experimental custom logger (upstream
# puppeteer/puppeteer#15324): protocol traffic reaches user-supplied sinks.
RSpec.describe 'Launcher custom logger', sinatra: true do
  include_context 'with test state'
  it 'should support a custom logger for protocol traffic', sinatra: true do
    sends = []
    receives = []
    mutex = Mutex.new
    logger = lambda do |prefix|
      # Disabled channels return nil; logging must not crash for them.
      case prefix
      when Puppeteer::DebugPrefixes::CDP_SEND
        lambda do |*args|
          mutex.synchronize { sends << args }
        end
      when Puppeteer::DebugPrefixes::CDP_RECEIVE
        lambda do |*args|
          mutex.synchronize { receives << args }
        end
      end
    end

    options = default_launch_options.merge(logger: logger)
    Puppeteer.launch(**options) do |browser|
      page = browser.new_page
      page.goto(server_empty_page)
      expect(page.evaluate('() => 1 + 1')).to eq(2)
    end

    expect(sends).not_to be_empty
    expect(sends.flatten.join).to include('Page.navigate')
    # Like upstream, protocol messages are logged as JSON strings.
    expect(receives).not_to be_empty
    expect(receives.flatten.map(&:class).uniq).to eq([String])
    expect(sends.flatten.map(&:class).uniq).to eq([String])
  end
end
