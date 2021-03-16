# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe 'example' do
  it 'should take a screenshot' do
    skip if Puppeteer.env.ci? && !Puppeteer.env.windows?

    page.goto('https://github.com/YusukeIwaki')
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, 'YusukeIwaki.png')
      page.screenshot(path: path)
      expect(File.open(path).read.size).to be > 1000
    end
  end

  it 'should input text and grab DOM elements' do
    skip if Puppeteer.env.ci? && !Puppeteer.env.windows?

    page.viewport = Puppeteer::Viewport.new(width: 1280, height: 800)
    page.goto("https://github.com/", wait_until: 'domcontentloaded')

    form = page.query_selector("form.js-site-search-form")
    search_input = form.query_selector("input.header-search-input")
    search_input.click

    page.keyboard.type_text("puppeteer")
    await_all(
      page.async_wait_for_navigation,
      search_input.async_press("Enter"),
    )

    list = page.query_selector("ul.repo-list")
    items = list.query_selector_all("div.f4")
    items.each do |item|
      title = item.eval_on_selector("a", "a => a.innerText")
      puts("==> #{title}")
    end
  end

  it 'should evaluate expression' do
    expect(page.evaluate('2 + 3')).to eq(5)
  end

  it 'should evaluate function returning object' do
    expect(page.evaluate('() => { return { a: 3, b: 4 } }')).to eq({ 'a' => 3, 'b' => 4 })
  end
end
