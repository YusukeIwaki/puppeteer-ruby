require 'spec_helper'

RSpec.describe Puppeteer::Page::PDFOptions do
  describe 'convert_print_parameter_to_inches' do
    let(:instance) { Puppeteer::Page::PDFOptions.new(options) }
    let(:options) { { path: 'x.pdf' } }
    subject { instance.send(:convert_print_parameter_to_inches, value) }

    context 'value is nil' do
      let(:value) { nil }
      it { is_expected.to be_nil }
    end

    context 'value is number' do
      let(:value) { 10 }
      it { is_expected.to eq(10 / 96.0) }
    end

    context 'value is decimal' do
      let(:value) { 10.5 }
      it { is_expected.to eq(10.5 / 96.0) }
    end

    context 'value is number without unit' do
      let(:value) { "10" }
      it { is_expected.to eq(10 / 96.0) }
    end

    context 'value is number with unit' do
      let(:value) { "10cm" }
      it { is_expected.to eq(10 * 37.8 / 96.0) }
    end

    context 'value is decimal with unit' do
      let(:value) { "10.5cm" }
      it { is_expected.to eq(10.5 * 37.8 / 96.0) }
    end
  end
end
