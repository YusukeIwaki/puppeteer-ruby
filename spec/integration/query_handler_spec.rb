require 'spec_helper'

RSpec.describe 'Query handler tests' do
  include_context 'with test state'
  describe 'Text selectors' do
    describe 'in Page' do
      it 'should query existing element' do
        page.content = '<section>test</section>'

        expect(page.query_selector('text/test').evaluate('el => el.tagName')).to eq('SECTION')
        expect(page.query_selector_all('text/test').size).to eq(1)
      end

      it 'should return empty array for non-existing element' do
        page.content = '<section>xxx</section>'

        expect(page.query_selector('text/test')).to be_nil
        expect(page.query_selector_all('text/test')).to be_empty
      end

      it 'should return first element' do
        page.content ='<div id="1">a</div><div>a</div>'

        element = page.query_selector('text/a')
        expect(element['id'].json_value).to eq('1')
      end

      it 'should return multiple elements' do
        page.content ='<div>a</div><div>a</div>'

        elements = page.query_selector_all('text/a')
        expect(elements.size).to eq(2)
      end

      it 'should pierce shadow DOM' do
        js = <<~JAVASCRIPT
        () => {
          const div = document.createElement('div');
          const shadow = div.attachShadow({mode: 'open'});
          const diva = document.createElement('div');
          shadow.append(diva);
          const divb = document.createElement('div');
          shadow.append(divb);
          diva.innerHTML = 'a';
          divb.innerHTML = 'b';
          document.body.append(div);
        }
        JAVASCRIPT
        page.evaluate(js)

        element = page.query_selector('text/a')
        expect(element.evaluate('el => el.textContent')).to eq('a')
      end

      it 'should query deeply nested text' do
        page.content = '<div><div>a</div><div>b</div></div>'

        element = page.query_selector('text/a')
        expect(element.evaluate('el => el.textContent')).to eq('a')
      end

      it 'should query inputs' do
        page.content = '<input type="text" value="a" /><div>a</div>'

        element = page.query_selector('text/a')
        expect(element.evaluate('el => el.tagName')).to eq('INPUT')
      end

      it 'should not query radio' do
        page.content = '<input type="radio" value="a" />'

        expect(page.query_selector('text/a')).to be_nil
      end

      it 'should query text spanning multiple elements' do
        page.content = '<div><span>a</span> <span>b</span><div>'

        element = page.query_selector('text/a b')
        expect(element.evaluate('el => el.tagName')).to eq('DIV')
      end
    end

    describe 'in ElementHandles' do
      it 'should query existing element' do
        page.content = '<div class="a"><span>a</span></div>'

        element_handle = page.query_selector('div')
        expect(element_handle.query_selector('text/a').evaluate('el => el.outerHTML')).to eq('<span>a</span>')
        expect(element_handle.query_selector_all('text/a').size).to eq(1)
      end

      it 'should return null for non-existing element' do
        page.content = '<div class="a"></div>'

        element_handle = page.query_selector('div')
        expect(element_handle.query_selector('text/a')).to be_nil
        expect(element_handle.query_selector_all('text/a')).to be_empty
      end
    end
  end

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
