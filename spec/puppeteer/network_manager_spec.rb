require 'spec_helper'

RSpec.describe Puppeteer::NetworkManager do
  let(:client) { double(Puppeteer::CDPSession).as_null_object }
  let(:frame_manager) { double(Puppeteer::FrameManager).as_null_object }
  let(:instance) { described_class.new(client, false, frame_manager) }

  describe 'extra_http_headers' do
    subject { instance.extra_http_headers = headers }

    context 'when setting non-string values' do
      let(:headers) { { 'My-Header' => ['Puppeteer', Puppeteer::VERSION] } }
      it { expect { subject }.to raise_error(ArgumentError) }
    end

    context 'when setting valid hash' do
      before do
        instance.extra_http_headers = { 'custom-key' => 'custom-value' }
      end

      let(:headers) { { 'My-Header' => 'Puppeteer 1' } }

      it 'updates extra_http_headers' do
        subject
        expect(instance.extra_http_headers).not_to have_key('custom-key')
        expect(instance.extra_http_headers['my-header']).to eq('Puppeteer 1')
      end
    end

    context 'Updating headers with getter and setter' do
      before do
        instance.extra_http_headers = { 'custom-key' => 'custom-value' }
      end

      let(:headers) { instance.extra_http_headers }

      context 'when new header contains non-string values' do
        before do
          headers['custom-key'] = ['Puppeteer', Puppeteer::VERSION]
        end

        it 'keeps original extra_http_headers' do
          expect { subject }.to raise_error(ArgumentError)
          expect(instance.extra_http_headers['custom-key']).to eq('custom-value')
        end
      end

      context 'with new header' do
        before do
          headers['New-custom-key'] = 'new-custom-value'
        end

        it 'updates extra_http_headers' do
          subject
          expect(instance.extra_http_headers['custom-key']).to eq('custom-value')
          expect(instance.extra_http_headers['new-custom-key']).to eq('new-custom-value')
        end
      end

      context 'with replacing key' do
        before do
          headers.delete('custom-key')
          headers['New-custom-key'] = 'new-custom-value'
        end

        it 'updates extra_http_headers' do
          subject
          expect(instance.extra_http_headers).not_to have_key('custom-key')
          expect(instance.extra_http_headers['new-custom-key']).to eq('new-custom-value')
        end
      end
    end

    context 'Trying to update with getter' do
      subject { instance.extra_http_headers[new_key] = new_value }

      before do
        instance.extra_http_headers = { 'custom-key' => 'custom-value' }
      end

      let(:new_key) { 'My-Header' }
      let(:new_value) { 'My-Value' }

      it "doesn't update extra_http_headers" do
        expect { subject }.not_to change { instance.extra_http_headers }
      end
    end
  end
end
