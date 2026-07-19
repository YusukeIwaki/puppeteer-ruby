require 'spec_helper'

RSpec.describe Puppeteer::HTTPResponse do
  def build_response(headers)
    request = Struct.new(:url).new('https://example.com')
    response_payload = {
      'remoteIPAddress' => '127.0.0.1',
      'remotePort' => 80,
      'status' => 200,
      'statusText' => 'OK',
      'headers' => headers,
    }
    described_class.new(nil, request, response_payload, nil)
  end

  it 'should normalize set-cookie using \n' do
    response = build_response({
      'set-cookie' => "a=b\n  c=d",
    })

    expect(response.headers['set-cookie']).to eq("a=b\n c=d")
  end

  it 'should normalize other headers using ,' do
    response = build_response({
      'content-type' => "text/html\n  charset=utf-8",
      'accept-language' => "en-US\n en",
    })

    expect(response.headers['content-type']).to eq('text/html, charset=utf-8')
    expect(response.headers['accept-language']).to eq('en-US, en')
  end
end
