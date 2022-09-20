require 'spec_helper'
require 'securerandom'

RSpec.describe Puppeteer::ElementHandle do
  describe Puppeteer::ElementHandle::Point do
    describe '.new' do
      subject { Puppeteer::ElementHandle::Point.new(x: 3, y: 4) }

      it {
        expect(subject.x).to eq(3)
        expect(subject.y).to eq(4)
      }
    end

    describe '/' do
      subject { Puppeteer::ElementHandle::Point.new(x: 8, y: 10) / 2 }

      it {
        expect(subject.x).to eq(4)
        expect(subject.y).to eq(5)
      }
    end

    describe '+' do
      subject { Puppeteer::ElementHandle::Point.new(x: 16, y: 10) + Puppeteer::ElementHandle::Point.new(x: 3, y: 9) }

      it {
        expect(subject.x).to eq(19)
        expect(subject.y).to eq(19)
      }
    end

    describe '==' do
      subject { Puppeteer::ElementHandle::Point.new(x: 3, y: 4) }

      it { is_expected.to eq({ x: 3, y: 4 }) }
      it { is_expected.to eq(Puppeteer::ElementHandle::Point.new(x: 3, y: 4)) }
    end
  end

  describe 'tap' do
    let(:handle) {
      Puppeteer::ElementHandle.new(
        context: double(Puppeteer::ExecutionContext),
        client: double(Puppeteer::CDPSession),
        remote_object: double(Puppeteer::RemoteObject),
        frame: double(Puppeteer::Frame,
          page: double(Puppeteer::Page),
          frame_manager: double(Puppeteer::FrameManager),
        ),
      )
    }

    context 'called with block' do
      let(:something) { double }
      subject { handle.tap { |x| something.awesome(x) } }

      it 'does not call TouchScreen#tap' do
        allow(something).to receive(:awesome)
        expect(handle).not_to receive(:scroll_into_view_if_needed)
        subject
      end

      it "behaves as Ruby's #tap method" do
        expect(something).to receive(:awesome).with(be_a(Puppeteer::ElementHandle))
        subject
      end
    end
  end
end
