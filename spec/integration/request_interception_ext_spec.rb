require 'spec_helper'

RSpec.describe 'request interception example' do
  def skip_interception_example_request?(request, target_url)
    return false if request.url == target_url
    return true if request.url.start_with?('data:')

    request.continue unless request.intercept_resolution_handled?
    true
  end

  it 'Legacy Mode prevails and the request is aborted', sinatra: true do
    with_test_state do |page:, server:, **|
      page.request_interception = true
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        request.abort(error_code: 'failed')
      end
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        expect(request.intercept_resolution_state.action).to eq('already-handled')

        begin
          request.continue(priority: 0)
        rescue Puppeteer::HTTPRequest::AlreadyHandledError
        end
      end

      expect { page.goto(server.empty_page) }.to raise_error(/net::ERR_FAILED/)
    end
  end

  it 'Legacy Mode prevails and the request is continued', sinatra: true do
    with_test_state do |page:, server:, **|
      page.request_interception = true
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        request.abort(error_code: 'failed', priority: 0)
      end
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        expect(request.intercept_resolution_state.action).to eq('abort')
        expect(request.intercept_resolution_state.priority).to eq(0)

        request.continue
      end

      expect(page.goto(server.empty_page)).to be_a(Puppeteer::HTTPResponse)
    end
  end

  it 'Cooperative Mode is active #1', sinatra: true do
    with_test_state do |page:, server:, **|
      page.request_interception = true
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        request.abort(error_code: 'failed', priority: 0)
      end
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        params = request.continue_request_overrides
        params[:priority] = 5
        request.continue(**params)
      end
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        expect(request.intercept_resolution_state.action).to eq('continue')
        expect(request.intercept_resolution_state.priority).to eq(5)

        request.continue
      end

      expect(page.goto(server.empty_page)).to be_a(Puppeteer::HTTPResponse)
    end
  end

  it 'Cooperative Mode is active #2', sinatra: true do
    with_test_state do |page:, server:, **|
      page.request_interception = true
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        request.abort(error_code: 'failed', priority: 10)
      end
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        params = request.continue_request_overrides
        params[:priority] = 15
        request.continue(**params)
      end
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        params = request.response_for_request || {}
        params[:priority] = 15
        request.respond(**params)
      end
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        params = request.response_for_request || {}
        params[:priority] = 12
        request.respond(**params)
      end
      page.on('request') do |request|
        next if skip_interception_example_request?(request, server.empty_page)

        expect(request.intercept_resolution_state.action).to eq('respond')
        expect(request.intercept_resolution_state.priority).to eq(15)

        request.continue
      end

      expect(page.goto(server.empty_page)).to be_a(Puppeteer::HTTPResponse)
    end
  end
end
