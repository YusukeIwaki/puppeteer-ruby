require 'spec_helper'

RSpec.describe 'Coverage specs' do
  include_context 'with test state'
  describe 'JSCoverage' do
    it 'should work', sinatra: true do
      page.coverage.start_js_coverage
      page.goto("#{server_prefix}/jscoverage/simple.html", wait_until: 'networkidle0')
      coverage = page.coverage.stop_js_coverage
      expect(coverage.size).to eq(1)
      expect(coverage.first.url).to include('/jscoverage/simple.html')
      expect(coverage.first.ranges).to eq([
        { start: 0, end: 17 },
        { start: 35, end: 61 },
      ])
    end

    it 'should work with block', sinatra: true do
      coverage = page.coverage.js_coverage do
        page.goto("#{server_prefix}/jscoverage/simple.html", wait_until: 'networkidle0')
      end
      expect(coverage.size).to eq(1)
      expect(coverage.first.url).to include('/jscoverage/simple.html')
      expect(coverage.first.ranges).to eq([
        { start: 0, end: 17 },
        { start: 35, end: 61 },
      ])
    end

    it 'should report sourceURLs', sinatra: true do
      coverage = page.coverage.js_coverage do
        page.goto("#{server_prefix}/jscoverage/sourceurl.html")
      end

      expect(coverage.size).to eq(1)
      expect(coverage.first.url).to eq('nicename.js')
    end

    it 'should ignore eval() scripts by default', sinatra: true do
      coverage = page.coverage.js_coverage do
        page.goto("#{server_prefix}/jscoverage/eval.html")
      end

      expect(coverage.size).to eq(1)
    end

    it "shouldn't ignore eval() scripts if reportAnonymousScripts is true", sinatra: true do
      coverage = page.coverage.js_coverage(report_anonymous_scripts: true) do
        page.goto("#{server_prefix}/jscoverage/eval.html")
      end

      expect(coverage.size).to eq(2)
      found = coverage.select { |entry| entry.url.start_with?('debugger://') }
      expect(found).not_to be_empty
    end

    it 'should ignore pptr internal scripts if reportAnonymousScripts is true', sinatra: true do
      coverage = page.coverage.js_coverage(report_anonymous_scripts: true) do
        page.goto(server_empty_page)
        page.evaluate('console.log("foo")')
        page.evaluate("() => console.log('bar')")
      end
      expect(coverage).to be_empty
    end

    it 'should report multiple scripts', sinatra: true do
      coverage = page.coverage.js_coverage do
        page.goto("#{server_prefix}/jscoverage/multiple.html")
      end
      expect(coverage.size).to eq(2)
      expect(coverage.map(&:url)).to contain_exactly(
        include('/jscoverage/script1.js'),
        include('/jscoverage/script2.js'),
      )
    end

    it 'should report right ranges', sinatra: true do
      coverage = page.coverage.js_coverage do
        page.goto("#{server_prefix}/jscoverage/ranges.html")
      end
      expect(coverage.size).to eq(1)
      entry = coverage.first
      expect(entry.ranges.size).to eq(2)
      range = entry.ranges[0]
      expect(entry.text[range[:start]...range[:end]]).to eq("\n")

      range = entry.ranges[1]
      expect(entry.text[range[:start]...range[:end]]).to eq("console.log('used!');if(true===false)")
    end

    it 'should report right ranges for "per function" scope', sinatra: true do
      coverage = page.coverage.js_coverage(use_block_coverage: false) do
        page.goto("#{server_prefix}/jscoverage/ranges.html")
      end
      expect(coverage.size).to eq(1)
      entry = coverage.first
      expect(entry.ranges.size).to eq(2)
      range = entry.ranges[0]
      expect(entry.text[range[:start]...range[:end]]).to eq("\n")

      range = entry.ranges[1]
      expect(entry.text[range[:start]...range[:end]]).to eq("console.log('used!');if(true===false)console.log('unused!');")
    end

    it 'should report scripts that have no coverage', sinatra: true do
      coverage = page.coverage.js_coverage do
        page.goto("#{server_prefix}/jscoverage/unused.html")
      end
      expect(coverage.size).to eq(1)
      entry = coverage.first
      expect(entry.url).to include('unused.html')
      expect(entry.ranges).to be_empty
    end

    it 'should work with conditionals', sinatra: true do
      coverage = page.coverage.js_coverage do
        page.goto("#{server_prefix}/jscoverage/involved.html")
      end
      expected_coverage = JSON.parse(File.read('spec/integration/golden-chromium/jscoverage-involved.txt'))
      expect(coverage.size).to eq(expected_coverage.size)
      aggregate_failures do
        coverage.each_with_index do |entry, i|
          expected_entry = expected_coverage[i]
          expect(entry.url).to eq(expected_entry['url'].gsub('http://localhost:<PORT>', server_prefix))
          expect(entry.text).to eq(expected_entry['text'])
          expect(entry.ranges).to eq(expected_entry['ranges'].map { |e| { start: e['start'], end: e['end'] } })
        end
      end
    end

    describe 'reset_on_navigation', sinatra: true do
      it 'should report scripts across navigations when disabled' do
        coverage = page.coverage.js_coverage(reset_on_navigation: false) do
          page.goto("#{server_prefix}/jscoverage/multiple.html")
          page.goto(server_empty_page)
        end
        expect(coverage.size).to eq(2)
      end

      it 'should NOT report scripts across navigations when enabled' do
        coverage = page.coverage.js_coverage do # Enabled by default
          page.goto("#{server_prefix}/jscoverage/multiple.html")
          page.goto(server_empty_page)
        end
        expect(coverage).to be_empty
      end
    end

    describe 'includeRawScriptCoverage', sinatra: true do
      it 'should not include rawScriptCoverage field when disabled' do
        coverage = page.coverage.js_coverage do
          page.goto("#{server_prefix}/jscoverage/simple.html", wait_until: 'networkidle0')
        end
        expect(coverage.size).to eq(1)
        expect(coverage.first).not_to respond_to(:raw_script_coverage)
      end

      it 'should include rawScriptCoverage field when enabled' do
        coverage = page.coverage.js_coverage(include_raw_script_coverage: true) do
          page.goto("#{server_prefix}/jscoverage/simple.html", wait_until: 'networkidle0')
        end
        expect(coverage.size).to eq(1)
        expect(coverage.first).to respond_to(:raw_script_coverage)
        expect(coverage.first.raw_script_coverage).to be_a(Hash)
      end
    end

    # // @see https://crbug.com/990945
    it 'should not hang when there is a debugger statement', sinatra: true, pending: true do
      Timeout.timeout(5) do
        page.coverage.js_coverage do
          page.goto(server_empty_page)
          page.evaluate('() => { debugger; }')
        end
      end
    end
  end

  describe 'CSSCoverage' do
    it 'should work', sinatra: true do
      page.coverage.start_css_coverage
      page.goto("#{server_prefix}/csscoverage/simple.html")
      coverage = page.coverage.stop_css_coverage
      expect(coverage.size).to eq(1)
      expect(coverage.first.url).to include('/csscoverage/simple.html')
      expect(coverage.first.ranges).to eq([
        { start: 1, end: 22 },
      ])
      expect(coverage.first.text[1...22]).to eq('div { color: green; }')
    end

    it 'should work with block', sinatra: true do
      coverage = page.coverage.css_coverage do
        page.goto("#{server_prefix}/csscoverage/simple.html")
      end
      expect(coverage.size).to eq(1)
      expect(coverage.first.url).to include('/csscoverage/simple.html')
      expect(coverage.first.ranges).to eq([
        { start: 1, end: 22 },
      ])
      expect(coverage.first.text[1...22]).to eq('div { color: green; }')
    end

    it 'should report sourceURLs', sinatra: true do
      coverage = page.coverage.css_coverage do
        page.goto("#{server_prefix}/csscoverage/sourceurl.html")
      end
      expect(coverage.size).to eq(1)
      expect(coverage.first.url).to eq('nicename.css')
    end

    it 'should report multiple stylesheets', sinatra: true do
      coverage = page.coverage.css_coverage do
        page.goto("#{server_prefix}/csscoverage/multiple.html")
      end
      expect(coverage.size).to eq(2)
      expect(coverage.map(&:url)).to contain_exactly(
        include('/csscoverage/stylesheet1.css'),
        include('/csscoverage/stylesheet2.css'),
      )
    end

    it 'should report stylesheets that have no coverage', sinatra: true do
      coverage = page.coverage.css_coverage do
        page.goto("#{server_prefix}/csscoverage/unused.html")
      end
      expect(coverage.size).to eq(1)
      expect(coverage.first.url).to eq('unused.css')
      expect(coverage.first.ranges).to be_empty
    end

    it 'should work with media queries', sinatra: true do
      coverage = page.coverage.css_coverage do
        page.goto("#{server_prefix}/csscoverage/media.html")
      end
      expect(coverage.size).to eq(1)
      expect(coverage.first.url).to include('/csscoverage/media.html')
      expect(coverage.first.ranges).to contain_exactly(
        { start: 8, end: 15 },
        { start: 17, end: 38 },
      )
    end

    it 'should work with complicated usecases', sinatra: true do
      coverage = page.coverage.css_coverage do
        page.goto("#{server_prefix}/csscoverage/involved.html")
      end
      expected_coverage = JSON.parse(File.read('spec/integration/golden-chromium/csscoverage-involved.txt'))
      expect(coverage.size).to eq(expected_coverage.size)
      aggregate_failures do
        coverage.each_with_index do |entry, i|
          expected_entry = expected_coverage[i]
          expect(entry.url).to eq(expected_entry['url'].gsub('http://localhost:<PORT>', server_prefix))
          expect(entry.text).to eq(expected_entry['text'])
          expect(entry.ranges).to eq(expected_entry['ranges'].map { |e| { start: e['start'], end: e['end'] } })
        end
      end
    end

    it 'should work with empty stylesheets', sinatra: true do
      coverage = page.coverage.css_coverage do
        page.goto("#{server_prefix}/csscoverage/empty.html")
      end

      expect(coverage.size).to eq(1)
      expect(coverage.first.text).to eq('')
    end

    it 'should ignore injected stylesheets' do
      coverage = page.coverage.css_coverage do
        page.add_style_tag(content: 'body { margin: 10px;}')

        # trigger style recalc
        margin = page.evaluate("() => window.getComputedStyle(document.body).margin")
        raise "margin must be 10px here" unless margin == '10px'
      end
      expect(coverage).to be_empty
    end

    it 'should work with a recently loaded stylesheet', sinatra: true do
      coverage = page.coverage.css_coverage do
        js = <<~JAVASCRIPT
        async (url) => {
          document.body.textContent = 'hello, world';

          const link = document.createElement('link');
          link.rel = 'stylesheet';
          link.href = url;
          document.head.appendChild(link);
          await new Promise((x) => (link.onload = x));
        }
        JAVASCRIPT
        page.evaluate(js, "#{server_prefix}/csscoverage/stylesheet1.css")
      end
      expect(coverage.size).to eq(1)
    end

    describe 'reset_on_navigation' do
      it 'should report stylesheets across navigations', sinatra: true do
        coverage = page.coverage.css_coverage(reset_on_navigation: false) do
          page.goto("#{server_prefix}/csscoverage/multiple.html")
          page.goto(server_empty_page)
        end
        expect(coverage.size).to eq(2)
      end

      it 'should NOT report stylesheets across navigations', sinatra: true do
        coverage = page.coverage.css_coverage do # Enabled by default.
          page.goto("#{server_prefix}/csscoverage/multiple.html")
          page.goto(server_empty_page)
        end
        expect(coverage).to be_empty
      end
    end
  end
end
