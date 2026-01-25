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

  describe 'request interception' do
    it 'does not block when requestPaused arrives before requestWillBeSent' do
      allow(frame_manager).to receive(:frame).and_return(nil)
      allow(client).to receive(:send_message)
      instance.request_interception = true

      started = Async::Promise.new
      gate = Async::Promise.new
      finished = Async::Promise.new

      instance.add_event_listener(NetworkManagerEmittedEvents::Request) do |request|
        request.enqueue_intercept_action(lambda do
          started.resolve(true) unless started.resolved?
          gate.wait
          request.continue
          finished.resolve(true) unless finished.resolved?
        end)
      end

      network_request_id = 'request-1'
      fetch_request_id = 'fetch-1'
      request_url = 'http://example.test/one.png'

      request_paused_event = {
        'requestId' => fetch_request_id,
        'networkId' => network_request_id,
        'request' => {
          'url' => request_url,
          'method' => 'GET',
          'headers' => {},
        },
        'resourceType' => 'Image',
      }

      request_will_be_sent_event = {
        'requestId' => network_request_id,
        'loaderId' => network_request_id,
        'request' => {
          'url' => request_url,
          'method' => 'GET',
          'headers' => {},
        },
        'type' => 'Image',
        'initiator' => {},
      }

      instance.instance_variable_get(:@network_event_manager)
              .store_request_paused(network_request_id, request_paused_event)

      Async do
        Puppeteer::AsyncUtils.async_timeout(100, -> {
          instance.send(:handle_request_will_be_sent, request_will_be_sent_event, client)
        }).wait

        Puppeteer::AsyncUtils.async_timeout(1000, started).wait
        expect(finished.resolved?).to eq(false)

        gate.resolve(true)
        Puppeteer::AsyncUtils.async_timeout(1000, finished).wait
      end.wait
    end
  end
end
