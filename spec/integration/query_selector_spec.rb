require 'spec_helper'

RSpec.describe 'querySelector' do
  describe 'Page#eval_on_selector' do
    it 'should work' do
      page.content = '<section id="testAttribute">43543</section>'
      id = page.eval_on_selector('section', '(e) => e.id')
      expect(id).to eq('testAttribute')
    end

    it 'should accept arguments' do
      page.content = '<section>hello</section>'
      text = page.eval_on_selector(
        'section',
        '(e, suffix) => e.textContent + suffix',
        ' world!',
      )
      expect(text).to eq('hello world!')
    end

    it 'should accept ElementHandles as arguments' do
      page.content = '<section>hello</section><div> world</div>'
      div_handle = page.S('div')

      text = page.eval_on_selector(
        'section',
        '(e, div) => e.textContent + div.textContent',
        div_handle,
      )
      expect(text).to eq('hello world')
    end

    it 'should throw error if no element is found' do
      expect {
        page.eval_on_selector('section', '(e) => e.id')
      }.to raise_error(/failed to find element matching selector "section"/)
    end
  end

  describe 'Page#eval_on_selector_all' do
    it 'should work' do
      page.content = '<div>hello</div><div>beautiful</div><div>world!</div>'

      divs_count = page.eval_on_selector_all('div', '(divs) => divs.length')
      expect(divs_count).to eq(3)
    end
  end

  describe 'Page#S' do
    it 'should query existing element' do
      page.content = '<section>test</section>'

      element = page.S('section')
      expect(element).not_to be_nil
    end

    it 'should return null for non-existing element' do
      page.content = '<section>test</section>'

      element = page.S('non-existing-element')
      expect(element).to be_nil
    end
  end

  describe 'Page#SS' do
    it 'should query existing elements' do
      page.content = '<div>A</div><br/><div>B</div>'

      elements = page.SS('div')
      expect(elements).to be_a(Enumerable)
      expect(elements.size).to eq(2)

      texts = elements.map { |el| page.evaluate('(e) => e.textContent', el) }
      expect(texts).to eq(%w[A B])
    end

    it 'should return empty array if nothing is found' do
      page.content = '<span>A</span><br/><span>B</span>'
      elements = page.SS('div')
      expect(elements).to be_a(Enumerable)
      expect(elements).to be_empty
    end
  end

  describe 'Page#$x' do
    it 'should query existing element' do
      page.content = '<section>test</section>'

      elements = page.Sx('//section')
      expect(elements).to be_a(Enumerable)
      expect(elements.size).to eq(1)
    end

    it 'should return empty array for non-existing element' do
      page.content = '<section>test</section>'

      elements = page.Sx('//div')
      expect(elements).to be_a(Enumerable)
      expect(elements).to be_empty
    end

    it 'should return multiple elements' do
      page.content = '<div></div><div></div>'

      elements = page.Sx('//div')
      expect(elements).to be_a(Enumerable)
      expect(elements.size).to eq(2)
    end
  end

  describe 'ElementHandle#S' do
    it 'should query existing element' do
      page.content = '<html><body><div class="second"><div class="inner">A</div></div></body></html>'

      html = page.S('html')
      second = html.S('.second')
      inner = second.S('.inner')
      content = page.evaluate('(e) => e.textContent', inner)

      expect(content).to eq('A')
    end

    it 'should return null for non-existing element' do
      page.content = '<html><body><div class="second"><div class="inner">B</div></div></body></html>'

      html = page.S('html')
      second = html.S('.third')

      expect(second).to be_nil
    end
  end

  describe 'ElementHandle#eval_on_selector' do
    it 'should work' do
      page.content = '<html><body><div class="tweet"><div class="like">100</div><div class="retweets">10</div></div></body></html>'

      tweet = page.S('.tweet')
      content = tweet.eval_on_selector('.like', '(node) => node.innerText')

      expect(content).to eq('100')
    end

    it 'should retrieve content from subtree' do
      html_content = '<div class="a">not-a-child-div</div><div id="myId"><div class="a">a-child-div</div></div>'
      page.content = html_content

      element_handle = page.S('#myId')
      content = element_handle.eval_on_selector('.a', '(node) => node.innerText')

      expect(content).to eq('a-child-div')
    end

    it 'should throw in case of missing selector' do
      html_content = '<div class="a">not-a-child-div</div><div id="myId"></div>'
      page.content = html_content

      element_handle = page.S('#myId')

      expect {
        element_handle.eval_on_selector('.a', '(node) => node.innerText')
      }.to raise_error(/failed to find element matching selector ".a"/)
    end
  end

  describe 'ElementHandle#eval_on_selector_all' do
    it 'should work' do
      page.content = '<html><body><div class="tweet"><div class="like">100</div><div class="like">10</div></div></body></html>'

      tweet = page.S('.tweet')
      content = tweet.eval_on_selector_all(
        '.like',
        '(nodes) => nodes.map((n) => n.innerText)',
      )

      expect(content).to eq(['100', '10'])
    end

    it 'should retrieve content from subtree' do
      html_content = '<div class="a">not-a-child-div</div><div id="myId"><div class="a">a1-child-div</div><div class="a">a2-child-div</div></div>'
      page.content = html_content

      element_handle = page.S('#myId')
      content = element_handle.eval_on_selector_all(
        '.a',
        '(nodes) => nodes.map((n) => n.innerText)',
      )

      expect(content).to eq(['a1-child-div', 'a2-child-div'])
    end

    it 'should not throw in case of missing selector' do
      html_content = '<div class="a">not-a-child-div</div><div id="myId"></div>'
      page.content = html_content

      element_handle = page.S('#myId')
      nodes_length = element_handle.eval_on_selector_all(
        '.a',
        '(nodes) => nodes.length',
      )

      expect(nodes_length).to eq(0)
    end
  end

  describe 'ElementHandle#SS' do
    it 'should query existing elements' do
      page.content = '<html><body><div>A</div><br/><div>B</div></body></html>'

      html = page.S('html')
      elements = html.SS('div')

      expect(elements).to be_a(Enumerable)
      expect(elements.length).to eq(2)
      expect(elements.map { |el| page.evaluate('(e) => e.textContent', el) }).to eq(%w[A B])
    end

    it 'should return empty array for non-existing elements' do
      page.content = '<html><body><span>A</span><br/><span>B</span></body></html>'

      html = page.S('html')
      elements = html.SS('div')

      expect(elements).to be_a(Enumerable)
      expect(elements).to be_empty
    end
  end

  describe 'ElementHandle#Sx' do
    it 'should query existing element' do
      page.content = '<html><body><div class="second"><div class="inner">A</div></div></body></html>'

      html = page.S('html')
      second = html.Sx("./body/div[contains(@class, 'second')]")
      inner = second[0].Sx("./div[contains(@class, 'inner')]")
      content = page.evaluate(
        '(e) => e.textContent',
        inner.first,
      )

      expect(content).to eq('A')
    end

    it 'should return null for non-existing element' do
      page.content = '<html><body><div class="second"><div class="inner">B</div></div></body></html>'

      html = page.S('html')
      second = html.Sx("/div[contains(@class, 'third')]")


      expect(second).to be_a(Enumerable)
      expect(second).to be_empty
    end
  end
end
