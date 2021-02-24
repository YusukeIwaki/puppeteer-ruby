require 'spec_helper'

RSpec.describe 'evaluation specs' do
  describe 'Page#evaluate', puppeteer: :page do
    it 'should work' do
      expect(page.evaluate('() => 7 * 3')).to eq(21)
    end

    it 'should transfer arrays' do
      arr = [1, 2, 3]
      expect(page.evaluate('(a) => a', arr)).to eq(arr)
      expect(page.evaluate('(a) => Array.isArray(a)', arr)).to eq(true)
    end

    it 'should modify global environment' do
      page.evaluate('() => (globalThis.globalVar = 123)')
      expect(page.evaluate('globalVar')).to eq(123)
    end
  end

  describe 'Page.evaluate_on_new_document' do
    sinatra do
      get('/tamperable.html') do
        '<script> window.result = window.injected; </script>'
      end
    end

    it_fails_firefox 'should evaluate before anything else on the page' do
      page.evaluate_on_new_document('function () { globalThis.injected = 123; }')
      page.goto('http://127.0.0.1:4567/tamperable.html')
      expect(page.evaluate('() => globalThis.result')).to eq(123)
    end
  end
end
