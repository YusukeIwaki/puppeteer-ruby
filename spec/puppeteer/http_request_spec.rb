require 'base64'
require 'spec_helper'

RSpec.describe Puppeteer::HTTPRequest do
  describe '#post_data' do
    let(:client) { instance_double(Puppeteer::CDPSession) }

    it 'decodes postDataEntries bytes when available' do
      event = {
        'requestId' => 'request-id',
        'loaderId' => 'request-id',
        'type' => 'Document',
        'request' => {
          'url' => 'https://example.test',
          'method' => 'POST',
          'postDataEntries' => [
            { 'bytes' => Base64.strict_encode64('{"foo":') },
            { 'bytes' => Base64.strict_encode64('"bar"}') },
          ],
        },
      }

      request = described_class.new(client, nil, nil, false, event, [])
      expect(request.post_data).to eq('{"foo":"bar"}')
      expect(request.has_post_data?).to eq(true)
    end

    it 'falls back to request.postData when postDataEntries is not provided' do
      event = {
        'requestId' => 'request-id',
        'loaderId' => 'request-id',
        'type' => 'Document',
        'request' => {
          'url' => 'https://example.test',
          'method' => 'POST',
          'postData' => '{"foo":"bar"}',
        },
      }

      request = described_class.new(client, nil, nil, false, event, [])
      expect(request.post_data).to eq('{"foo":"bar"}')
      expect(request.has_post_data?).to eq(true)
    end
  end
end
