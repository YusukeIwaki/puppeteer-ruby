require 'async/semaphore'

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

    def initialize(sender)
      @sender = sender
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

    def params
      {
        offline: @offline,
        latency: @latency,
        downloadThroughput: @download,
        uploadThroughput: @upload,
      }
    end

    def refresh
      update_network_conditions
    end

    private def update_network_conditions
      @sender.call('Network.emulateNetworkConditions', params)
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
  # @param {boolean} network_enabled
  def initialize(client, ignore_https_errors, frame_manager, network_enabled: true)
    @client = client
    @ignore_https_errors = ignore_https_errors
    @frame_manager = frame_manager
    @network_enabled = network_enabled
    @network_event_manager = Puppeteer::NetworkEventManager.new
    @clients = Set.new
    @initialized = false

    @extra_http_headers = {}
    @user_agent = nil
    @user_agent_metadata = nil

    @attempted_authentications = Set.new
    @user_request_interception_enabled = false
    @protocol_request_interception_enabled = false
    @user_cache_disabled = nil
    @internal_network_condition = InternalNetworkCondition.new(method(:send_to_clients))
    @interception_semaphore = Async::Semaphore.new(1)

    add_client(@client)
  end

  def init
    apply_to_clients do |client|
      configure_client(client)
    end
    @initialized = true
  end

  def add_client(client)
    return unless @network_enabled
    return if @clients.include?(client)

    @clients << client
    setup_listeners(client)
    if @initialized
      if Async::Task.current?
        Async do
          configure_client(client)
        end
      else
        configure_client(client)
      end
    end
  end

  def inspect
    values = %i[network_event_manager].map do |sym|
      value = instance_variable_get(:"@#{sym}")
      "@#{sym}=#{value}"
    end
    "#<Puppeteer::HTTPRequest #{values.join(' ')}>"
  end

  private def apply_to_clients
    @clients.each do |client|
      yield client
    end
  end

  private def ignore_client_error?(error)
    message = error&.message
    return false unless message

    lowered = message.downcase
    return true if lowered.include?('target closed')
    return true if lowered.include?('session closed')
    return true if lowered.include?('not supported')
    return true if lowered.include?("wasn't found")

    false
  end

  private def safe_send_message(client, method, params = {})
    client.send_message(method, params)
  rescue => err
    raise unless ignore_client_error?(err)
  end

  private def send_to_clients(method, params)
    apply_to_clients do |client|
      safe_send_message(client, method, params)
    end
  end

  private def apply_extra_http_headers(client)
    safe_send_message(client, 'Network.setExtraHTTPHeaders', headers: @extra_http_headers)
  end

  private def apply_user_agent(client)
    return unless @user_agent

    safe_send_message(client, 'Network.setUserAgentOverride', {
      userAgent: @user_agent,
      userAgentMetadata: @user_agent_metadata,
    }.compact)
  end

  private def apply_protocol_cache_disabled(client)
    return if @user_cache_disabled.nil?

    safe_send_message(client, 'Network.setCacheDisabled', cacheDisabled: @user_cache_disabled)
  end

  private def apply_protocol_request_interception(client)
    if @protocol_request_interception_enabled
      safe_send_message(client, 'Fetch.enable',
        handleAuthRequests: true,
        patterns: [{ urlPattern: '*' }],
      )
    else
      safe_send_message(client, 'Fetch.disable')
    end
  end

  private def configure_client(client)
    safe_send_message(client, 'Network.enable')
    if @ignore_https_errors
      safe_send_message(client, 'Security.setIgnoreCertificateErrors', ignore: true)
    end
    apply_extra_http_headers(client)
    apply_user_agent(client)
    apply_protocol_cache_disabled(client)
    apply_protocol_request_interception(client)
    safe_send_message(client, 'Network.emulateNetworkConditions', @internal_network_condition.params)
  end

  # @param username [String|NilClass]
  # @param password [String|NilClass]
  def authenticate(username:, password:)
    if username.nil? && password.nil?
      @credentials = nil
    else
      @credentials = Credentials.new(username: username, password: password)
    end
    update_protocol_request_interception
  end

  # @param {!Object<string, string>} extraHTTPHeaders
  def extra_http_headers=(headers)
    new_extra_http_headers = {}
    headers.each do |key, value|
      unless value.is_a?(String)
        type_description =
          case value
          when Numeric
            'number'
          when TrueClass, FalseClass
            'boolean'
          when NilClass
            'null'
          when Symbol
            'symbol'
          when Array, Hash
            'object'
          else
            value.class.to_s
          end
        raise ArgumentError.new("Expected value of header \"#{key}\" to be String, but \"#{type_description}\" is found.")
      end
      new_extra_http_headers[key.downcase] = value
    end
    @extra_http_headers = new_extra_http_headers
    apply_to_clients { |client| apply_extra_http_headers(client) }
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
    @user_agent = user_agent
    @user_agent_metadata = user_agent_metadata
    apply_to_clients { |client| apply_user_agent(client) }
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

  private def setup_listeners(client)
    client.add_event_listener(CDPSessionEmittedEvents::Disconnected) do
      @clients.delete(client)
    end

    client.on_event('Fetch.requestPaused') do |event|
      handle_request_paused(event, client)
    end
    client.on_event('Fetch.authRequired') do |event|
      handle_auth_required(event, client)
    end
    client.on_event('Network.requestWillBeSent') do |event|
      handle_request_will_be_sent(event, client)
    end
    client.on_event('Network.requestWillBeSentExtraInfo') do |event|
      handle_request_will_be_sent_extra_info(event, client)
    end
    client.on_event('Network.requestServedFromCache') do |event|
      handle_request_served_from_cache(event, client)
    end
    client.on_event('Network.responseReceived') do |event|
      handle_response_received(event, client)
    end
    client.on_event('Network.loadingFinished') do |event|
      handle_loading_finished(event, client)
    end
    client.on_event('Network.loadingFailed') do |event|
      handle_loading_failed(event, client)
    end
    client.on_event('Network.responseReceivedExtraInfo') do |event|
      handle_response_received_extra_info(event, client)
    end
  end

  private def update_protocol_request_interception
    enabled = @user_request_interception_enabled || !@credentials.nil?
    return if @protocol_request_interception_enabled == enabled
    @protocol_request_interception_enabled = enabled

    @user_cache_disabled = false if @user_cache_disabled.nil?

    update_protocol_cache_disabled
    apply_to_clients { |client| apply_protocol_request_interception(client) }
  end

  private def update_protocol_cache_disabled
    return if @user_cache_disabled.nil?

    apply_to_clients { |client| apply_protocol_cache_disabled(client) }
  end

  private def handle_request_will_be_sent(event, client)
    network_request_id = event['requestId']
    event_url = event.dig('request', 'url')
    if event_url
      url_fragment = event.dig('request', 'urlFragment')
      event_url += url_fragment if url_fragment
    end
    existing_request = @network_event_manager.get_request(network_request_id)
    if existing_request &&
       existing_request.url == event_url &&
       existing_request.method == event.dig('request', 'method')
      if_present(@network_event_manager.request_extra_info(network_request_id).shift) do |extra_info|
        existing_request.update_headers(extra_info['headers'])
      end
      return
    end

    # Request interception doesn't happen for data URLs with Network Service.
    if @user_request_interception_enabled && !event['request']['url'].start_with?('data:')
      @network_event_manager.store_request_will_be_sent(network_request_id, event)

      # CDP may have sent a Fetch.requestPaused event already. Check for it.
      if_present(@network_event_manager.get_request_paused(network_request_id)) do |request_paused_event|
        fetch_request_id = request_paused_event['requestId']
        patch_request_event_headers(event, request_paused_event)
        handle_request(event, fetch_request_id, client: client)
        @network_event_manager.forget_request_paused(network_request_id)
      end

      return
    end
    handle_request(event, nil, client: client)
  end

  private def handle_auth_required(event, client)
    auth_request_id = event['requestId']
    response = 'Default'
    if @attempted_authentications.include?(auth_request_id)
      response = 'CancelAuth'
    elsif @credentials
      response = 'ProvideCredentials'
      @attempted_authentications << auth_request_id
    end

    username = @credentials&.username
    password = @credentials&.password

    begin
      client.send_message('Fetch.continueWithAuth',
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

  private def handle_request_paused(event, client)
    if !@user_request_interception_enabled && @protocol_request_interception_enabled
      begin
        client.send_message('Fetch.continueRequest', requestId: event['requestId'])
      rescue => err
        debug_puts(err)
      end
    end

    request_id = event['networkId']
    fetch_request_id = event['requestId']
    if !request_id || request_id.empty?
      handle_request_without_network_instrumentation(event, client)
      return
    end
    network_request_id = request_id

    request_will_be_sent_event = @network_event_manager.get_request_will_be_sent(network_request_id)

    # redirect requests have the same `requestId`
    if request_will_be_sent_event &&
       (request_will_be_sent_event['request']['url'] != event['request']['url'] ||
        request_will_be_sent_event['request']['method'] != event['request']['method'])

      @network_event_manager.forget_request_will_be_sent(network_request_id)
      request_will_be_sent_event = nil
    end

    if request_will_be_sent_event
      patch_request_event_headers(request_will_be_sent_event, event)
      handle_request(request_will_be_sent_event, fetch_request_id, client: client)
    else
      if event['redirectedRequestId']
        handle_redirect_request_paused(event, network_request_id, fetch_request_id, client)
      elsif event['resourceType'] && event['resourceType'].to_s.downcase != 'document'
        request_event = build_request_event_from_paused(event, request_id)
        handle_request_from_paused(request_event, fetch_request_id, [], client: client)
      else
        @network_event_manager.store_request_paused(network_request_id, event)
      end
    end
  end

  private def patch_request_event_headers(request_will_be_sent_event, request_paused_event)
    request_will_be_sent_event['request']['headers'].merge!(
      # includes extra headers, like: Accept, Origin
      request_paused_event['request']['headers'])
  end

  private def handle_request_will_be_sent_extra_info(event, client)
    network_request_id = event['requestId']
    request = @network_event_manager.get_request(network_request_id)
    if request
      request.update_headers(event['headers'])
    else
      @network_event_manager.request_extra_info(network_request_id) << event
    end
  end

  private def with_interception_lock
    return yield unless Async::Task.current?

    @interception_semaphore.acquire do
      yield
    end
  end

  private def handle_request_without_network_instrumentation(event, client)
    frame = if_present(event['frameId']) { |frame_id| @frame_manager.frame(frame_id) }
    request = Puppeteer::HTTPRequest.new(client, frame, event['requestId'], @user_request_interception_enabled, event, [])
    emit_event(NetworkManagerEmittedEvents::Request, request)
    begin
      with_interception_lock { request.finalize_interceptions }
    rescue => err
      debug_puts(err)
    end
  end

  private def handle_redirect_request_paused(event, network_request_id, fetch_request_id, client)
    redirect_chain = []
    if_present(@network_event_manager.get_request(network_request_id)) do |request|
      response_payload = build_synthetic_redirect_response(event)
      handle_request_redirect(request, response_payload, nil)
      redirect_chain = request.internal.redirect_chain
    end

    request_event = build_request_event_from_paused(event, event['networkId'])
    handle_request_from_paused(request_event, fetch_request_id, redirect_chain, client: client)
  end

  private def build_request_event_from_paused(event, request_id)
    {
      'requestId' => request_id,
      'request' => event['request'],
      'type' => event['resourceType'],
      'frameId' => event['frameId'],
      'initiator' => event['initiator'],
    }.compact
  end

  private def build_synthetic_redirect_response(event)
    status = event['responseStatusCode'] || 302
    headers = {}
    if_present(event.dig('request', 'url')) do |url|
      headers['location'] = url
    end
    {
      'status' => status,
      'statusText' => Puppeteer::HTTPRequest::STATUS_TEXTS[status.to_s] || 'Found',
      'headers' => headers,
      'fromDiskCache' => false,
      'fromServiceWorker' => false,
    }
  end

  private def handle_request_from_paused(event, fetch_request_id, redirect_chain, client:)
    network_request_id = event['requestId']
    frame = if_present(event['frameId']) { |frame_id| @frame_manager.frame(frame_id) }
    request = Puppeteer::HTTPRequest.new(client, frame, fetch_request_id, @user_request_interception_enabled, event, redirect_chain)
    if_present(@network_event_manager.request_extra_info(network_request_id).shift) do |extra_info|
      request.update_headers(extra_info['headers'])
    end
    @network_event_manager.store_request(network_request_id, request)
    emit_event(NetworkManagerEmittedEvents::Request, request)
    begin
      with_interception_lock { request.finalize_interceptions }
    rescue => err
      debug_puts(err)
    end
  end

  private def handle_request(event, fetch_request_id, from_memory_cache: false, client:)
    network_request_id = event['requestId']
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
        redirect_response_extra_info = @network_event_manager.response_extra_info(network_request_id).shift
        unless redirect_response_extra_info
          redirect_info = RedirectInfo.new(
            event: event,
            fetch_request_id: fetch_request_id,
          )
          @network_event_manager.enqueue_redirect_info(network_request_id, redirect_info)
          return
        end
      end

      # If we connect late to the target, we could have missed the
      # requestWillBeSent event.
      if_present(@network_event_manager.get_request(network_request_id)) do |request|
        handle_request_redirect(request, event['redirectResponse'], redirect_response_extra_info)
        redirect_chain = request.internal.redirect_chain
        if_present(@network_event_manager.request_extra_info(network_request_id).shift) do |extra_info|
          request.update_headers(extra_info['headers'])
        end
      end
    end
    frame = if_present(event['frameId']) { |frame_id| @frame_manager.frame(frame_id) }
    request = Puppeteer::HTTPRequest.new(client, frame, fetch_request_id, @user_request_interception_enabled, event, redirect_chain)
    if_present(@network_event_manager.request_extra_info(network_request_id).shift) do |extra_info|
      request.update_headers(extra_info['headers'])
    end
    request.internal.from_memory_cache = from_memory_cache
    @network_event_manager.store_request(network_request_id, request)
    emit_event(NetworkManagerEmittedEvents::Request, request)
    begin
      with_interception_lock { request.finalize_interceptions }
    rescue => err
      debug_puts(err)
    end
  end

  private def handle_request_served_from_cache(event, client)
    network_request_id = event['requestId']
    request = @network_event_manager.get_request(network_request_id)
    request_will_be_sent_event = @network_event_manager.get_request_will_be_sent(network_request_id)
    if request
      request.internal.from_memory_cache = true
    elsif request_will_be_sent_event
      handle_request(request_will_be_sent_event, nil, from_memory_cache: true, client: client)
      request = @network_event_manager.get_request(network_request_id)
    end
    unless request
      debug_puts("Request #{event['requestId']} was served from cache but we could not find the corresponding request object")
      return
    end
    emit_event(NetworkManagerEmittedEvents::RequestServedFromCache, request)
  end

  # @param request [Puppeteer::HTTPRequest]
  # @param response_payload [Hash]
  private def handle_request_redirect(request, response_payload, extra_info)
    response = Puppeteer::HTTPResponse.new(request.client, request, response_payload, extra_info)
    request.internal.response = response
    request.internal.redirect_chain << request
    response.internal.body_loaded_promise.reject(Puppeteer::HTTPResponse::Redirected.new)
    forget_request(request, false)
    emit_event(NetworkManagerEmittedEvents::Response, response)
    emit_event(NetworkManagerEmittedEvents::RequestFinished, request)
  end

  private def emit_response_event(response_received_event, extra_info, network_request_id:)
    request = @network_event_manager.get_request(network_request_id)
    # FileUpload sends a response without a matching request.
    return unless request

    unless @network_event_manager.response_extra_info(network_request_id).empty?
      debug_puts("Unexpected extraInfo events for request #{response_received_event['requestId']}")
    end

    # Chromium sends wrong extraInfo events for responses served from cache.
    # @see https://crbug.com/1340398
    if response_received_event.dig('response', 'fromDiskCache')
      extra_info = nil
    end

    response = Puppeteer::HTTPResponse.new(request.client, request, response_received_event['response'], extra_info)
    request.internal.response = response
    emit_event(NetworkManagerEmittedEvents::Response, response)
  end

  private def adopt_cdp_session_if_needed(client, request)
    return if client == request.client

    request.internal.client = client
  end

  # @param event [Hash]
  private def handle_response_received(event, client)
    network_request_id = event['requestId']
    request = @network_event_manager.get_request(network_request_id)
    extra_info = nil
    if request && !request.internal.from_memory_cache? && event['hasExtraInfo']
      extra_info = @network_event_manager.response_extra_info(network_request_id).shift
      emit_response_event(event, extra_info, network_request_id: network_request_id)
      return
    end
    emit_response_event(event, extra_info, network_request_id: network_request_id)
  end

  private def handle_response_received_extra_info(event, client)
    network_request_id = event['requestId']
    # We may have skipped a redirect response/request pair due to waiting for
    # this ExtraInfo event. If so, continue that work now that we have the
    # request.
    if_present(@network_event_manager.take_queued_redirect_info(network_request_id)) do |redirect_info|
      @network_event_manager.response_extra_info(network_request_id) << event
      handle_request(redirect_info.event, redirect_info.fetch_request_id, client: client)
      return
    end

    if_present(@network_event_manager.get_request(network_request_id)) do |request|
      if request.response
        request.response.internal.update_extra_info(event)
        return
      end
    end

    # Wait until we get another event that can use this ExtraInfo event.
    return unless @network_event_manager.get_request(network_request_id)

    @network_event_manager.response_extra_info(network_request_id) << event
  end

  private def forget_request(request, forget_events)
    request_id = request.internal.request_id
    network_request_id = request_id
    interception_id = request.internal.interception_id
    auth_request_id = interception_id

    @network_event_manager.forget_request(network_request_id)
    @attempted_authentications.delete(auth_request_id)
    if forget_events
      @network_event_manager.forget(network_request_id)
    end
  end

  private def handle_loading_finished(event, client)
    network_request_id = event['requestId']
    # If the response event for this request is still waiting on a
    # corresponding ExtraInfo event, then wait to emit this event too.
    queued_events = @network_event_manager.get_queued_event_group(network_request_id)
    if queued_events
      @network_event_manager.forget_queued_event_group(network_request_id)
      emit_response_event(queued_events.response_received_event, nil, network_request_id: network_request_id)
      emit_loading_finished(event, network_request_id: network_request_id, client: client)
      return
    else
      emit_loading_finished(event, network_request_id: network_request_id, client: client)
    end
  end

  private def emit_loading_finished(event, network_request_id:, client:)
    request = @network_event_manager.get_request(network_request_id)
    # For certain requestIds we never receive requestWillBeSent event.
    # @see https://crbug.com/750469
    return unless request

    adopt_cdp_session_if_needed(client, request)

    # Under certain conditions we never get the Network.responseReceived
    # event from protocol. @see https://crbug.com/883475
    if_present(request.response) do |response|
      response.internal.body_loaded_promise.resolve(nil)
    end

    forget_request(request, true)
    emit_event(NetworkManagerEmittedEvents::RequestFinished, request)
  end

  private def handle_loading_failed(event, client)
    network_request_id = event['requestId']
    # If the response event for this request is still waiting on a
    # corresponding ExtraInfo event, then wait to emit this event too.
    queued_events = @network_event_manager.get_queued_event_group(network_request_id)
    if queued_events
      @network_event_manager.forget_queued_event_group(network_request_id)
      emit_response_event(queued_events.response_received_event, nil, network_request_id: network_request_id)
      emit_loading_failed(event, network_request_id: network_request_id, client: client)
      return
    else
      emit_loading_failed(event, network_request_id: network_request_id, client: client)
    end
  end

  private def emit_loading_failed(event, network_request_id:, client:)
    request = @network_event_manager.get_request(network_request_id)
    # For certain requestIds we never receive requestWillBeSent event.
    # @see https://crbug.com/750469
    return unless request

    adopt_cdp_session_if_needed(client, request)

    request.internal.failure_text = event['errorText']
    if_present(request.response) do |response|
      response.internal.body_loaded_promise.resolve(nil)
    end
    forget_request(request, true)
    emit_event(NetworkManagerEmittedEvents::RequestFailed, request)
  end
end
