# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe 'example' do
  it 'should take a screenshot' do
    skip if Puppeteer.env.ci? && !Puppeteer.env.windows?

    page.goto('https://github.com/YusukeIwaki')
    tmpdir = Dir.mktmpdir
    begin
      path = File.join(tmpdir, 'YusukeIwaki.png')
      page.screenshot(path: path)
      expect(File.open(path, 'rb').read.size).to be > 1000
    ensure
      FileUtils.remove_entry(tmpdir, true)
    end
  end

  it 'should print PDF with options' do
    skip if Puppeteer.env.ci? && !Puppeteer.env.windows?

    page.viewport = Puppeteer::Viewport.new(width: 1200, height: 800, device_scale_factor: 2)
    page.goto("https://github.com/YusukeIwaki")
    page.wait_for_selector(".js-yearly-contributions")
    overlay = page.query_selector('.js-yearly-contributions')

    js = <<-JAVASCRIPT
    graph => {
      const width = getComputedStyle(graph).width;
      graph = graph.cloneNode(true);
      graph.style.width = width;
      document.body.innerHTML = `
        <div style="display:flex;justify-content:center;align-items:center;height:100vh;">;
          ${graph.outerHTML}
        </div>
      `;
    }
    JAVASCRIPT
    page.evaluate(js, overlay)
    page.pdf(
      path: '5.element-to-pdf.github.pdf',
      print_background: true,
      format: "letter",
      margin: { top: "1cm", left: "2cm", right: "3cm", bottom: "4cm" },
      omit_background: true,
    )
  end

  it 'should input text and grab DOM elements' do
    skip if Puppeteer.env.ci? && !Puppeteer.env.windows?

    page.viewport = Puppeteer::Viewport.new(width: 1280, height: 800)
    page.goto("https://github.com/", wait_until: 'domcontentloaded')

    form = page.query_selector("form.js-site-search-form")
    search_input = form.query_selector("input.header-search-input")
    search_input.click
    page.keyboard.type_text("puppeteer")

    page.wait_for_navigation do
      search_input.press("Enter")
    end

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
