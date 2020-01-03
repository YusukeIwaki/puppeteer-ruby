# Puppeteer in Ruby [UNDER HEAVY DEVELOPMENT]

A Ruby port of [puppeteer](https://pptr.dev/).

## Getting Started

The simplest usage is below:

```ruby
require('puppeteer');

Puppeteer.launch(headless: false) do |browser|
  page = browser.pages.first || browser.new_page
  page.goto("https://github.com/YusukeIwaki")
  page.screenshot(path: "YusukeIwaki.png")
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/YusukeIwaki/puppeteer-ruby.
