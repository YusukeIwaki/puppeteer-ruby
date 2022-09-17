require 'spec_helper'

RSpec.describe 'Query handler tests' do
  describe 'XPath selectors' do
    describe 'in Page' do
      it 'should query existing element' do
        page.content = '<section>test</section>'
        el = page.query_selector('xpath/html/body/section')
        expect(el).to be_a(Puppeteer::ElementHandle)
        expect(el.evaluate('el => el.textContent')).to eq('test')

        elements = page.query_selector_all('xpath/html/body/section')
        expect(elements.size).to eq(1)
        el = elements.first
        expect(el).to be_a(Puppeteer::ElementHandle)
        expect(el.evaluate('el => el.textContent')).to eq('test')
      end

      it 'should return empty array for non-existing element' do
        el = page.query_selector('xpath/html/body/non-existing-element')
        expect(el).to be_nil

        elements = page.query_selector_all('xpath/html/body/non-existing-element')
        expect(elements).to be_empty
      end

      it 'should return first element' do
        page.content = '<div>a</div><div>b</div>'

        el = page.query_selector('xpath/html/body/div')
        expect(el.evaluate('el => el.textContent')).to eq('a')
      end

      it 'should return multiple elements' do
        page.content = '<div>a</div><div>b</div>'

        elements = page.query_selector_all('xpath/html/body/div')
        expect(elements.size).to eq(2)
        expect(elements.first.evaluate('el => el.textContent')).to eq('a')
        expect(elements.last.evaluate('el => el.textContent')).to eq('b')
      end
    end

    describe 'in ElementHandles' do
      it 'should query existing element' do
        page.content = '<span>outer</span><div class="a">a<span>inner</span></div>'
        div = page.query_selector('div')
        el = div.query_selector('xpath/span')
        expect(el).to be_a(Puppeteer::ElementHandle)
        expect(el.evaluate('el => el.textContent')).to eq('inner')

        elements = div.query_selector_all('xpath/span')
        expect(elements.size).to eq(1)
        el = elements.first
        expect(el).to be_a(Puppeteer::ElementHandle)
        expect(el.evaluate('el => el.textContent')).to eq('inner')
      end

      it 'should return null for non-existing element' do
        page.content = '<div class="a">a</div>'

        div = page.query_selector('div')
        el = div.query_selector('xpath/div')
        expect(el).to be_nil

        elements = div.query_selector_all('xpath/html/body/div')
        expect(elements).to be_empty
      end
    end
  end
end
