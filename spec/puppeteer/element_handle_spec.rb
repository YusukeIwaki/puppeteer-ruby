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
      subject { Puppeteer::ElementHandle::Point.new(x: 8, y:10) / 2 }

      it {
        expect(subject.x).to eq(4)
        expect(subject.y).to eq(5)
      }
    end

    describe '+' do
      subject { Puppeteer::ElementHandle::Point.new(x: 16, y:10) + Puppeteer::ElementHandle::Point.new(x: 3, y:9) }

      it {
        expect(subject.x).to eq(19)
        expect(subject.y).to eq(19)
      }
    end
  end
end
