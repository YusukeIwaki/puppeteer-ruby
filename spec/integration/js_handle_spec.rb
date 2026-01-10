require 'spec_helper'

RSpec.describe Puppeteer::JSHandle do
  describe 'Page.evaluateHandle' do
    it 'should work' do
      with_test_state do |page:, **|
        window_handle = page.evaluate_handle('() => window')
        expect(window_handle).to be_a(Puppeteer::JSHandle)
        window_handle.dispose
      end
    end

    it 'should return the RemoteObject' do
      with_test_state do |page:, **|
        window_handle = page.evaluate_handle('() => window')
        expect(window_handle.remote_object).to be_a(Puppeteer::RemoteObject)
        window_handle.dispose
      end
    end

    it 'should accept object handle as an argument' do
      with_test_state do |page:, **|
        navigator_handle = page.evaluate_handle('() => navigator')
        text = page.evaluate('(e) => e.userAgent', navigator_handle)
        expect(text).to include('Mozilla')
        navigator_handle.dispose
      end
    end

    it 'should accept object handle to primitive types' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('() => 5')
        is_five = page.evaluate('(e) => Object.is(e, 5)', handle)
        expect(is_five).to eq(true)
        handle.dispose
      end
    end

    it 'should warn about recursive objects' do
      with_test_state do |page:, **|
        test = {}
        test['obj'] = test
        expect { page.evaluate_handle('(opts) => opts', test) }.to raise_error(/Recursive objects are not allowed\./)
      end
    end

    it 'should accept object handle to unserializable value' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('() => Infinity')
        is_infinity = page.evaluate('(e) => Object.is(e, Infinity)', handle)
        expect(is_infinity).to eq(true)
        handle.dispose
      end
    end

    it 'should use the same JS wrappers' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle(<<~JAVASCRIPT)
        () => {
          globalThis.FOO = 123;
          return window;
        }
        JAVASCRIPT
        expect(page.evaluate('(e) => e.FOO', handle)).to eq(123)
        handle.dispose
      end
    end
  end

  describe 'JSHandle.getProperty' do
    it 'should work' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('() => ({ one: 1, two: 2, three: 3 })')
        two_handle = handle.property('two')
        expect(two_handle.json_value).to eq(2)
        two_handle.dispose
        handle.dispose
      end
    end
  end

  describe 'JSHandle.jsonValue' do
    it 'should work' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle("() => ({ foo: 'bar' })")
        json = handle.json_value
        expect(json).to eq({ 'foo' => 'bar' })
        handle.dispose
      end
    end

    it 'works with jsonValues that are not objects' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('() => ["a", "b"]')
        json = handle.json_value
        expect(json).to eq(['a', 'b'])
        handle.dispose
      end
    end

    it 'works with jsonValues that are primitives' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle("() => 'foo'")
        expect(handle.json_value).to eq('foo')
        handle.dispose

        undefined_handle = page.evaluate_handle('() => undefined')
        expect(undefined_handle.json_value).to be_nil
        undefined_handle.dispose
      end
    end

    it 'should work with dates' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle("() => new Date('2017-09-26T00:00:00.000Z')")
        date = handle.json_value
        expect(date).to be_a(Time)
        expect(date.iso8601(3)).to eq('2017-09-26T00:00:00.000Z')
        handle.dispose
      end
    end

    it 'should not throw for circular objects' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle(<<~JAVASCRIPT)
        () => {
          const t = {g: 1};
          t.t = t;
          return t;
        }
        JAVASCRIPT
        expect { handle.json_value }.not_to raise_error
        handle.dispose
      end
    end
  end

  describe 'JSHandle.getProperties' do
    it 'should work' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle("() => ({ foo: 'bar' })")
        properties = handle.properties
        foo = properties['foo']
        expect(foo).to be_a(Puppeteer::JSHandle)
        expect(foo.json_value).to eq('bar')
        properties.each_value(&:dispose)
        handle.dispose
      end
    end

    it 'should return even non-own properties' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle(<<~JAVASCRIPT)
        () => {
          class A {
            constructor() {
              this.a = '1';
            }
          }
          class B extends A {
            constructor() {
              super();
              this.b = '2';
            }
          }
          return new B();
        }
        JAVASCRIPT
        properties = handle.properties
        expect(properties['a'].json_value).to eq('1')
        expect(properties['b'].json_value).to eq('2')
        properties.each_value(&:dispose)
        handle.dispose
      end
    end
  end

  describe 'JSHandle.asElement' do
    it 'should work' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('() => document.body')
        element = handle.as_element
        expect(element).to be_a(Puppeteer::ElementHandle)
        element.dispose
      end
    end

    it 'should return null for non-elements' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('() => 2')
        element = handle.as_element
        expect(element).to be_nil
        handle.dispose
      end
    end

    it 'should return ElementHandle for TextNodes' do
      with_test_state do |page:, **|
        page.set_content('<div>ee!</div>')
        handle = page.evaluate_handle("() => document.querySelector('div').firstChild")
        element = handle.as_element
        expect(element).to be_a(Puppeteer::ElementHandle)
        is_text = page.evaluate('(e) => e && e.nodeType === Node.TEXT_NODE', element)
        expect(is_text).to eq(true)
        element.dispose
      end
    end
  end

  describe 'JSHandle.toString' do
    it 'should work for primitives' do
      with_test_state do |page:, **|
        number_handle = page.evaluate_handle('() => 2')
        expect(number_handle.to_s).to eq('JSHandle:2')
        number_handle.dispose

        string_handle = page.evaluate_handle("() => 'a'")
        expect(string_handle.to_s).to eq('JSHandle:a')
        string_handle.dispose
      end
    end

    it 'should work for complicated objects' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('() => window')
        expect(handle.to_s).to(eq('JSHandle@window').or(eq('JSHandle@object')))
        handle.dispose
      end
    end

    it 'should work with different subtypes' do
      with_test_state do |page:, **|
        [
          ['(function(){})', 'JSHandle@function'],
          ['12', 'JSHandle:12'],
          ['true', 'JSHandle:true'],
          ['undefined', 'JSHandle:undefined'],
          ['"foo"', 'JSHandle:foo'],
          ['Symbol()', 'JSHandle@symbol'],
          ['new Map()', 'JSHandle@map'],
          ['new Set()', 'JSHandle@set'],
          ['[]', 'JSHandle@array'],
          ['null', 'JSHandle:null'],
          ['/foo/', 'JSHandle@regexp'],
          ['document.body', 'JSHandle@node'],
          ['new Date()', 'JSHandle@date'],
          ['new WeakMap()', 'JSHandle@weakmap'],
          ['new WeakSet()', 'JSHandle@weakset'],
          ['new Error()', 'JSHandle@error'],
          ['new Int32Array()', 'JSHandle@typedarray'],
          ['new Proxy({}, {})', 'JSHandle@proxy'],
        ].each do |expression, expected|
          handle = page.evaluate_handle(expression)
          expect(handle.to_s).to eq(expected)
          handle.dispose
        end
      end
    end

    it 'should work with window subtypes' do
      with_test_state do |page:, **|
        window_handle = page.evaluate_handle('window')
        expect(window_handle.to_s).to eq('JSHandle@window')
        window_handle.dispose

        global_handle = page.evaluate_handle('globalThis')
        expect(global_handle.to_s).to eq('JSHandle@window')
        global_handle.dispose
      end
    end
  end

  describe 'JSHandle[Symbol.dispose]' do
    it 'should work' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('new Set()')
        expect(handle).to be_a(Puppeteer::JSHandle)
        handle.dispose_symbol
        expect(handle.disposed?).to eq(true)
      end
    end
  end

  describe 'JSHandle[Symbol.asyncDispose]' do
    it 'should work' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('new Set()')
        expect(handle).to be_a(Puppeteer::JSHandle)
        handle.async_dispose_symbol.wait
        expect(handle.disposed?).to eq(true)
      end
    end
  end

  describe 'JSHandle.move' do
    it 'should work' do
      with_test_state do |page:, **|
        handle = page.evaluate_handle('new Set()')
        handle.move
        handle.dispose_symbol
        expect(handle).to be_a(Puppeteer::JSHandle)
        expect(handle.disposed?).to eq(false)
        handle.dispose
      end
    end
  end
end
