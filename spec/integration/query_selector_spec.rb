require 'spec_helper'

RSpec.describe 'querySelector' do
  describe 'Page#eval_on_selector' do
    it 'should work' do
      with_test_state do |page:, **|
        page.content = '<section id="testAttribute">43543</section>'
        id = page.eval_on_selector('section', '(e) => e.id')
        expect(id).to eq('testAttribute')
      end
    end

    it 'should accept arguments' do
      with_test_state do |page:, **|
        page.content = '<section>hello</section>'
        text = page.eval_on_selector(
          'section',
          '(e, suffix) => e.textContent + suffix',
          ' world!',
        )
        expect(text).to eq('hello world!')
      end
    end

    it 'should accept ElementHandles as arguments' do
      with_test_state do |page:, **|
        page.content = '<section>hello</section><div> world</div>'
        div_handle = page.query_selector('div')

        text = page.eval_on_selector(
          'section',
          '(e, div) => e.textContent + div.textContent',
          div_handle,
        )
        expect(text).to eq('hello world')
      end
    end

    it 'should throw error if no element is found' do
      with_test_state do |page:, **|
        expect {
          page.eval_on_selector('section', '(e) => e.id')
        }.to raise_error(/failed to find element matching selector "section"/)
      end
    end
  end

  describe 'Page#eval_on_selector_all' do
    it 'should work' do
      with_test_state do |page:, **|
        page.content = '<div>hello</div><div>beautiful</div><div>world!</div>'

        divs_count = page.eval_on_selector_all('div', '(divs) => divs.length')
        expect(divs_count).to eq(3)
      end
    end

    it 'should accept extra arguments' do
      with_test_state do |page:, **|
        page.content = '<div>hello</div><div>beautiful</div><div>world!</div>'

        divs_count_plus5 = page.eval_on_selector_all(
          'div',
          '(divs, two, three) => divs.length + two + three',
          2,
          3,
        )
        expect(divs_count_plus5).to eq(8)
      end
    end

    it 'should accept ElementHandles as arguments' do
      with_test_state do |page:, **|
        page.content = '<section>2</section><section>2</section><section>1</section><div>3</div>'
        div_handle = page.query_selector('div')
        sum = page.eval_on_selector_all(
          'section',
          '(sections, div) => sections.reduce((acc, section) => acc + Number(section.textContent), 0) + Number(div.textContent)',
          div_handle,
        )
        expect(sum).to eq(8)
      end
    end

    it 'should handle many elements', timeout: 25 do
      with_test_state do |page:, **|
        page.evaluate(<<~JAVASCRIPT)
          for (var i = 0; i <= 1000; i++) {
            const section = document.createElement('section');
            section.textContent = i;
            document.body.appendChild(section);
          }
        JAVASCRIPT
        sum = page.eval_on_selector_all(
          'section',
          '(sections) => sections.reduce((acc, section) => acc + Number(section.textContent), 0)',
        )
        expect(sum).to eq(500500)
      end
    end
  end

  describe 'Page#query_selector' do
    it 'should query existing element' do
      with_test_state do |page:, **|
        page.content = '<section>test</section>'

        element = page.query_selector('section')
        expect(element).not_to be_nil
      end
    end

    it 'should return null for non-existing element' do
      with_test_state do |page:, **|
        page.content = '<section>test</section>'

        element = page.query_selector('non-existing-element')
        expect(element).to be_nil
      end
    end
  end

  describe 'Page#query_selector_all' do
    it 'should query existing elements' do
      with_test_state do |page:, **|
        page.content = '<div>A</div><br/><div>B</div>'

        elements = page.query_selector_all('div')
        expect(elements).to be_a(Enumerable)
        expect(elements.size).to eq(2)

        texts = elements.map { |el| page.evaluate('(e) => e.textContent', el) }
        expect(texts).to eq(%w[A B])
      end
    end

    it 'should query existing elements without isolation' do
      with_test_state do |page:, **|
        page.content = '<div>A</div><br/><div>B</div>'

        elements = page.query_selector_all('div', isolate: false)
        expect(elements).to be_a(Enumerable)
        expect(elements.size).to eq(2)

        texts = elements.map { |el| page.evaluate('(e) => e.textContent', el) }
        expect(texts).to eq(%w[A B])
      end
    end

    it 'should return empty array if nothing is found' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        elements = page.query_selector_all('div')
        expect(elements).to be_a(Enumerable)
        expect(elements).to be_empty
      end
    end

    describe 'xpath' do
      it 'should query existing element' do
        with_test_state do |page:, **|
          page.content = '<section>test</section>'
          elements = page.query_selector_all('xpath/html/body/section')
          expect(elements.first).not_to be_nil
          expect(elements.size).to eq(1)
        end
      end

      it 'should return empty array for non-existing element' do
        with_test_state do |page:, **|
          elements = page.query_selector_all('xpath/html/body/non-existing-element')
          expect(elements).to eq([])
        end
      end

      it 'should return multiple elements' do
        with_test_state do |page:, **|
          page.content = '<div></div><div></div>'
          elements = page.query_selector_all('xpath/html/body/div')
          expect(elements.size).to eq(2)
        end
      end
    end
  end

  describe 'ElementHandle#query_selector' do
    it 'should query existing element' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/playground.html")
        page.content = '<html><body><div class="second"><div class="inner">A</div></div></body></html>'

        html = page.query_selector('html')
        second = html.query_selector('.second')
        inner = second.query_selector('.inner')
        content = page.evaluate('(e) => e.textContent', inner)

        expect(content).to eq('A')
      end
    end

    it 'should return null for non-existing element' do
      with_test_state do |page:, **|
        page.content = '<html><body><div class="second"><div class="inner">B</div></div></body></html>'

        html = page.query_selector('html')
        second = html.query_selector('.third')

        expect(second).to be_nil
      end
    end
  end

  describe 'ElementHandle#eval_on_selector' do
    it 'should work' do
      with_test_state do |page:, **|
        page.content = '<html><body><div class="tweet"><div class="like">100</div><div class="retweets">10</div></div></body></html>'

        tweet = page.query_selector('.tweet')
        content = tweet.eval_on_selector('.like', '(node) => node.innerText')

        expect(content).to eq('100')
      end
    end

    it 'should retrieve content from subtree' do
      with_test_state do |page:, **|
        html_content = '<div class="a">not-a-child-div</div><div id="myId"><div class="a">a-child-div</div></div>'
        page.content = html_content

        element_handle = page.query_selector('#myId')
        content = element_handle.eval_on_selector('.a', '(node) => node.innerText')

        expect(content).to eq('a-child-div')
      end
    end

    it 'should throw in case of missing selector' do
      with_test_state do |page:, **|
        html_content = '<div class="a">not-a-child-div</div><div id="myId"></div>'
        page.content = html_content

        element_handle = page.query_selector('#myId')

        expect {
          element_handle.eval_on_selector('.a', '(node) => node.innerText')
        }.to raise_error(/failed to find element matching selector ".a"/)
      end
    end
  end

  describe 'ElementHandle#eval_on_selector_all' do
    it 'should work' do
      with_test_state do |page:, **|
        page.content = '<html><body><div class="tweet"><div class="like">100</div><div class="like">10</div></div></body></html>'

        tweet = page.query_selector('.tweet')
        content = tweet.eval_on_selector_all(
          '.like',
          '(nodes) => nodes.map((n) => n.innerText)',
        )

        expect(content).to eq(['100', '10'])
      end
    end

    it 'should retrieve content from subtree' do
      with_test_state do |page:, **|
        html_content = '<div class="a">not-a-child-div</div><div id="myId"><div class="a">a1-child-div</div><div class="a">a2-child-div</div></div>'
        page.content = html_content

        element_handle = page.query_selector('#myId')
        content = element_handle.eval_on_selector_all(
          '.a',
          '(nodes) => nodes.map((n) => n.innerText)',
        )

        expect(content).to eq(['a1-child-div', 'a2-child-div'])
      end
    end

    it 'should not throw in case of missing selector' do
      with_test_state do |page:, **|
        html_content = '<div class="a">not-a-child-div</div><div id="myId"></div>'
        page.content = html_content

        element_handle = page.query_selector('#myId')
        nodes_length = element_handle.eval_on_selector_all(
          '.a',
          '(nodes) => nodes.length',
        )

        expect(nodes_length).to eq(0)
      end
    end
  end

  describe 'ElementHandle#query_selector_all' do
    it 'should query existing elements' do
      with_test_state do |page:, **|
        page.content = '<html><body><div>A</div><br/><div>B</div></body></html>'

        html = page.query_selector('html')
        elements = html.query_selector_all('div')

        expect(elements).to be_a(Enumerable)
        expect(elements.length).to eq(2)
        expect(elements.map { |el| page.evaluate('(e) => e.textContent', el) }).to eq(%w[A B])
      end
    end

    it 'should return empty array for non-existing elements' do
      with_test_state do |page:, **|
        page.content = '<html><body><span>A</span><br/><span>B</span></body></html>'

        html = page.query_selector('html')
        elements = html.query_selector_all('div')

        expect(elements).to be_a(Enumerable)
        expect(elements).to be_empty
      end
    end

    describe 'xpath' do
      it 'should query existing element' do
        with_test_state do |page:, server:, **|
          page.goto("#{server.prefix}/playground.html")
          page.content = '<html><body><div class="second"><div class="inner">A</div></div></body></html>'

          html = page.query_selector('html')
          second = html.query_selector_all("xpath/./body/div[contains(@class, 'second')]")
          inner = second[0].query_selector_all("xpath/./div[contains(@class, 'inner')]")
          content = page.evaluate('(e) => e.textContent', inner[0])

          expect(content).to eq('A')
        end
      end

      it 'should return null for non-existing element' do
        with_test_state do |page:, **|
          page.content = '<html><body><div class="second"><div class="inner">B</div></div></body></html>'

          html = page.query_selector('html')
          second = html.query_selector_all("xpath/div[contains(@class, 'third')]")
          expect(second).to eq([])
        end
      end
    end
  end

  describe 'QueryAll' do
    before(:all) do
      Puppeteer.register_custom_query_handler(
        name: 'allArray',
        query_all: '(element, selector) => [...element.querySelectorAll(selector)]',
      )
    end

    after(:all) do
      Puppeteer.unregister_custom_query_handler(name: 'allArray')
    end

    it 'should have registered handler' do
      expect(Puppeteer.custom_query_handler_names).to include('allArray')
    end

    it '$$ should query existing elements' do
      with_test_state do |page:, **|
        page.content = '<html><body><div>A</div><br/><div>B</div></body></html>'
        html = page.query_selector('html')
        elements = html.query_selector_all('allArray/div')
        expect(elements.size).to eq(2)
        texts = elements.map { |el| page.evaluate('(e) => e.textContent', el) }
        expect(texts).to eq(%w[A B])
      end
    end

    it '$$ should return empty array for non-existing elements' do
      with_test_state do |page:, **|
        page.content = '<html><body><span>A</span><br/><span>B</span></body></html>'
        html = page.query_selector('html')
        elements = html.query_selector_all('allArray/div')
        expect(elements.size).to eq(0)
      end
    end

    it '$$eval should work' do
      with_test_state do |page:, **|
        page.content = '<div>hello</div><div>beautiful</div><div>world!</div>'
        divs_count = page.eval_on_selector_all('allArray/div', '(divs) => divs.length')
        expect(divs_count).to eq(3)
      end
    end

    it '$$eval should accept extra arguments' do
      with_test_state do |page:, **|
        page.content = '<div>hello</div><div>beautiful</div><div>world!</div>'
        divs_count_plus5 = page.eval_on_selector_all(
          'allArray/div',
          '(divs, two, three) => divs.length + two + three',
          2,
          3,
        )
        expect(divs_count_plus5).to eq(8)
      end
    end

    it '$$eval should accept ElementHandles as arguments' do
      with_test_state do |page:, **|
        page.content = '<section>2</section><section>2</section><section>1</section><div>3</div>'
        div_handle = page.query_selector('div')
        sum = page.eval_on_selector_all(
          'allArray/section',
          '(sections, div) => sections.reduce((acc, section) => acc + Number(section.textContent), 0) + Number(div.textContent)',
          div_handle,
        )
        expect(sum).to eq(8)
      end
    end

    it '$$eval should handle many elements', timeout: 25 do
      with_test_state do |page:, **|
        page.evaluate(<<~JAVASCRIPT)
          for (var i = 0; i <= 1000; i++) {
            const section = document.createElement('section');
            section.textContent = i;
            document.body.appendChild(section);
          }
        JAVASCRIPT
        sum = page.eval_on_selector_all(
          'allArray/section',
          '(sections) => sections.reduce((acc, section) => acc + Number(section.textContent), 0)',
        )
        expect(sum).to eq(500500)
      end
    end
  end
end
