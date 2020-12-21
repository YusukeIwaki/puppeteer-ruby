require 'spec_helper'

RSpec.describe Puppeteer::Page::ScreenshotOptions do
  describe 'quality' do
    let(:instance) { Puppeteer::Page::ScreenshotOptions.new(options) }
    subject { instance.quality }

    context 'when not specified' do
      let(:options) { {} }
      it { is_expected.to be_nil }
    end

    context 'when quality=0 is specified' do
      let(:options) { { type: 'jpeg', quality: 0 } }
      it { is_expected.to eq(0) }
    end

    context 'when quality=100 is specified' do
      let(:options) { { type: 'jpeg', quality: 100 } }
      it { is_expected.to eq(100) }
    end
  end
end
