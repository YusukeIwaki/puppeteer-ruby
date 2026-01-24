require 'spec_helper'

RSpec.describe 'Locator' do
  it 'should allow transient stable bounding box before viewport is ready' do
    with_test_state do |page:, **|
      page.default_timeout = 800
      page.viewport = Puppeteer::Viewport.new(width: 400, height: 200)
      page.content = <<~HTML
        <style>
          #container { height: 0; overflow: hidden; }
          button { width: 80px; height: 30px; }
        </style>
        <div id="container">
          <button onclick="window.clicked = true">Click</button>
        </div>
        <script>
          window.clicked = false;
          const button = document.querySelector('button');
          setTimeout(() => {
            let x = 0;
            const step = () => {
              x = (x + 1) % 100;
              button.style.transform = `translateX(${x}px)`;
              requestAnimationFrame(step);
            };
            requestAnimationFrame(step);
          }, 150);
          setTimeout(() => {
            document.querySelector('#container').style.height = '100px';
          }, 300);
        </script>
      HTML

      page.locator('button').click
      expect(page.evaluate('() => window.clicked')).to eq(true)
    end
  end
end
