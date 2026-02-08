require 'spec_helper'

RSpec.describe 'network (white-box / Ruby-specific)' do
  it 'should throw for non UTF-8 response body' do
    with_test_state do |page:, server:, **|
      server.set_route('/binary-response') do |_request, writer|
        writer.add_header('Content-Type', 'application/octet-stream')
        writer.write("\xFF\xFE\xFA".b)
        writer.finish
      end

      response_promise = async_promise do
        page.wait_for_response(predicate: ->(response) { response.url.end_with?('/binary-response') })
      end
      page.goto(server.empty_page)
      page.evaluate("() => fetch('/binary-response')")
      response = response_promise.wait

      expect {
        response.text
      }.to raise_error(Puppeteer::Error, 'Could not decode response body as UTF-8')
    end
  end
end
