# Puppeteer in Ruby [UNDER HEAVY DEVELOPMENT]

A Ruby port of [puppeteer](https://pptr.dev/).

REMARK: This Gem is NOT production-ready!!

## Getting Started

Simple usage:

```ruby
require 'puppeteer'

Puppeteer.launch(headless: false, slow_mo: 50, args: ['--guest', '--window-size=1280,800']) do |browser|
  page = browser.pages.first || browser.new_page
  page.viewport = Puppeteer::Viewport.new(width: 1280, height: 800)
  page.goto("https://github.com/", wait_until: 'domcontentloaded')

  form = page.S("form.js-site-search-form")
  searchInput = form.S("input.header-search-input")
  searchInput.type_text("puppeteer")
  await_all(
    page.async_wait_for_navigation,
    searchInput.async_press("Enter"),
  )

  list = page.S("ul.repo-list")
  items = list.SS("div.f4")
  items.each do |item|
    title = item.Seval("a", "a => a.innerText")
    puts("==> #{title}")
  end
end
```

![puppeteer-ruby](https://user-images.githubusercontent.com/11763113/78505735-6e7f3000-77b0-11ea-9c82-9016828dd2a9.gif)


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/YusukeIwaki/puppeteer-ruby.
