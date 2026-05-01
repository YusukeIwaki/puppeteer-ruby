RSpec.describe Puppeteer do
  it 'has a version number' do
    expect(Puppeteer::VERSION).not_to be nil
  end

  describe '.connect' do
    it 'accepts channel and preserves nil default_viewport' do
      browser = instance_double(Puppeteer::Browser)
      connector = instance_double(Puppeteer::BrowserConnector, connect_to_browser: browser)

      expect(Puppeteer::BrowserConnector).to receive(:new).with(
        hash_including(
          channel: 'chrome',
          default_viewport: nil,
        ),
      ).and_return(connector)

      Async do
        expect(Puppeteer.connect(channel: :chrome, default_viewport: nil)).to eq(browser)
      end.wait
    end
  end
end
