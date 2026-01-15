require 'spec_helper'

RSpec.describe 'Page (white-box / Ruby-specific)' do
  it 'can browser html page', sinatra: true do
    with_test_state do |page:, server:, **|
      sinatra = TestServerSinatraAdapter.new(server)
      sinatra.get('/hello') do
        <<~HTML
        <html>
          <head>
            <title>Hello World</title>
          </head>
          <body>My Sinatra</body>
        </html>
        HTML
      end

      page.goto("#{server.prefix}/hello")
      expect(page.title).to include('Hello World')
      expect(page.evaluate('() => document.body.innerText')).to eq('My Sinatra')
    end
  end

  describe 'Page.waitForRequest (nested waits)' do
    it 'should work even if nested', sinatra: true do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        promises = [
          page.async_wait_for_request(url: "#{server.prefix}/digits/2.png"),
          page.async_wait_for_request(url: "#{server.prefix}/digits/3.png"),
        ]
        page.evaluate(<<~JAVASCRIPT)
        () => {
          fetch('/digits/1.png');
          fetch('/digits/2.png');
          fetch('/digits/3.png');
        }
        JAVASCRIPT
        requests = await_promises(*promises)
        expect(requests.map(&:url)).to contain_exactly(
          "#{server.prefix}/digits/2.png",
          "#{server.prefix}/digits/3.png",
        )
      end
    end
  end

  describe 'printing to PDF' do
    it 'can print to PDF without file', sinatra: true do
      skip('Printing to pdf is currently only supported in headless') unless headless?

      with_test_state do |page:, server:, **|
        sinatra = TestServerSinatraAdapter.new(server)
        sinatra.get('/') { '<h1>It Works!</h1>' }
        page.goto("#{server.prefix}/")

        data = page.pdf
        expect(data.size).to be > 0
      end
    end
  end
end
