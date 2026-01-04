[![Gem Version](https://badge.fury.io/rb/puppeteer-ruby.svg)](https://badge.fury.io/rb/puppeteer-ruby)

> [!IMPORTANT]
> The `main` branch is currently under **HEAVY DEVELOPMENT** for increased stability.
> If you need the latest stable release, please refer to the [ref-2025 tag](https://github.com/YusukeIwaki/puppeteer-ruby/tree/ref-2025).

# Puppeteer in Ruby

A Ruby port of [puppeteer](https://pptr.dev/).

![logo](puppeteer-ruby.png)

REMARK: This Gem covers just a part of Puppeteer APIs. See [API Coverage list](./docs/api_coverage.md) for detail. Feedbacks and feature requests are welcome :)

## Getting Started

### Installation

Add this line to your application's Gemfile:

```ruby
gem 'puppeteer-ruby'
```

And then execute:

    $ bundle install

### Capture a site

```ruby
require 'puppeteer-ruby'

Puppeteer.launch(headless: false) do |browser|
  page = browser.new_page
  page.goto("https://github.com/YusukeIwaki")
  page.screenshot(path: "YusukeIwaki.png")
end
```

NOTE: `require 'puppeteer-ruby'` is not necessary in Rails.

### Simple scraping

```ruby
require 'puppeteer-ruby'

Puppeteer.launch(headless: false, slow_mo: 50, args: ['--window-size=1280,800']) do |browser|
  page = browser.new_page
  page.viewport = Puppeteer::Viewport.new(width: 1280, height: 800)
  with_network_retry { page.goto("https://github.com/", wait_until: 'domcontentloaded') }

  page.wait_for_selector('[placeholder="Search or jump to..."]').click
  search_input = page.wait_for_selector('input[name="query-builder-test"]')
  search_input.click
  page.keyboard.type_text("puppeteer")

  page.wait_for_navigation do
    search_input.press("Enter")
  end

  list = page.wait_for_selector('[data-testid="results-list"]')
  items = list.query_selector_all(".search-title")
  items.each do |item|
    title = item.eval_on_selector("a", "a => a.innerText")
    puts("==> #{title}")
  end
end
```

### Evaluate JavaScript

```ruby
require 'puppeteer-ruby'

Puppeteer.launch do |browser|
  page = browser.new_page
  page.goto 'https://github.com/YusukeIwaki'

  # Get the "viewport" of the page, as reported by the page.
  dimensions = page.evaluate(<<~JAVASCRIPT)
  () => {
    return {
      width: document.documentElement.clientWidth,
      height: document.documentElement.clientHeight,
      deviceScaleFactor: window.devicePixelRatio
    };
  }
  JAVASCRIPT

  puts "dimensions: #{dimensions}"
  # => dimensions: {"width"=>800, "height"=>600, "deviceScaleFactor"=>1}
end
```

More usage examples can be found [here](https://github.com/YusukeIwaki/puppeteer-ruby-example)

## :whale: Running in Docker

Following packages are required.

- Google Chrome or Chromium
  - In Debian-based images, `google-chrome-stable`
  - In Alpine-based images, `chromium`

Also, CJK font will be required for Chinese, Japanese, Korean sites.

### References

- Puppeteer official README: https://github.com/puppeteer/puppeteer/blob/main/docs/troubleshooting.md#running-puppeteer-in-docker
- puppeteer-ruby example: https://github.com/YusukeIwaki/puppeteer-ruby-example/tree/master/docker_chromium

## :bulb: Collaboration with Selenium or Capybara

It is really remarkable that we can use puppeteer functions in existing Selenium or Capybara codes, with a few configuration in advance.

```ruby
require 'spec_helper'

RSpec.describe 'hotel.testplanisphere.dev', type: :feature do
  before {
    visit 'https://hotel.testplanisphere.dev/'

    # acquire Puppeteer::Browser instance, by connecting Chrome with DevTools Protocol.
    @browser = Puppeteer.connect(
                 browser_url: 'http://localhost:9222',
                 default_viewport: Puppeteer::Viewport.new(width: 1280, height: 800))
  }

  after {
    # release Puppeteer::Browser reesource.
    @browser.disconnect
  }

  it 'can be handled with puppeteer and assert with Capybara' do
    # automation with puppeteer
    puppeteer_page = @browser.pages.first
    puppeteer_page.wait_for_selector('li.nav-item')

    reservation_link = puppeteer_page.query_selector_all('li.nav-item')[1]

    puppeteer_page.wait_for_navigation do
      reservation_link.click
    end

    # expectation with Capybara DSL
    expect(page).to have_text('宿泊プラン一覧')
  end

  it 'can be handled with Capybara and assert with puppeteer' do
    # automation with Capybara
    page.all('li.nav-item')[1].click

    # expectation with puppeteer
    puppeteer_page = @browser.pages.first
    body_text = puppeteer_page.eval_on_selector('body', '(el) => el.textContent')
    expect(body_text).to include('宿泊プラン一覧')
  end
```

The detailed step of configuration can be found [here](https://github.com/YusukeIwaki/puppeteer-ruby-example/tree/master/_with_capybara-rspec).

## :bulb: Use Puppeteer methods simply without Capybara::DSL

We can also use puppeteer-ruby as it is without Capybara DSL. When you want to just test a Rails application simply with Puppeteer, refer this section.

Also, if you have trouble with handling flaky/unstable testcases in existing feature/system specs, consider replacing Capybara::DSL with raw puppeteer-ruby codes like `page.wait_for_selector(...)` or `page.wait_for_navigation { ... }`.

Capybara prepares test server even when Capybara DSL is not used.

Sample configuration is shown below. You can use it by putting the file at `spec/support/puppeteer_ruby.rb` or another location where RSpec loads on initialization.

```ruby
RSpec.configure do |config|
  require 'capybara'

  # This driver only requests Capybara to launch test server.
  # Remark that no Capybara::DSL is available with this driver.
  class CapybaraNullDriver < Capybara::Driver::Base
    def needs_server?
      true
    end
  end

  Capybara.register_driver(:null) { CapybaraNullDriver.new }

  config.around(driver: :null) do |example|
    Capybara.current_driver = :null

    # Rails server is launched here,
    # (at the first time of accessing Capybara.current_session.server)
    @base_url = Capybara.current_session.server.base_url

    require 'puppeteer'
    launch_options = {
      # Use launch options as you like.
      channel: :chrome,
      headless: false,
    }
    Puppeteer.launch(**launch_options) do |browser|
      @puppeteer_page = browser.new_page
      example.run
    end

    Capybara.reset_sessions!
    Capybara.use_default_driver
  end
end
```

Now, we can work with integration test using `Puppeteer::Page` in puppeteer-ruby.

```ruby
RSpec.describe 'Sample integration tests', driver: :null do
  let(:page) { @puppeteer_page }
  let(:base_url) { @base_url }

  it 'should work with Puppeteer' do
    # null driver only launches server, and Capybara::DSL is unavailable.
    expect { visit '/' }.to raise_error(/NotImplementedError/)

    page.goto("#{base_url}/")

    # Automation with Puppeteer
    h1_text = page.eval_on_selector('h1', '(el) => el.textContent')
    expect(h1_text).to eq('It works!')
  end
end
```

## API

https://yusukeiwaki.github.io/puppeteer-ruby-docs/

## Note on Firefox

This library supports **Chrome/Chromium only**. For Firefox automation, consider using [playwright-ruby-client](https://github.com/YusukeIwaki/playwright-ruby-client) or [puppeteer-bidi](https://github.com/YusukeIwaki/puppeteer-bidi).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/YusukeIwaki/puppeteer-ruby.
