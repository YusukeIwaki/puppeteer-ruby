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

  class InternalNetworkCondition
    attr_writer :offline, :upload, :download, :latency

    def initialize(client)
      @client = client
      @offline = false
      @upload = -1
      @download = -1
      @latency = 0
    end

    def offline_mode=(value)
      return if @offline == value
      @offline = value
      update_network_conditions
    end

    def network_condition=(network_condition)
      if network_condition
        @upload = network_condition.upload
        @download = network_condition.download
        @latency = network_condition.latency
      else
        @upload = -1
        @download = -1
        @latency = 0
      end
      update_network_conditions
    end

    private def update_network_conditions
      @client.send_message('Network.emulateNetworkConditions',
        offline: @offline,
        latency: @latency,
        downloadThroughput: @download,
        uploadThroughput: @upload,
      )
    end
  end

  class RedirectInfo
    def initialize(event:, fetch_request_id:)
      @event = event
      @fetch_request_id = fetch_request_id
    end
    attr_reader :event, :fetch_request_id
  end

  class QueuedEventGroup
    def initialize(response_received_event:)
      @response_received_event = response_received_event
    end
    attr_reader :response_received_event
    attr_accessor :loading_finished_event, :loading_failed_event
  end

  # @param {!Puppeteer.CDPSession} client
  # @param {boolean} ignoreHTTPSErrors
  # @param {!Puppeteer.FrameManager} frameManager
  def initialize(client, ignore_https_errors, frame_manager)
    @client = client
    @ignore_https_errors = ignore_https_errors
    @frame_manager = frame_manager
    @network_event_manager = Puppeteer::NetworkEventManager.new

    @extra_http_headers = {}

    @attempted_authentications = Set.new
    @user_request_interception_enabled = false
    @protocol_request_interception_enabled = false
    @user_cache_disabled = false
    @internal_network_condition = InternalNetworkCondition.new(@client)

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
    @client.on_event('Network.responseReceivedExtraInfo') do |event|
      handle_response_received_extra_info(event)
    end
  end

  def init
    @client.send_message('Network.enable')
    if @ignore_https_errors
      @client.send_message('Security.setIgnoreCertificateErrors', ignore: true)
    end
  end

  def inspect
    values = %i[network_event_manager].map do |sym|
      value = instance_variable_get(:"@#{sym}")
      "@#{sym}=#{value}"
    end
    "#<Puppeteer::HTTPRequest #{values.join(' ')}>"
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

  def num_requests_in_progress
    @network_event_manager.num_requests_in_progress
  end

  # @param value [TrueClass|FalseClass]
  def offline_mode=(value)
    @internal_network_condition.offline_mode=(value)
  end

  # @param network_condition [Puppeteer::NetworkCondition|nil]
  def emulate_network_conditions(network_condition)
    @internal_network_condition.network_condition = network_condition
  end

  # @param user_agent [String]
  # @param user_agent_metadata [Hash]
  def set_user_agent(user_agent, user_agent_metadata = nil)
    @client.send_message('Network.setUserAgentOverride', {
      userAgent: user_agent,
      userAgentMetadata: user_agent_metadata,
    }.compact)
  end
  alias_method :user_agent=, :set_user_agent

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
    if @user_request_interception_enabled && !event['request']['url'].start_with?('data:')
      network_request_id = event['requestId']
      @network_event_manager.store_request_will_be_sent(network_request_id, event)

      # CDP may have sent a Fetch.requestPaused event already. Check for it.
      if_present(@network_event_manager.get_request_paused(network_request_id)) do |request_paused_event|
        fetch_request_id = request_paused_event['requestId']
        handle_request(event, fetch_request_id)
        @network_event_manager.forget_request_paused(network_request_id)
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

    network_request_id = event['networkId']
    fetch_request_id = event['requestId']
    return unless network_request_id

    request_will_be_sent_event = @network_event_manager.get_request_will_be_sent(network_request_id)

    # redirect requests have the same `requestId`
    if request_will_be_sent_event &&
       (request_will_be_sent_event['request']['url'] != event['request']['url'] ||
        request_will_be_sent_event['request']['method'] != event['request']['method'])

      @network_event_manager.forget_request_will_be_sent(network_request_id)
      request_will_be_sent_event = nil
    end

    if request_will_be_sent_event
      handle_request(request_will_be_sent_event, fetch_request_id)
    else
      @network_event_manager.store_request_paused(network_request_id, event)
    end
  end

  private def handle_request(event, fetch_request_id)
    redirect_chain = []
    if event['redirectResponse']
      # We want to emit a response and requestfinished for the
      # redirectResponse, but we can't do so unless we have a
      # responseExtraInfo ready to pair it up with. If we don't have any
      # responseExtraInfos saved in our queue, they we have to wait until
      # the next one to emit response and requestfinished, *and* we should
      # also wait to emit this Request too because it should come after the
      # response/requestfinished.
      redirect_response_extra_info = nil
      if event['redirectHasExtraInfo']
        redirect_response_extra_info = @network_event_manager.response_extra_info(event['requestId']).shift
        unless redirect_response_extra_info
          redirect_info = RedirectInfo.new(
            event: event,
            fetch_request_id: fetch_request_id,
          )
          @network_event_manager.enqueue_redirect_info(event['requestId'], redirect_info)
          return
        end
      end

      # If we connect late to the target, we could have missed the
      # requestWillBeSent event.
      if_present(@network_event_manager.get_request(event['requestId'])) do |request|
        handle_request_redirect(request, event['redirectResponse'], redirect_response_extra_info)
        redirect_chain = request.internal.redirect_chain
      end
    end
    frame = if_present(event['frameId']) { |frame_id| @frame_manager.frame(frame_id) }
    request = Puppeteer::HTTPRequest.new(@client, frame, fetch_request_id, @user_request_interception_enabled, event, redirect_chain)
    @network_event_manager.store_request(event['requestId'], request)
    emit_event(NetworkManagerEmittedEvents::Request, request)
    begin
      request.finalize_interceptions
    rescue => err
      debug_puts(err)
    end
  end

  private def handle_request_served_from_cache(event)
    request = @network_event_manager.get_request(event['requestId'])
    if request
      request.internal.from_memory_cache = true
    end
    emit_event(NetworkManagerEmittedEvents::RequestServedFromCache, request)
  end

  # @param request [Puppeteer::HTTPRequest]
  # @param response_payload [Hash]
  private def handle_request_redirect(request, response_payload, extra_info)
    response = Puppeteer::HTTPResponse.new(@client, request, response_payload, extra_info)
    request.internal.response = response
    request.internal.redirect_chain << request
    response.internal.body_loaded_promise.reject(Puppeteer::HTTPResponse::Redirected.new)
    forget_request(request, false)
    emit_event(NetworkManagerEmittedEvents::Response, response)
    emit_event(NetworkManagerEmittedEvents::RequestFinished, request)
  end

  private def emit_response_event(response_received_event, extra_info)
    request = @network_event_manager.get_request(response_received_event['requestId'])
    # FileUpload sends a response without a matching request.
    return unless request

    unless @network_event_manager.response_extra_info(response_received_event['requestId']).empty?
      debug_puts("Unexpected extraInfo events for request #{response_received_event['requestId']}")
    end

    response = Puppeteer::HTTPResponse.new(@client, request, response_received_event['response'], extra_info)
    request.internal.response = response
    emit_event(NetworkManagerEmittedEvents::Response, response)
  end

  # @param event [Hash]
  private def handle_response_received(event)
    request = @network_event_manager.get_request(event['requestId'])
    extra_info = nil
    if request && !request.internal.from_memory_cache? && event['hasExtraInfo']
      extra_info = @network_event_manager.response_extra_info(event['requestId']).shift

      unless extra_info
        # Wait until we get the corresponding ExtraInfo event.
        @network_event_manager.enqueue_event_group(event['requestId'], QueuedEventGroup.new(event))
        return
      end
    end
    emit_response_event(event, extra_info)
  end

  private def handle_response_received_extra_info(event)
    # We may have skipped a redirect response/request pair due to waiting for
    # this ExtraInfo event. If so, continue that work now that we have the
    # request.
    if_present(@network_event_manager.take_queued_redirect_info(event['requestId'])) do |redirect_info|
      @network_event_manager.response_extra_info(event['requestId']) << event
      handle_request(redirect_info.event, redirect_info)
      return
    end

    # We may have skipped response and loading events because we didn't have
    # this ExtraInfo event yet. If so, emit those events now.
    if_present(@network_event_manager.get_queued_event_group(event['requestId'])) do |queued_events|
      emit_response_event(queued_events.response_received_event, event)
      if_present(queued_events.loading_finished_event) do |loading_finished_event|
        emit_loading_finished(loading_finished_event)
      end
      if_present(queued_events.loading_failed_event) do |loading_failed_event|
        emit_loading_failed(loading_failed_event)
      end
      return
    end

    # Wait until we get another event that can use this ExtraInfo event.
    @network_event_manager.response_extra_info(event['requestId']) << event
  end

  private def forget_request(request, forget_events)
    request_id = request.internal.request_id
    interception_id = request.internal.interception_id

    @network_event_manager.forget_request(request_id)
    @attempted_authentications.delete(interception_id)
    if forget_events
      @network_event_manager.forget(request_id)
    end
  end

  private def handle_loading_finished(event)
    # If the response event for this request is still waiting on a
    # corresponding ExtraInfo event, then wait to emit this event too.
    queued_events = @network_event_manager.get_queued_event_group(event['requestId'])
    if queued_events
      queued_events.loading_finished_event = event
    else
      emit_loading_finished(event)
    end
  end

  private def emit_loading_finished(event)
    request = @network_event_manager.get_request(event['requestId'])
    # For certain requestIds we never receive requestWillBeSent event.
    # @see https://crbug.com/750469
    return unless request

    # Under certain conditions we never get the Network.responseReceived
    # event from protocol. @see https://crbug.com/883475
    if_present(request.response) do |response|
      response.internal.body_loaded_promise.fulfill(nil)
    end

    forget_request(request, true)
    emit_event(NetworkManagerEmittedEvents::RequestFinished, request)
  end

  private def handle_loading_failed(event)
    # If the response event for this request is still waiting on a
    # corresponding ExtraInfo event, then wait to emit this event too.
    queued_events = @network_event_manager.get_queued_event_group(event['requestId'])
    if queued_events
      queued_events.loading_failed_event = event
    else
      emit_loading_failed(event)
    end
  end

  private def emit_loading_failed(event)
    request = @network_event_manager.get_request(event['requestId'])
    # For certain requestIds we never receive requestWillBeSent event.
    # @see https://crbug.com/750469
    return unless request

    request.internal.failure_text = event['errorText']
    if_present(request.response) do |response|
      response.internal.body_loaded_promise.fulfill(nil)
    end
    forget_request(request, true)
    emit_event(NetworkManagerEmittedEvents::RequestFailed, request)
  end
end
