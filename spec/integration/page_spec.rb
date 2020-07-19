require 'spec_helper'

RSpec.describe Puppeteer::Page do
  describe 'goto' do
    sinatra do
      get('/') {
        <<~HTML
        <html>
          <head>
            <title>Hello World</title>
          </head>
          <body>My Sinatra</body>
        </html>
        HTML
      }
    end

    it "can browser html page" do
      page.goto("http://127.0.0.1:4567/")
      expect(page.title).to include("Hello World")
      expect(page.evaluate('() => document.body.innerText')).to eq("My Sinatra")
    end
  end
end
