class Puppeteer::NetworkManager
  include Puppeteer::DebugPrint
  include Puppeteer::EventCallbackable
  include Puppeteer::IfPresent

  class Credentials
    # @param username [String|NilClass]
    # @param password [String|NilClass]
    def initialize(username:, password:)
      @username = username
      @password = password
    end
    attr_reader :username, :password
  end

  # @param {!Puppeteer.CDPSession} client
  # @param {boolean} ignoreHTTPSErrors
  # @param {!Puppeteer.FrameManager} frameManager
  def initialize(client, ignore_https_errors, frame_manager)
    @client = client
    @ignore_https_errors = ignore_https_errors
    @frame_manager = frame_manager

    # @type {!Map<string, !Request>}
    @request_id_to_request = {}

    # @type {!Map<string, !Protocol.Network.requestWillBeSentPayload>}
    @request_id_to_request_with_be_sent_event = {}

    @extra_http_headers = {}

    @offline = false

    @attempted_authentications = Set.new
    @user_request_interception_enabled = false
    @protocol_request_interception_enabled = false
    @user_cache_disabled = false
    @request_id_to_interception_id = {}

    @client.on_event('Fetch.requestPaused') do |event|
      handle_request_paused(event)
    end
    @client.on_event('Fetch.authRequired') do |event|
      handle_auth_required(event)
    end
    @client.on_event('Network.requestWillBeSent') do |event|
      handle_request_will_be_sent(event)
    end
    @client.on_event('Network.requestServedFromCache') do |event|
      handle_request_served_from_cache(event)
    end
    @client.on_event('Network.responseReceived') do |event|
      handle_response_received(event)
    end
    @client.on_event('Network.loadingFinished') do |event|
      handle_loading_finished(event)
    end
    @client.on_event('Network.loadingFailed') do |event|
      handle_loading_failed(event)
    end
  end

  def init
    @client.send_message('Network.enable')
    if @ignore_https_errors
      @client.send_message('Security.setIgnoreCertificateErrors', ignore: true)
    end
  end

  # @param username [String|NilClass]
  # @param password [String|NilClass]
  def authenticate(username:, password:)
    @credentials = Credentials.new(username: username, password: password)
    update_protocol_request_interception
  end

  # @param {!Object<string, string>} extraHTTPHeaders
  def extra_http_headers=(headers)
    new_extra_http_headers = {}
    headers.each do |key, value|
      unless value.is_a?(String)
        raise ArgumentError.new("Expected value of header \"#{key}\" to be String, but \"#{value}\" is found.")
      end
      new_extra_http_headers[key.downcase] = value
    end
    @extra_http_headers = new_extra_http_headers
    @client.send_message('Network.setExtraHTTPHeaders', headers: new_extra_http_headers)
  end

  # @return {!Object<string, string>}
  def extra_http_headers
    @extra_http_headers.dup
  end

  # @param value [TrueClass|FalseClass]
  def offline_mode=(value)
    return if @offline == value
    @offline = value
    @client.send_message('Network.emulateNetworkConditions',
      offline: @offline,
      # values of 0 remove any active throttling. crbug.com/456324#c9
      latency: 0,
      downloadThroughput: -1,
      uploadThroughput: -1,
    )
  end

  # @param user_agent [String]
  def user_agent=(user_agent)
    @client.send_message('Network.setUserAgentOverride', userAgent: user_agent)
  end

  def cache_enabled=(enabled)
    @user_cache_disabled = !enabled
    update_protocol_cache_disabled
  end

  def request_interception=(enabled)
    @user_request_interception_enabled = enabled
    update_protocol_request_interception
  end

  private def update_protocol_request_interception
    enabled = @user_request_interception_enabled || !@credentials.nil?
    return if @protocol_request_interception_enabled == enabled
    @protocol_request_interception_enabled = enabled

    if enabled
      update_protocol_cache_disabled
      @client.send_message('Fetch.enable',
        handleAuthRequests: true,
        patterns: [{ urlPattern: '*' }],
      )
    else
      update_protocol_cache_disabled
      @client.async_send_message('Fetch.disable')
    end
  end

  private def update_protocol_cache_disabled
    cache_disabled = @user_cache_disabled || @protocol_request_interception_enabled
    @client.send_message('Network.setCacheDisabled', cacheDisabled: cache_disabled)
  end

  private def handle_request_will_be_sent(event)
    # Request interception doesn't happen for data URLs with Network Service.
    if @protocol_request_interception_enabled && !event['request']['url'].start_with?('data:')
      request_id = event['requestId']
      interception_id = @request_id_to_interception_id.delete(request_id)
      if interception_id
        handle_request(event, interception_id)
      else
        @request_id_to_request_with_be_sent_event[request_id] = event
      end
      return
    end
    handle_request(event, nil)
  end

  private def handle_auth_required(event)
    response = 'Default'
    if @attempted_authentications.include?(event['requestId'])
      response = 'CancelAuth'
    elsif @credentials
      response = 'ProvideCredentials'
      @attempted_authentications << event['requestId']
    end

    username = @credentials&.username
    password = @credentials&.password

    begin
      @client.send_message('Fetch.continueWithAuth',
        requestId: event['requestId'],
        authChallengeResponse: {
          response: response,
          username: username,
          password: password,
        },
      )
    rescue => err
      debug_puts(err)
    end
  end

  private def handle_request_paused(event)
    if !@user_request_interception_enabled && @protocol_request_interception_enabled
      begin
        @client.send_message('Fetch.continueRequest', requestId: event['requestId'])
      rescue => err
        debug_puts(err)
      end
    end

    request_id = event['networkId']
    interception_id = event['requestId']
    if request_id && (request_will_be_sent_event = @request_id_to_request_with_be_sent_event.delete(request_id))
      handle_request(request_will_be_sent_event, interception_id)
    else
      @request_id_to_interception_id[request_id] = interception_id
    end
  end

  private def handle_request(event, interception_id)
    redirect_chain = []
    if event['redirectResponse']
      if_present(@request_id_to_request[event['requestId']]) do |request|
        handle_request_redirect(request, event['redirectResponse'])
        redirect_chain = request.internal.redirect_chain
      end
    end
    frame = if_present(event['frameId']) { |frame_id| @frame_manager.frame(frame_id) }
    request = Puppeteer::Request.new(@client, frame, interception_id, @user_request_interception_enabled, event, redirect_chain)
    @request_id_to_request[event['requestId']] = request
    emit_event('Events.NetworkManager.Request', request)
  end

  private def handle_request_served_from_cache(event)
    if_present(@request_id_to_request[event['requestId']]) do |request|
      request.internal.from_memory_cache = true
    end
  end

  # @param request [Puppeteer::Request]
  # @param response_payload [Hash]
  private def handle_request_redirect(request, response_payload)
    response = Puppeteer::Response.new(@client, request, response_payload)
    request.internal.response = response
    request.internal.redirect_chain << request
    response.internal.body_loaded_promise.reject(Puppeteer::Response::Redirected.new)
    @request_id_to_request.delete(request.internal.request_id)
    @attempted_authentications.delete(request.internal.interception_id)
    emit_event('Events.NetworkManager.Response', response)
    emit_event('Events.NetworkManager.RequestFinished', request)
  end

  # @param event [Hash]
  private def handle_response_received(event)
    request = @request_id_to_request[event['requestId']]
    # FileUpload sends a response without a matching request.
    return unless request

    response = Puppeteer::Response.new(@client, request, event['response'])
    request.internal.response = response
    emit_event('Events.NetworkManager.Response', response)
  end

  private def handle_loading_finished(event)
    request = @request_id_to_request[event['requestId']]
    # For certain requestIds we never receive requestWillBeSent event.
    # @see https://crbug.com/750469
    return unless request


    # Under certain conditions we never get the Network.responseReceived
    # event from protocol. @see https://crbug.com/883475
    if_present(request.response) do |response|
      response.internal.body_loaded_promise.fulfill(nil)
    end

    @request_id_to_request.delete(request.internal.request_id)
    @attempted_authentications.delete(request.internal.interception_id)
    emit_event('Events.NetworkManager.RequestFinished', request)
  end

  private def handle_loading_failed(event)
    request = @request_id_to_request[event['requestId']]
    # For certain requestIds we never receive requestWillBeSent event.
    # @see https://crbug.com/750469
    return unless request

    request.internal.failure_text = event['errorText']
    if_present(request.response) do |response|
      response.internal.body_loaded_promise.fulfill(nil)
    end
    @request_id_to_request.delete(request.internal.request_id)
    @attempted_authentications.delete(request.internal.interception_id)
    emit_event('Events.NetworkManager.RequestFailed', request)
  end
end
