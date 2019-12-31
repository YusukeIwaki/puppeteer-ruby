require 'puppeteer';

Puppeteer.launch(headless: false) do |browser|
  page = browser.pages.first || browser.new_page
  page.goto("https://github.com/YusukeIwaki")
  page.screenshot(path: "YusukeIwaki.png")
  page.close
end
