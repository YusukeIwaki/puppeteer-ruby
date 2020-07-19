require 'spec_helper'

RSpec.describe Puppeteer::Page do
  describe 'click button' do
    sinatra do
      get('/button') {
        <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Button test</title>
          </head>
          <body>
            <button onclick="clicked();">Click target</button>
            <script>
              window.result = 'Was not clicked';
              function clicked() {
                result = 'Clicked';
              }
            </script>
          </body>
        </html>
        HTML
      }
    end

    it {
      page.goto("http://127.0.0.1:4567/button")
      page.click('button')
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    }
  end

  describe 'click svg' do
    before {
      page.content = <<~SVG
      <svg height="100" width="100">
        <circle onclick="javascript:window.__CLICKED=42" cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
      </svg>
      SVG
    }

    it {
      page.click('circle')
      expect(page.evaluate('() => globalThis.__CLICKED')).to eq(42)
    }
  end

  # https://github.com/puppeteer/puppeteer/issues/4281
  describe 'click on a span with an inline element inside' do
    before {
      page.content = <<~HTML
      <style>
      span::before {
        content: 'q';
      }
      </style>
      <span onclick='javascript:window.CLICKED=42'></span>
      HTML
    }

    it {
      page.click('span')
      expect(page.evaluate('() => globalThis.CLICKED')).to eq(42)
    }
  end
end
