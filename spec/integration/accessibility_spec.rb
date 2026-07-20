require 'spec_helper'

RSpec.describe 'Accessibility' do
  include Utils::AttachFrame

  def expect_ax_tree(actual, expected)
    expect(actual).to be_a(Hash)
    expected.each do |key, value|
      if key == 'children'
        expect(actual.fetch(key).length).to eq(value.length)
        actual.fetch(key).zip(value).each do |actual_child, expected_child|
          expect_ax_tree(actual_child, expected_child)
        end
      else
        expect(actual[key]).to eq(value)
      end
    end
  end

  it 'should work' do
    with_test_state do |page:, **|
      page.set_content(<<~HTML)
        <!DOCTYPE html>
        <html lang="en">
        <head><title>Accessibility Test</title></head>
        <body>
          <div>Hello World</div>
          <h1>Inputs</h1>
          <input placeholder="Empty input" autofocus />
          <input placeholder="readonly input" readonly />
          <input placeholder="disabled input" disabled />
          <input aria-label="Input with whitespace" value="  " />
          <input value="value only" />
          <input aria-placeholder="placeholder" value="and a value" />
          <div aria-hidden="true" id="desc">This is a description!</div>
          <input aria-placeholder="placeholder" value="and a value" aria-describedby="desc" />
          <select><option>First Option</option><option>Second Option</option></select>
          <a href="https://example.com">example</a>
        </body>
      HTML
      page.focus('[placeholder="Empty input"]')

      expect_ax_tree(page.accessibility.snapshot, {
        'role' => 'RootWebArea',
        'name' => 'Accessibility Test',
        'children' => [
          { 'role' => 'StaticText', 'name' => 'Hello World' },
          { 'role' => 'heading', 'name' => 'Inputs', 'level' => 1 },
          { 'role' => 'textbox', 'name' => 'Empty input', 'focused' => true },
          { 'role' => 'textbox', 'name' => 'readonly input', 'readonly' => true },
          { 'role' => 'textbox', 'name' => 'disabled input', 'disabled' => true },
          { 'role' => 'textbox', 'name' => 'Input with whitespace', 'value' => '  ' },
          { 'role' => 'textbox', 'name' => '', 'value' => 'value only' },
          { 'role' => 'textbox', 'name' => 'placeholder', 'value' => 'and a value' },
          {
            'role' => 'textbox',
            'name' => 'placeholder',
            'value' => 'and a value',
            'description' => 'This is a description!',
          },
          {
            'role' => 'combobox',
            'name' => '',
            'value' => 'First Option',
            'haspopup' => 'menu',
            'expanded' => false,
            'children' => [
              { 'role' => 'option', 'name' => 'First Option', 'selected' => true },
              { 'role' => 'option', 'name' => 'Second Option' },
            ],
          },
          { 'name' => 'example', 'role' => 'link', 'url' => 'https://example.com/' },
        ],
      })
    end
  end

  it 'should work for showcase', sinatra: true do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/a11y/landmarks.html")
      snapshot = page.accessibility.snapshot
      search_children = [{ 'role' => 'search', 'name' => '' }]
      begin
        expect_ax_tree(snapshot, build_showcase_tree([
          { 'role' => 'form', 'name' => '', 'children' => search_children },
        ]))
      rescue RSpec::Expectations::ExpectationNotMetError
        expect_ax_tree(snapshot, build_showcase_tree(search_children))
      end
    end
  end

  it 'should report uninteresting nodes' do
    with_test_state do |page:, **|
      page.set_content('<textarea>hi</textarea>')
      page.focus('textarea')
      focused = find_focused_node(
        page.accessibility.snapshot(interesting_only: false),
      )
      expect_ax_tree(focused, {
        'role' => 'textbox',
        'name' => '',
        'value' => 'hi',
        'focused' => true,
        'multiline' => true,
        'children' => [{
          'role' => 'generic',
          'name' => '',
          'children' => [{ 'role' => 'StaticText', 'name' => 'hi' }],
        }],
      })
    end
  end

  describe 'iframes' do
    it 'should not include iframe data if not requested', sinatra: true do
      with_test_state do |page:, server:, **|
        frame = attach_frame(page, 'frame1', server.empty_page)
        frame.evaluate(<<~JAVASCRIPT)
          () => {
            const button = document.createElement('button');
            button.innerText = 'value1';
            document.body.appendChild(button);
          }
        JAVASCRIPT
        snapshot = page.accessibility.snapshot(interesting_only: true)
        expect_ax_tree(snapshot, { 'role' => 'RootWebArea', 'name' => '' })
      end
    end

    it 'same-origin iframe (interesting only)', sinatra: true do
      with_test_state do |page:, server:, **|
        frame = attach_frame(page, 'frame1', server.empty_page)
        add_accessible_button(frame)
        expect_ax_tree(
          page.accessibility.snapshot(interesting_only: true, include_iframes: true),
          iframe_tree,
        )
      end
    end

    it 'cross-origin iframe (interesting only)', sinatra: true do
      with_test_state do |page:, server:, **|
        frame = attach_frame(page, 'frame1', "#{server.cross_process_prefix}/empty.html")
        add_accessible_button(frame)
        expect_ax_tree(
          page.accessibility.snapshot(interesting_only: true, include_iframes: true),
          iframe_tree,
        )
      end
    end

    it 'same-origin iframe (all nodes)', sinatra: true do
      with_test_state do |page:, server:, **|
        frame = attach_frame(page, 'frame1', server.empty_page)
        add_accessible_button(frame)
        expect_ax_tree(
          page.accessibility.snapshot(interesting_only: false, include_iframes: true),
          {
            'role' => 'RootWebArea',
            'name' => '',
            'children' => [{
              'role' => 'none',
              'children' => [{
                'role' => 'generic',
                'name' => '',
                'children' => [{
                  'role' => 'Iframe',
                  'name' => '',
                  'children' => [{
                    'role' => 'RootWebArea',
                    'name' => '',
                    'children' => [{
                      'role' => 'none',
                      'children' => [{
                        'role' => 'generic',
                        'name' => '',
                        'children' => [{
                          'role' => 'button',
                          'name' => 'value1',
                          'children' => [{
                            'role' => 'StaticText',
                            'name' => 'value1',
                            'children' => [{ 'role' => 'InlineTextBox' }],
                          }],
                        }],
                      }],
                    }],
                  }],
                }],
              }],
            }],
          },
        )
      end
    end
  end

  it 'keyshortcuts' do
    with_test_state do |page:, **|
      page.set_content('<div role="grid" tabindex="-1" aria-keyshortcuts="foo">hey</div>')
      snapshot = page.accessibility.snapshot
      expect(snapshot.fetch('children').first['keyshortcuts']).to eq('foo')
    end
  end

  describe 'filtering children of leaf nodes' do
    describe 'root option' do
      it 'should work a button' do
        with_test_state do |page:, **|
          page.set_content('<button>My Button</button>')
          button = page.query_selector('button')
          expect_ax_tree(
            page.accessibility.snapshot(root: button),
            { 'role' => 'button', 'name' => 'My Button' },
          )
          button.dispose
        end
      end

      it 'should return null when the element is no longer in DOM' do
        with_test_state do |page:, **|
          page.set_content('<button>My Button</button>')
          button = page.query_selector('button')
          page.eval_on_selector('button', 'button => button.remove()')
          expect(page.accessibility.snapshot(root: button)).to be_nil
          button.dispose
        end
      end

      it 'should support the interestingOnly option' do
        with_test_state do |page:, **|
          page.set_content('<div><button>My Button</button></div><div class="uninteresting"></div>')
          uninteresting = page.query_selector('div.uninteresting')
          expect(page.accessibility.snapshot(root: uninteresting)).to be_nil
          uninteresting.dispose

          div = page.query_selector('div')
          expect_ax_tree(
            page.accessibility.snapshot(root: div),
            { 'name' => 'My Button', 'role' => 'button' },
          )
          expect_ax_tree(
            page.accessibility.snapshot(root: div, interesting_only: false),
            {
              'role' => 'generic',
              'name' => '',
              'children' => [{
                'role' => 'button',
                'name' => 'My Button',
                'children' => [{ 'role' => 'StaticText', 'name' => 'My Button' }],
              }],
            },
          )
          div.dispose
        end
      end
    end

    describe 'elementHandle()' do
      it 'should get an ElementHandle from a snapshot item' do
        with_test_state do |page:, **|
          page.set_content('<button>My Button</button>')
          button = page.query_selector('button')
          snapshot = page.accessibility.snapshot(root: button)
          button_handle = snapshot.element_handle
          expect(button_handle.evaluate('button => button.innerHTML')).to eq('My Button')
          button_handle.dispose
          button.dispose
        end
      end

      it 'should get the parent ElementHandle from a text node accessibility node' do
        with_test_state do |page:, **|
          page.set_content('<div><b>Hello, </b> world!</div>')
          div = page.query_selector('div')
          parent_snapshot = page.accessibility.snapshot(
            root: div,
            interesting_only: false,
          )
          expect_ax_tree(parent_snapshot, {
            'role' => 'generic',
            'name' => '',
            'children' => [
              { 'role' => 'StaticText', 'name' => 'Hello, ' },
              { 'role' => 'StaticText', 'name' => 'world!' },
            ],
          })
          text_node = div.evaluate_handle('element => element.lastChild')
          snapshot = page.accessibility.snapshot(root: text_node)
          expect_ax_tree(snapshot, { 'role' => 'StaticText', 'name' => 'world!' })
          parent_node_handle = parent_snapshot.element_handle
          text_node_handle = snapshot.element_handle
          expect(
            parent_node_handle.evaluate('(parent, text) => parent === text', text_node_handle),
          ).to eq(true)
          expect(text_node_handle.evaluate('element => element.innerHTML')).to eq(
            '<b>Hello, </b> world!',
          )
          parent_node_handle.dispose
          text_node_handle.dispose
          text_node.dispose
          div.dispose
        end
      end
    end
  end

  it 'should capture new accessibility properties and not prune them' do
    with_test_state do |page:, **|
      page.set_content(<<~HTML)
        <div role="alert" aria-busy="true">This is an alert</div>
        <div aria-live="polite" aria-atomic="true" aria-relevant="additions text">
          This is polite live region
        </div>
        <div aria-modal="true" role="dialog" aria-roledescription="My Modal">Modal content</div>
        <div id="error">Error message</div>
        <input aria-invalid="true" aria-errormessage="error" value="invalid input">
        <div id="details">Additional details</div>
        <div aria-details="details">Element with details</div>
        <div aria-description="This is a description"></div>
      HTML
      snapshot = page.accessibility.snapshot
      expect_ax_tree(snapshot, {
        'role' => 'RootWebArea',
        'children' => [
          {
            'role' => 'alert',
            'name' => '',
            'busy' => true,
            'live' => 'assertive',
            'atomic' => true,
            'children' => [{ 'role' => 'StaticText', 'name' => 'This is an alert' }],
          },
          {
            'role' => 'generic',
            'name' => '',
            'live' => 'polite',
            'atomic' => true,
            'relevant' => 'additions text',
            'children' => [{ 'role' => 'StaticText', 'name' => 'This is polite live region' }],
          },
          {
            'role' => 'dialog',
            'name' => '',
            'modal' => true,
            'roledescription' => 'My Modal',
            'children' => [{ 'role' => 'StaticText', 'name' => 'Modal content' }],
          },
          { 'role' => 'StaticText', 'name' => 'Error message' },
          {
            'role' => 'textbox',
            'value' => 'invalid input',
            'invalid' => 'true',
            'errormessage' => 'error',
          },
          { 'role' => 'StaticText', 'name' => 'Additional details' },
          {
            'role' => 'generic',
            'details' => 'details',
            'children' => [{ 'role' => 'StaticText', 'name' => 'Element with details' }],
          },
          {
            'role' => 'generic',
            'description' => 'This is a description',
          },
        ],
      })
    end
  end

  def add_accessible_button(frame)
    frame.evaluate(<<~JAVASCRIPT)
      () => {
        const button = document.createElement('button');
        button.innerText = 'value1';
        document.body.appendChild(button);
      }
    JAVASCRIPT
  end

  def iframe_tree
    {
      'role' => 'RootWebArea',
      'name' => '',
      'children' => [{
        'role' => 'Iframe',
        'name' => '',
        'children' => [{
          'role' => 'RootWebArea',
          'name' => '',
          'children' => [{ 'role' => 'button', 'name' => 'value1' }],
        }],
      }],
    }
  end

  def find_focused_node(node)
    return node if node&.fetch('focused', false)

    node&.fetch('children', [])&.each do |child|
      focused_child = find_focused_node(child)
      return focused_child if focused_child
    end
    nil
  end

  def build_showcase_tree(children)
    {
      'role' => 'RootWebArea',
      'name' => 'HTML Elements Showcase',
      'children' => [
        {
          'role' => 'banner',
          'name' => '',
          'children' => [
            { 'role' => 'heading', 'name' => 'HTML Elements Showcase', 'level' => 1 },
            {
              'role' => 'navigation',
              'name' => '',
              'children' => %w[Forms Media Interactive].map do |name|
                {
                  'role' => 'link',
                  'name' => name,
                  'children' => [{ 'role' => 'StaticText', 'name' => name }],
                }
              end,
            },
          ],
        },
        { 'role' => 'main', 'name' => '', 'children' => children },
        {
          'role' => 'complementary',
          'name' => '',
          'children' => [{ 'role' => 'StaticText', 'name' => 'complementary' }],
        },
        {
          'role' => 'contentinfo',
          'name' => '',
          'children' => [{ 'role' => 'StaticText', 'name' => 'contentinfo' }],
        },
      ],
    }
  end
end
