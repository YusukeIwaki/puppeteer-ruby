require 'spec_helper'

RSpec.describe 'querySelector (extensions)' do
  describe 'Page#$x' do
    it 'should query existing element' do
      with_test_state do |page:, **|
        page.content = '<section>test</section>'

        elements = page.Sx('//section')
        expect(elements).to be_a(Enumerable)
        expect(elements.size).to eq(1)
      end
    end

    it 'should return empty array for non-existing element' do
      with_test_state do |page:, **|
        page.content = '<section>test</section>'

        elements = page.Sx('//div')
        expect(elements).to be_a(Enumerable)
        expect(elements).to be_empty
      end
    end

    it 'should return multiple elements' do
      with_test_state do |page:, **|
        page.content = '<div></div><div></div>'

        elements = page.Sx('//div')
        expect(elements).to be_a(Enumerable)
        expect(elements.size).to eq(2)
      end
    end
  end

  describe 'ElementHandle#Sx' do
    it 'should query existing element' do
      with_test_state do |page:, **|
        page.content = '<html><body><div class="second"><div class="inner">A</div></div></body></html>'

        html = page.query_selector('html')
        second = html.Sx("./body/div[contains(@class, 'second')]")
        inner = second[0].Sx("./div[contains(@class, 'inner')]")
        content = page.evaluate(
          '(e) => e.textContent',
          inner.first,
        )

        expect(content).to eq('A')
      end
    end

    it 'should return null for non-existing element' do
      with_test_state do |page:, **|
        page.content = '<html><body><div class="second"><div class="inner">B</div></div></body></html>'

        html = page.query_selector('html')
        second = html.Sx("/div[contains(@class, 'third')]")

        expect(second).to be_a(Enumerable)
        expect(second).to be_empty
      end
    end
  end
end
