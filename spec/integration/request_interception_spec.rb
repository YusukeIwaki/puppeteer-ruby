require 'spec_helper'

RSpec.describe 'request interception' do
  include_context 'with test state'
  it 'should intercept', sinatra: true do
    page.request_interception = true

    page.on('request') do |request|
      if request.url.include?('favicon.ico')
        request.continue
        next
      end

      expect(request.url).to include('/empty.html')
      expect(request.headers['user-agent']).not_to be_nil
      expect(request.headers['accept']).not_to be_nil
      expect(request.method).to eq('GET')
      expect(request.post_data).to be_nil
      expect(request.navigation_request?).to eq(true)
      expect(request.resource_type).to eq('document')

      request.continue
    end
    response = page.goto(server_empty_page)
    expect(response.ok?).to eq(true)
  end

  it 'should indicate alreay-handled if an intercept has been handled', sinatra: true do
    page.request_interception = true
    page.on('request', &:continue)
    page.on('request') do |request|
      expect(request.intercept_resolution_handled?).to eq(true)
    end
    page.on('request') do |request|
      expect(request.intercept_resolution_state.action).to eq('already-handled')
    end

    page.goto(server_empty_page)
  end

  it 'should allow mocking multiple headers with same key', sinatra: true do
    page.request_interception = true
    page.on('request') do |request|
      request.respond(
        status: 200,
        headers: {
          foo: 'bar',
          arr: ['1', '2'],
          'set-cookie': ['first=1', 'second=2'],
        },
        body: 'Hello world',
      )
    end

    response = page.goto(server_empty_page)
    cookies = page.cookies
    first_cookie = cookies.find { |cookie| cookie['name'] == 'first' }
    second_cookie = cookies.find { |cookie| cookie['name'] == 'second' }

    expect(response.status).to eq(200)
    expect(response.headers['foo']).to eq('bar')
    expect(response.headers['arr']).to eq("1\n2")
    # request.respond() will not trigger Network.responseReceivedExtraInfo
    # fail to get 'set-cookie' header from response
    expect(first_cookie['value']).to eq('1')
    expect(second_cookie['value']).to eq('2')
  end
end

# https://github.com/puppeteer/puppeteer/blob/e2e98376b9a3fa9a2501ddc86ff6407f3b59887d/docs/api.md#cooperative-intercept-mode-and-legacy-intercept-mode
RSpec.describe 'request interception example' do
  example 'Legacy Mode prevails and the request is aborted', sinatra: true do
    # In this example, Legacy Mode prevails and the request is aborted immediately
    # because at least one handler omits priority when resolving the intercept:

    # Final outcome: immediate abort()
    page.request_interception = true
    page.on('request') do |request|
      # Legacy Mode: interception is aborted immediately.
      request.abort(error_code: 'failed')
    end
    page.on('request') do |request|
      # ['already-handled'], meaning a legacy resolution has taken place
      expect(request.intercept_resolution_state.action).to eq('already-handled')

      # Cooperative Mode: votes for continue at priority 0.
      # Ultimately throws an exception after all handlers have finished
      # running and Cooperative Mode resolutions are evaluated becasue
      # abort() was called using Legacy Mode.
      request.continue(priority: 0)
    end

    expect { page.goto(server_empty_page) }.to raise_error(/net::ERR_FAILED/)
  end

  example 'Legacy Mode prevails and the request is continued', sinatra: true do
    # In this example, Legacy Mode prevails and the request is continued
    # because at least one handler does not specify a priority:

    # Final outcome: immediate continue()
    page.request_interception = true
    page.on('request') do |request|
      # Cooperative Mode: votes to abort at priority 0.
      # Ultimately throws an exception after all handlers have finished
      # running and Cooperative Mode resolutions are evaluated becasue
      # continue() was called using Legacy Mode.
      request.abort(error_code: 'failed', priority: 0)
    end
    page.on('request') do |request|
      # ['abort', 0], meaning an abort @ 0 is the current winning resolution
      expect(request.intercept_resolution_state.action).to eq('abort')
      expect(request.intercept_resolution_state.priority).to eq(0)

      # Legacy Mode: intercept continues immediately.
      request.continue
    end

    expect(page.goto(server_empty_page)).to be_a(Puppeteer::HTTPResponse)
  end

  example 'Cooperative Mode is active #1', sinatra: true do
    # In this example, Cooperative Mode is active
    # because all handlers specify a priority.
    # continue() wins because it has a higher priority than abort().

    # Final outcome: cooperative continue() @ 5
    page.request_interception = true
    page.on('request') do |request|
      # Cooperative Mode: votes to abort at priority 0
      request.abort(error_code: 'failed', priority: 0)
    end
    page.on('request') do |request|
      # Cooperative Mode: votes to continue at priority 5
      params = request.continue_request_overrides
      params[:priority] = 5
      request.continue(**params)
    end
    page.on('request') do |request|
      # ['continue', 5], because continue @ 5 > abort @ 0
      expect(request.intercept_resolution_state.action).to eq('continue')
      expect(request.intercept_resolution_state.priority).to eq(5)

      request.continue
    end

    expect(page.goto(server_empty_page)).to be_a(Puppeteer::HTTPResponse)
  end

  example 'Cooperative Mode is active #2', sinatra: true do
    # In this example, Cooperative Mode is active
    # because all handlers specify priority.
    # respond() wins because its priority ties with continue(), but respond() beats continue().

    # Final outcome: cooperative continue() @ 5
    page.request_interception = true
    page.on('request') do |request|
      # Cooperative Mode: votes to abort at priority 10
      request.abort(error_code: 'failed', priority: 10)
    end
    page.on('request') do |request|
      # Cooperative Mode: votes to continue at priority 15
      params = request.continue_request_overrides
      params[:priority] = 15
      request.continue(**params)
    end
    page.on('request') do |request|
      # Cooperative Mode: votes to respond at priority 15
      params = request.response_for_request || {}
      params[:priority] = 15
      request.respond(**params)
    end
    page.on('request') do |request|
      # Cooperative Mode: votes to respond at priority 15
      params = request.response_for_request || {}
      params[:priority] = 12
      request.respond(**params)
    end
    page.on('request') do |request|
      # ['continue', 5], because continue @ 5 > abort @ 0
      expect(request.intercept_resolution_state.action).to eq('respond')
      expect(request.intercept_resolution_state.priority).to eq(15)

      request.continue
    end

    expect(page.goto(server_empty_page)).to be_a(Puppeteer::HTTPResponse)
  end
end
