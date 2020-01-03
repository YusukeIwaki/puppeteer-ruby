require 'spec_helper'

RSpec.describe Puppeteer::IfPresent do
  describe '#if_present' do
    include Puppeteer::IfPresent

    context 'when target is nil' do
      it 'returns nil' do
        expect(if_present(nil) { |x| 1 }).to be_nil
      end

      it "doesn't evaluate the given block" do
        dummy = double(:dummy)
        expect(dummy).not_to receive(:called)

        if_present(nil) { |x| dummy.called }
      end
    end

    context 'when target is not nil' do
      it 'returns the result of the given block evalated with the target' do
        expect(if_present("") { |s| "hoge" }).to eq("hoge")
        expect(if_present(false) { |b| true }).to eq(true)
        expect(if_present(0) { |z| 100 }).to eq(100)
      end
    end
  end
end
