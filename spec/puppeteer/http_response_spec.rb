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

  it 'should give single-line header value unchanged' do
    response = build_response({
      'content-type' => 'application/json; charset=utf-8',
    })

    expect(response.headers['content-type']).to eq('application/json; charset=utf-8')
  end

  it 'should normalize multiline header with newlines' do
    response = build_response({
      'content-type' => "text/html;\n charset=utf-8;\n boundary=something",
    })

    expect(response.headers['content-type']).to eq(
      'text/html;, charset=utf-8;, boundary=something',
    )
  end

  it 'should trim whitespace from each line' do
    response = build_response({
      'content-type' => "text/html; \n  charset=utf-8  \n   boundary=something   ",
    })

    expect(response.headers['content-type']).to eq(
      'text/html;, charset=utf-8, boundary=something',
    )
  end

  it 'should filter out empty lines' do
    response = build_response({
      'content-type' => "text/html;\n\n charset=utf-8;\n\n\n boundary=something",
    })

    expect(response.headers['content-type']).to eq(
      'text/html;, charset=utf-8;, boundary=something',
    )
  end

  it 'should normalize set-cookie with newlines' do
    response = build_response({
      'set-cookie' => "a=b\n c=d",
    })

    expect(response.headers['set-cookie']).to eq("a=b\n c=d")
  end
end
