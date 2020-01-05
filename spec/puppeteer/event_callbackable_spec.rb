require 'spec_helper'

RSpec.describe Puppeteer::EventCallbackable do
  describe 'Simple pub/sub' do
    class Pub
      include Puppeteer::EventCallbackable
    end

    let!(:pub) { Pub.new }
    let!(:sub) { double(:sub) }

    context 'with no parameter' do
      before {
        pub.on_event 'Pub.Event.awesome' do
          sub.awesome
        end
        pub.on_event 'Pub.Event.strange' do
          sub.strange
        end
      }
      it 'receives callback' do
        expect(sub).to receive(:awesome)
        expect(sub).not_to receive(:strange)
        pub.emit_event 'Pub.Event.awesome'
        pub.emit_event 'Pub.Event.strange.strange'
      end
    end

    context 'with parameters' do
      before {
        pub.on_event 'Pub.Event.awesome' do |arg1, arg2|
          sub.awesome(arg1, arg2)
        end
      }

      it 'can receive arguments' do
        expect(sub).to receive(:awesome).with(:error, "none")
        pub.emit_event 'Pub.Event.awesome', :error, "none"
      end
    end

    context 'with keyword parameters' do
      before {
        pub.on_event 'Pub.Event.awesome' do |error: nil|
          if error
            sub.on_error(error)
          else
            sub.awesome
          end
        end
      }

      it 'can receive with keyword arguments' do
        expect(sub).to receive(:on_error).with("not awesome")
        pub.emit_event 'Pub.Event.awesome', error: "not awesome"
      end

      it 'can omit optional keyword arguments' do
        expect(sub).not_to receive(:on_error)
        expect(sub).to receive(:awesome)
        pub.emit_event 'Pub.Event.awesome'
      end
    end
  end

  describe 'Subscription with method reference' do
    class Pub
      include Puppeteer::EventCallbackable
    end

    let!(:pub) { Pub.new }

    context 'with no parameters' do
      class Sub0
        def initialize(pub)
          pub.on_event 'Pub.Event.awesome', &method(:handle_awesome)
        end

        def handle_awesome
          ok
        end

        def ok ; end
      end

      let!(:sub) { Sub0.new(pub) }

      it 'receive callback with no arguments' do
        expect(sub).to receive(:ok)
        pub.emit_event 'Pub.Event.awesome'
      end
    end

    context 'with parameters' do
      class Sub1
        def initialize(pub)
          pub.on_event 'Pub.Event.awesome', &method(:handle_awesome)
        end

        def handle_awesome(arg1, arg2)
          ok(arg1, arg2)
        end

        def ok(arg1, arg2) ; end
      end

      let!(:sub) { Sub1.new(pub) }

      it 'receive callback with arguments' do
        expect(sub).to receive(:ok).with(:error, "none")
        pub.emit_event 'Pub.Event.awesome', :error, "none"
      end
    end

    context 'with keyword parameters' do
      class Sub2
        def initialize(pub)
          pub.on_event 'Pub.Event.awesome', &method(:handle_awesome)
        end

        def handle_awesome(error: nil, reason: nil)
          if error && reason
            ok(error, reason)
          end
        end

        def ok(arg1, arg2) ; end
      end

      let!(:sub) { Sub2.new(pub) }

      it 'receive callback with keyword arguments' do
        expect(sub).to receive(:ok).with(404, "Not Found")
        pub.emit_event 'Pub.Event.awesome', error: 404, reason: "Not Found"
      end
    end
  end

  describe 'Nested pub/sub' do
    class ParentPub
      include Puppeteer::EventCallbackable
    end

    class ChildPub
      include Puppeteer::EventCallbackable

      def initialize(parent)
        @me = 'child'
        parent.on_event 'Parent.awesome' do
          on_parent_awesome
          @me = 'awesome child'
          emit_event 'Child.awesome'
        end

        parent.on_event 'Child.awesome' do
          raise StandardError.new('invalid')
        end
      end

      def on_parent_awesome
      end

      attr_reader :me
    end

    let!(:parent) { ParentPub.new }
    let!(:child) { ChildPub.new(parent) }

    it 'receives callback' do
      expect(child).to receive(:on_parent_awesome)
      expect { parent.emit_event 'Parent.awesome' }.to change { child.me }.from('child').to('awesome child')
    end

    it 'can handle nested callback' do
      called = false
      child.on_event 'Child.awesome' do
        called = true
      end
      expect { parent.emit_event 'Parent.awesome' }.to change { called }.from(false).to(true)
    end
  end

  describe 'add event listeners' do
    class Pub
      include Puppeteer::EventCallbackable
    end

    let!(:pub) { Pub.new }
    let!(:sub1) { double(:sub1) }
    let!(:sub2) { double(:sub2) }
    let!(:sub1_listener) { pub.add_event_listener('Pub.Event.awesome') { sub1.ok } }
    let!(:sub2_listener) { pub.add_event_listener('Pub.Event.awesome') { sub2.yes } }

    it 'notify event callbacks for all listeners' do
      expect(sub1).to receive(:ok)
      expect(sub2).to receive(:yes)
      pub.emit_event 'Pub.Event.awesome'
    end

    context 'after removing a listener' do
      before {
        pub.remove_event_listener(sub1_listener)
      }

      it 'notify event callbacks only for listeners which keep listening' do
        expect(sub1).not_to receive(:ok)
        expect(sub2).to receive(:yes)
        pub.emit_event 'Pub.Event.awesome'
      end
    end
  end
end
