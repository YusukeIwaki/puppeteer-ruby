require 'spec_helper'

RSpec.describe Puppeteer::WaitTask do
  describe 'Page.waitFor' do
    sinatra do
      get('/') do
        <<~HTML
        <html>
        <head>
          <title>Top</title>
        </head>
        <body></body>
        </html>
        HTML
      end
      get('/grid.html') do
        <<~HTML
        <script>
        document.addEventListener('DOMContentLoaded', function() {
            function generatePalette(amount) {
                var result = [];
                var hueStep = 360 / amount;
                for (var i = 0; i < amount; ++i)
                    result.push('hsl(' + (hueStep * i) + ', 100%, 90%)');
                return result;
            }

            var palette = generatePalette(100);
            for (var i = 0; i < 200; ++i) {
                var box = document.createElement('div');
                box.classList.add('box');
                box.style.setProperty('background-color', palette[i % palette.length]);
                var x = i;
                do {
                    var digit = x % 10;
                    x = (x / 10)|0;
                    var img = document.createElement('img');
                    img.src = `./digits/${digit}.png`;
                    box.insertBefore(img, box.firstChild);
                } while (x);
                document.body.appendChild(box);
            }
        });
        </script>

        <style>

        body {
            margin: 0;
            padding: 0;
        }

        .box {
            font-family: arial;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            margin: 0;
            padding: 0;
            width: 50px;
            height: 50px;
            box-sizing: border-box;
            border: 1px solid darkgray;
        }

        ::-webkit-scrollbar {
            display: none;
        }
        </style>
        HTML
      end
    end

    it 'should wait for selector' do
      found = false
      wait_for = page.async_wait_for_selector('div').then { found = true }

      page.goto('http://127.0.0.1:4567/')
      expect(found).to eq(false)

      page.goto('http://127.0.0.1:4567/grid.html')
      await wait_for
      expect(found).to eq(true)
    end

    it 'should wait for an xpath' do
      found = false
      wait_for = page.async_wait_for_xpath('//div').then { found = true }

      page.goto('http://127.0.0.1:4567/')
      expect(found).to eq(false)

      page.goto('http://127.0.0.1:4567/grid.html')
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
