require 'spec_helper'

RSpec.describe Puppeteer::JSHandle do
  describe 'Page#evaluate_handle' do
    it 'should work' do
      window_handle = page.evaluate_handle('() => window')
      expect(window_handle).to be_a(Puppeteer::JSHandle)
    end

    it 'should accept object handle as an argument' do
      navigator_handle = page.evaluate_handle('() => navigator')
      text = page.evaluate('(e) => e.userAgent', navigator_handle)
      expect(text).to include('Mozilla')
    end

    it 'should accept object handle to primitive types' do
      handle = page.evaluate_handle('() => 5')
      expect(page.evaluate('(e) => Object.is(e, 5)', handle)).to eq(true)
    end

    it 'should accept object handle to unserializable value' do
      handle = page.evaluate_handle('() => Infinity')
      expect(page.evaluate('(e) => Object.is(e, Infinity)', handle)).to eq(true)
    end

    it 'should use the same JS wrappers / should work with primitives' do
      handle = page.evaluate_handle('() => { globalThis.FOO = 123; return window; }')
      expect(page.evaluate('(e) => e.FOO', handle)).to eq(123)
    end
  end

  describe '#property' do
    it 'should work' do
      handle = page.evaluate_handle('() => ({ one: 1, two: 2, three: 3 })')
      expect(handle['two'].json_value).to eq(2)
      expect(handle.property('two').json_value).to eq(2)
    end
  end

  describe '#json_value' do
    it 'should work' do
      handle = page.evaluate_handle("() => ({ foo: 'bar' })")
      json = handle.json_value
      expect(json).to eq({ 'foo' => 'bar' })
    end

    it 'should not work with dates' do
      date_handle = page.evaluate_handle("() => new Date('2017-09-26T00:00:00.000Z')")
      json = date_handle.json_value
      expect(json).to eq({})
    end

    it 'should throw for circular objects' do
      window_handle = page.evaluate_handle('window')
      expect { window_handle.json_value }.to raise_error(/Object reference chain is too long/)
    end
  end

  describe '#properties' do
    it 'should work' do
      handle = page.evaluate_handle("() => ({ foo: 'bar' })")
      properties = handle.properties
      expect(properties['foo'].json_value).to eq('bar')
    end

    it 'should return even non-own properties' do
      js = <<~JAVASCRIPT
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
      handle = page.evaluate_handle(js)
      properties = handle.properties
      expect(properties['a'].json_value).to eq('1')
      expect(properties['b'].json_value).to eq('2')
    end
  end

  describe '#as_element' do
    it 'should work' do
      handle = page.evaluate_handle("() => document.body")
      element = handle.as_element
      expect(element).to be_a(Puppeteer::ElementHandle)
    end

    it 'should return null for non-elements' do
      handle = page.evaluate_handle('() => 2')
      element = handle.as_element
      expect(element).to be_nil
    end

    it 'should return ElementHandle for TextNodes' do
      page.content = '<div>ee!</div>'
      handle = page.evaluate_handle("() => document.querySelector('div').firstChild")
      element = handle.as_element
      expect(element).to be_a(Puppeteer::ElementHandle)
      expect(page.evaluate("(e) => e.nodeType === Node.TEXT_NODE", element)).to eq(true)
    end
  end

  describe '#to_s' do
    it 'should work for primitives' do
      number_handle = page.evaluate_handle("() => 2")
      expect(number_handle.to_s).to eq("JSHandle:2")

      string_handle = page.evaluate_handle("() => 'a'")
      expect(string_handle.to_s).to eq("JSHandle:a")
    end

    it 'should work for complicated objects' do
      handle = page.evaluate_handle('() => window')
      expect(handle.to_s).to eq('JSHandle@object')
    end

    [
      [:integer, '12', 'JSHandle:12'],
      [:boolean, 'true', 'JSHandle:true'],
      [:undefined, 'undefined', 'JSHandle:undefined'],
      [:string, '"foo"', 'JSHandle:foo'],
      [:symbol, 'Symbol()', 'JSHandle@symbol'],
      [:map, 'new Map()', 'JSHandle@map'],
      [:set, 'new Set()', 'JSHandle@set'],
      [:null, 'null', 'JSHandle:undefined'], # in JS, 'JSHandle:undefined'. But Ruby can't distinguish null from undefined.
      [:regexp, '/foo/', 'JSHandle@regexp'],
      [:weakset, 'new WeakSet()', 'JSHandle@weakset'],
      [:error, 'new Error()', 'JSHandle@error'],
      [:typedarray, 'new Int32Array()', 'JSHandle@typedarray'],
      [:proxy, 'new Proxy({}, {})', 'JSHandle@proxy'],
    ].each do |type, js, expected_string|
      it "should work with different subtypes: [#{type}]" do
        expect(page.evaluate_handle(js).to_s).to eq(expected_string)
      end
    end
  end
end
