require 'spec_helper'

RSpec.describe 'Evaluation specs' do
  include Utils::AttachFrame

  describe 'Page.evaluate' do
    it 'should work' do
      with_test_state do |page:, **|
        result = page.evaluate('() => 7 * 3')
        expect(result).to eq(21)
      end
    end

    it 'should transfer BigInt' do
      with_test_state do |page:, **|
        bigint_handle = page.evaluate_handle('() => BigInt(42)')
        begin
          result = page.evaluate('(a) => a', bigint_handle)
          expect(result).to eq(42)
        ensure
          bigint_handle&.dispose
        end
      end
    end

    it 'should transfer NaN' do
      with_test_state do |page:, **|
        nan_handle = page.evaluate_handle('() => NaN')
        begin
          result = page.evaluate('(a) => a', nan_handle)
          expect(result.nan?).to eq(true)
        ensure
          nan_handle&.dispose
        end
      end
    end

    it 'should transfer -0' do
      with_test_state do |page:, **|
        neg_zero_handle = page.evaluate_handle('() => -0')
        begin
          result = page.evaluate('(a) => a', neg_zero_handle)
          expect(result.zero?).to eq(true)
          expect(1.0 / result).to eq(-Float::INFINITY)
        ensure
          neg_zero_handle&.dispose
        end
      end
    end

    it 'should transfer Infinity' do
      with_test_state do |page:, **|
        infinity_handle = page.evaluate_handle('() => Infinity')
        begin
          result = page.evaluate('(a) => a', infinity_handle)
          expect(result.infinite?).to eq(1)
        ensure
          infinity_handle&.dispose
        end
      end
    end

    it 'should transfer -Infinity' do
      with_test_state do |page:, **|
        neg_infinity_handle = page.evaluate_handle('() => -Infinity')
        begin
          result = page.evaluate('(a) => a', neg_infinity_handle)
          expect(result.infinite?).to eq(-1)
        ensure
          neg_infinity_handle&.dispose
        end
      end
    end

    it 'should transfer arrays' do
      with_test_state do |page:, **|
        result = page.evaluate('(a) => a', [1, 2, 3])
        expect(result).to eq([1, 2, 3])
      end
    end

    it 'should transfer arrays as arrays, not objects' do
      with_test_state do |page:, **|
        result = page.evaluate('(a) => Array.isArray(a)', [1, 2, 3])
        expect(result).to eq(true)
      end
    end

    it 'should transfer RegEx' do
      with_test_state do |page:, **|
        result = page.evaluate('(a) => `Hello World!`.match(a)[1]', /Hello (.*)/)
        expect(result).to eq('World!')
      end
    end

    it 'should modify global environment' do
      with_test_state do |page:, **|
        page.evaluate('() => (globalThis.globalVar = 123)')
        expect(page.evaluate('globalVar')).to eq(123)
      end
    end

    it 'should evaluate in the page context' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/global-var.html")
        expect(page.evaluate('globalVar')).to eq(123)
      end
    end

    it 'should replace symbols with undefined' do
      with_test_state do |page:, **|
        result = page.evaluate('() => [Symbol("foo4"), "foo"]')
        expect(result).to eq([nil, 'foo'])
      end
    end

    it 'should work with function shorthands' do
      with_test_state do |page:, **|
        sum = '(a, b) => a + b'
        mult = 'async (a, b) => a * b'
        expect(page.evaluate(sum, 1, 2)).to eq(3)
        expect(page.evaluate(mult, 2, 4)).to eq(8)
      end
    end

    it 'should work with function shorthands and nested arrow functions' do
      with_test_state do |page:, **|
        sum = '(a, b) => { const _arrow = () => {}; _arrow(); return a + b; }'
        expect(page.evaluate(sum, 1, 2)).to eq(3)
      end
    end

    it 'should work with unicode chars' do
      with_test_state do |page:, **|
        result = page.evaluate('(a) => a["中文字符"]', { '中文字符' => 42 })
        expect(result).to eq(42)
      end
    end

    it 'should throw when evaluation triggers reload' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.evaluate(<<~JAVASCRIPT)
          () => {
            location.reload();
            return new Promise(() => {});
          }
          JAVASCRIPT
        rescue => e
          error = e
        end
        expect(error).to be_truthy
        expect(
          ['Execution context was destroyed', 'no such frame'].any? do |text|
            error.message.include?(text)
          end,
        ).to eq(true)
      end
    end

    it 'should await promise' do
      with_test_state do |page:, **|
        result = page.evaluate('() => Promise.resolve(8 * 7)')
        expect(result).to eq(56)
      end
    end

    it 'should work right after framenavigated' do
      with_test_state do |page:, server:, **|
        frame_evaluation = nil
        page.on('framenavigated') do |frame|
          frame_evaluation = frame.async_evaluate('() => 6 * 7')
        end
        page.goto(server.empty_page)
        expect(frame_evaluation.wait).to eq(42)
      end
    end

    it 'should work from-inside an exposed function' do
      with_test_state do |page:, **|
        page.expose_function('callController', lambda do |a, b|
          page.evaluate('(a, b) => a * b', a, b)
        end)
        result = page.evaluate(<<~JAVASCRIPT)
        async () => {
          return globalThis.callController(9, 3);
        }
        JAVASCRIPT
        expect(result).to eq(27)
      end
    end

    it 'should reject promise with exception' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.evaluate('() => notExistingObject.property')
        rescue => e
          error = e
        end
        expect(error).to be_truthy
        expect(error.message).to include('notExistingObject')
      end
    end

    it 'should support thrown strings as error messages' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.evaluate('() => { throw "qwerty"; }')
        rescue => e
          error = e
        end
        expect(error.to_s).to include('qwerty')
      end
    end

    it 'should support thrown numbers as error messages' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.evaluate('() => { throw 100500; }')
        rescue => e
          error = e
        end
        expect(error.to_s).to include('100500')
      end
    end

    it 'should support thrown platform objects as error messages' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.evaluate('() => { throw new DOMException("some DOMException message"); }')
        rescue => e
          error = e
        end
        expect(error.message).to include('some DOMException message')
      end
    end

    it 'should return complex objects' do
      with_test_state do |page:, **|
        object = { 'foo' => 'bar!' }
        result = page.evaluate('(a) => a', object)
        expect(result).not_to equal(object)
        expect(result).to eq(object)
      end
    end

    it 'should return BigInt' do
      with_test_state do |page:, **|
        result = page.evaluate('() => BigInt(42)')
        expect(result).to eq(42)
      end
    end

    it 'should return NaN' do
      with_test_state do |page:, **|
        result = page.evaluate('() => NaN')
        expect(result.nan?).to eq(true)
      end
    end

    it 'should return -0' do
      with_test_state do |page:, **|
        result = page.evaluate('() => -0')
        expect(result.zero?).to eq(true)
        expect(1.0 / result).to eq(-Float::INFINITY)
      end
    end

    it 'should return Infinity' do
      with_test_state do |page:, **|
        result = page.evaluate('() => Infinity')
        expect(result.infinite?).to eq(1)
      end
    end

    it 'should return -Infinity' do
      with_test_state do |page:, **|
        result = page.evaluate('() => -Infinity')
        expect(result.infinite?).to eq(-1)
      end
    end

    it 'should return RegEx' do
      with_test_state do |page:, **|
        result = page.evaluate('() => /(.*)/')
        expect(result).to be_a(Regexp)
      end
    end

    it 'should accept "null" as one of multiple parameters' do
      with_test_state do |page:, **|
        result = page.evaluate(
          '(a, b) => Object.is(a, null) && Object.is(b, "foo")',
          nil,
          'foo',
        )
        expect(result).to eq(true)
      end
    end

    it 'should properly serialize null fields' do
      with_test_state do |page:, **|
        result = page.evaluate('() => ({ a: undefined })')
        expect(result).to eq({})
      end
    end

    it 'should return undefined for non-serializable objects' do
      with_test_state do |page:, **|
        result = page.evaluate('() => window')
        expect(result).to be_nil
      end
    end

    it 'should return promise as empty object' do
      with_test_state do |page:, **|
        result = page.evaluate(<<~JAVASCRIPT)
        () => {
          return {
            promise: new Promise(resolve => {
              setTimeout(resolve, 1000);
            }),
          };
        }
        JAVASCRIPT
        expect(result).to eq({ 'promise' => {} })
      end
    end

    it 'should work for circular object' do
      with_test_state do |page:, **|
        result = page.evaluate(<<~JAVASCRIPT)
        () => {
          const a = {
            c: 5,
            d: {
              foo: 'bar',
            },
          };
          const b = {a};
          a['b'] = b;
          return a;
        }
        JAVASCRIPT
        expect(result).to include(
          'c' => 5,
          'd' => { 'foo' => 'bar' },
          'b' => { 'a' => nil },
        )
      end
    end

    it 'should accept a string' do
      with_test_state do |page:, **|
        result = page.evaluate('1 + 2')
        expect(result).to eq(3)
      end
    end

    it 'should accept a string with semi colons' do
      with_test_state do |page:, **|
        result = page.evaluate('1 + 5;')
        expect(result).to eq(6)
      end
    end

    it 'should accept a string with comments' do
      with_test_state do |page:, **|
        result = page.evaluate("2 + 5;\n// do some math!")
        expect(result).to eq(7)
      end
    end

    it 'should accept element handle as an argument' do
      with_test_state do |page:, **|
        page.set_content('<section>42</section>')
        element = page.query_selector('section')
        begin
          text = page.evaluate('(e) => e.textContent', element)
          expect(text).to eq('42')
        ensure
          element&.dispose
        end
      end
    end

    it 'should throw if underlying element was disposed' do
      with_test_state do |page:, **|
        page.set_content('<section>39</section>')
        element = page.query_selector('section')
        element.dispose
        error = nil
        begin
          page.evaluate('(e) => e.textContent', element)
        rescue => e
          error = e
        end
        expect(error.message).to match(/JSHandles? is disposed/)
      end
    end

    it 'should throw if elementHandles are from other frames' do
      with_test_state do |page:, server:, **|
        attach_frame(page, 'frame1', server.empty_page)
        body_handle = page.frames[1].query_selector('body')
        error = nil
        begin
          page.evaluate('(body) => body?.innerHTML', body_handle)
        rescue => e
          error = e
        ensure
          body_handle&.dispose
        end
        expect(error).to be_truthy
        expect(
          [
            'JSHandles can be evaluated only in the context they were created',
            "Trying to evaluate JSHandle from different frames. Usually this means you're using a handle from a page on a different page.",
          ].any? { |message| error.message.include?(message) },
        ).to eq(true)
      end
    end

    it 'should simulate a user gesture' do
      with_test_state do |page:, **|
        result = page.evaluate(<<~JAVASCRIPT)
        () => {
          document.body.appendChild(document.createTextNode('test'));
          document.execCommand('selectAll');
          return document.execCommand('copy');
        }
        JAVASCRIPT
        expect(result).to eq(true)
      end
    end

    it 'should not throw an error when evaluation does a navigation' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/one-style.html")
        on_request = async_promise { server.wait_for_request('/empty.html') }
        result = page.evaluate(<<~JAVASCRIPT)
        () => {
          window.location = '/empty.html';
          return [42];
        }
        JAVASCRIPT
        expect(result).to eq([42])
        on_request.wait
      end
    end

    it 'should transfer 100Mb of data from page to node.js' do
      with_test_state do |page:, **|
        result = page.evaluate('() => Array(100 * 1024 * 1024 + 1).join("a")')
        expect(result.length).to eq(100 * 1024 * 1024)
      end
    end

    it 'should throw error with detailed information on exception inside promise' do
      with_test_state do |page:, **|
        error = nil
        begin
          page.evaluate(<<~JAVASCRIPT)
          () => {
            return new Promise(() => {
              throw new Error('Error in promise');
            });
          }
          JAVASCRIPT
        rescue => e
          error = e
        end
        expect(error.message).to include('Error in promise')
      end
    end

    it 'should return properly serialize objects with unknown type fields' do
      with_test_state do |page:, **|
        page.set_content(<<~HTML)
          <img
            src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
          />
        HTML

        result = page.evaluate(<<~JAVASCRIPT)
        async () => {
          const image = document.querySelector('img');
          const imageBitmap = await createImageBitmap(image);

          return {
            a: 'foo',
            b: imageBitmap,
          };
        }
        JAVASCRIPT

        expect(result).to eq({
          'a' => 'foo',
          'b' => nil,
        })
      end
    end
  end

  describe 'Page.evaluateOnNewDocument' do
    it 'should evaluate before anything else on the page' do
      with_test_state do |page:, server:, **|
        page.evaluate_on_new_document('() => { globalThis.injected = 123; }')
        page.goto("#{server.prefix}/tamperable.html")
        expect(page.evaluate('() => globalThis.result')).to eq(123)
      end
    end

    it 'should work with CSP' do
      with_test_state do |page:, server:, **|
        server.set_csp('/empty.html', "script-src #{server.prefix}")
        page.evaluate_on_new_document('() => { globalThis.injected = 123; }')
        page.goto("#{server.prefix}/empty.html")
        expect(page.evaluate('() => globalThis.injected')).to eq(123)

        begin
          page.add_script_tag(content: 'window.e = 10;')
        rescue
        end
        expect(page.evaluate('() => window.e')).to be_nil
      end
    end
  end

  describe 'Page.removeScriptToEvaluateOnNewDocument' do
    it 'should remove new document script' do
      with_test_state do |page:, server:, **|
        identifier = page.evaluate_on_new_document('() => { globalThis.injected = 123; }')['identifier']
        page.goto("#{server.prefix}/tamperable.html")
        expect(page.evaluate('() => globalThis.result')).to eq(123)

        page.remove_script_to_evaluate_on_new_document(identifier)
        page.reload
        expect(page.evaluate('() => globalThis.result || null')).to be_nil
      end
    end
  end

  describe 'Frame.evaluate' do
    it 'should have different execution contexts' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        attach_frame(page, 'frame1', server.empty_page)
        expect(page.frames.length).to eq(2)
        page.frames[0].evaluate('() => (globalThis.FOO = "foo")')
        page.frames[1].evaluate('() => (globalThis.FOO = "bar")')
        expect(page.frames[0].evaluate('() => globalThis.FOO')).to eq('foo')
        expect(page.frames[1].evaluate('() => globalThis.FOO')).to eq('bar')
      end
    end

    it 'should have correct execution contexts' do
      with_test_state do |page:, server:, **|
        page.goto("#{server.prefix}/frames/one-frame.html")
        expect(page.frames.length).to eq(2)
        expect(page.frames[0].evaluate('() => document.body.textContent.trim()')).to eq('')
        expect(page.frames[1].evaluate('() => document.body.textContent.trim()')).to eq("Hi, I'm frame")
      end
    end

    it 'should execute after cross-site navigation' do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        main_frame = page.main_frame
        expect(main_frame.evaluate('() => window.location.href')).to include('localhost')
        page.goto("#{server.cross_process_prefix}/empty.html")
        expect(main_frame.evaluate('() => window.location.href')).to include('127')
      end
    end
  end
end
