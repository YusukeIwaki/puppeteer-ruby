class Puppeteer::HTTPRequest
  include Puppeteer::DebugPrint
  include Puppeteer::IfPresent

  # defines some methods used only in NetworkManager, Response
  class InternalAccessor
    def initialize(request)
      @request = request
    end

    def request_id
      @request.instance_variable_get(:@request_id)
    end

    def interception_id
      @request.instance_variable_get(:@interception_id)
    end

    # @param response [Puppeteer::HTTPResponse]
    def response=(response)
      @request.instance_variable_set(:@response, response)
    end

    def redirect_chain
      @request.instance_variable_get(:@redirect_chain)
    end

    def failure_text=(failure_text)
      @request.instance_variable_set(:@failure_text, failure_text)
    end

    def from_memory_cache=(from_memory_cache)
      @request.instance_variable_set(:@from_memory_cache, from_memory_cache)
    end

    def from_memory_cache?
      @request.instance_variable_get(:@from_memory_cache)
    end
  end

  # @param client [Puppeteer::CDPSession]
  # @param frame [Puppeteer::Frame]
  # @param interception_id [string|nil]
  # @param allow_interception [boolean]
  # @param event [Hash]
  # @param redirect_chain Array<Request>
  def initialize(client, frame, interception_id, allow_interception, event, redirect_chain)
    @client = client
    @request_id = event['requestId']
    @is_navigation_request = event['requestId'] == event['loaderId'] && event['type'] == 'Document'
    @interception_id = interception_id
    @allow_interception = allow_interception
    @url = event['request']['url']
    @resource_type = event['type'].downcase
    @method = event['request']['method']
    @post_data = event['request']['postData']
    @frame = frame
    @redirect_chain = redirect_chain
    @continue_request_overrides = {}
    @current_strategy = 'none'
    @current_priority = nil
    @intercept_actions = []
    @initiator = event['initiator']

    @headers = {}
    event['request']['headers'].each do |key, value|
      @headers[key.downcase] = value
    end
    @from_memory_cache = false

    @internal = InternalAccessor.new(self)
  end

  attr_reader :internal
  attr_reader :url, :resource_type, :method, :post_data, :headers, :response, :frame, :initiator

  def inspect
    values = %i[request_id method url].map do |sym|
      value = instance_variable_get(:"@#{sym}")
      "@#{sym}=#{value}"
    end
    "#<Puppeteer::HTTPRequest #{values.join(' ')}>"
  end

  private def assert_interception_allowed
    unless @allow_interception
      raise InterceptionNotEnabledError.new
    end
  end

  private def assert_interception_not_handled
    if @interception_handled
      raise AlreadyHandledError.new
    end
  end

  # @returns the `ContinueRequestOverrides` that will be used
  # if the interception is allowed to continue (ie, `abort()` and
  # `respond()` aren't called).
  def continue_request_overrides
    assert_interception_allowed
    @continue_request_overrides
  end

  # @returns The `ResponseForRequest` that gets used if the
  # interception is allowed to respond (ie, `abort()` is not called).
  def response_for_request
    assert_interception_allowed
    @response_for_request
  end

  # @returns the most recent reason for aborting the request
  def abort_error_reason
    assert_interception_allowed
    @abort_error_reason
  end

  # @returns An array of the current intercept resolution strategy and priority
  # `[strategy,priority]`. Strategy is one of: `abort`, `respond`, `continue`,
  #  `disabled`, `none`, or `already-handled`.
  def intercept_resolution
    if !@allow_interception
      ['disabled']
    elsif @interception_handled
      ['already-handled']
    else
      [@current_strategy, @current_priority]
    end
  end

  # Adds an async request handler to the processing queue.
  # Deferred handlers are not guaranteed to execute in any particular order,
  # but they are guarnateed to resolve before the request interception
  # is finalized.
  #
  # @param pending_handler [Proc]
  def enqueue_intercept_action(pending_handler)
    @intercept_actions << pending_handler
  end

  # Awaits pending interception handlers and then decides how to fulfill
  # the request interception.
  def finalize_interceptions
    @intercept_actions.each(&:call)
    case @intercept_resolution
    when :abort
      abort_impl(**@abort_error_reason)
    when :respond
      respond_impl(**@response_for_request)
    when :continue
      continue_impl(@continue_request_overrides)
    end
  end

  def navigation_request?
    @is_navigation_request
  end

  def redirect_chain
    @redirect_chain.dup
  end

  def failure
    if_present(@failure_text) do |failure_text|
      { errorText: @failure_text }
    end
  end

  private def headers_to_array(headers)
    return nil unless headers

    headers.map do |key, value|
      { name: key, value: value.to_s }
    end
  end

  class InterceptionNotEnabledError < StandardError
    def initialize
      super('Request Interception is not enabled!')
    end
  end

  class AlreadyHandledError < StandardError
    def initialize
      super('Request is already handled!')
    end
  end

  # proceed request on request interception.
  #
  # Example:
  #
  #   page.on 'request' do |req|
  #     # Override headers
  #     headers = req.headers.merge(
  #       foo: 'bar', # set "foo" header
  #       origin: nil, # remove "origin" header
  #     )
  #     req.continue(headers: headers)
  #   end
  #
  # @param error_code [String|Symbol]
  def continue(url: nil, method: nil, post_data: nil, headers: nil, priority: nil)
    # Request interception is not supported for data: urls.
    return if @url.start_with?('data:')

    assert_interception_allowed
    assert_interception_not_handled

    overrides = {
      url: url,
      method: method,
      postData: post_data,
      headers: headers_to_array(headers),
    }.compact

    if priority.nil?
      continue_impl(overrides)
      return
    end

    @continue_request_overrides = overrides
    if @current_priority.nil? || priority > @current_priority
      @current_strategy = :continue
      @current_priority = priority
      return
    end

    if priority == @current_priority
      if @current_strategy == :abort || @current_strategy == :respond
        return
      end
      @current_strategy = :continue
    end
  end

  private def continue_impl(overrides)
    @interception_handled = true

    begin
      @client.send_message('Fetch.continueRequest',
        requestId: @interception_id,
        **overrides,
      )
    rescue => err
      # In certain cases, protocol will return error if the request was already canceled
      # or the page was closed. We should tolerate these errors.
      debug_puts(err)
    end
  end

  # Mocking response.
  #
  # Example:
  #
  #   page.on 'request' do |req|
  #     req.respond(
  #       status: 404,
  #       content_type: 'text/plain',
  #       body: 'Not Found!'
  #     )
  #   end
  #
  # @param status [Integer]
  # @param headers [Hash<String, String>]
  # @param content_type [String]
  # @param body [String]
  def respond(status: nil, headers: nil, content_type: nil, body: nil, priority: nil)
    # Mocking responses for dataURL requests is not currently supported.
    return if @url.start_with?('data:')

    assert_interception_allowed
    assert_interception_not_handled

    if priority.nil?
      respond_impl(status: status, headers: headers, content_type: content_type, body: body)
      return
    end

    @response_for_request = {
      status: status,
      headers: headers,
      content_type: content_type,
      body: body,
    }

    if @current_priority.nil? || priority > @current_priority
      @current_strategy = :respond
      @current_priority = priority
      return
    end

    if priority == @current_priority
      if @current_strategy == :abort
        return
      end
      @current_strategy = :respond
    end
  end

  private def respond_impl(status: nil, headers: nil, content_type: nil, body: nil)
    @interception_handled = true

    mock_response_headers = {}
    headers&.each do |key, value|
      mock_response_headers[key.downcase] = value
    end
    if content_type
      mock_response_headers['content-type'] = content_type
    end
    if body
      mock_response_headers['content-length'] = body.length
    end

    mock_response = {
      responseCode: status || 200,
      responsePhrase: STATUS_TEXTS[(status || 200).to_s],
      responseHeaders: headers_to_array(mock_response_headers),
      body: if_present(body) { |mock_body| Base64.strict_encode64(mock_body) },
    }.compact

    begin
      @client.send_message('Fetch.fulfillRequest',
        requestId: @interception_id,
        **mock_response,
      )
    rescue => err
      # In certain cases, protocol will return error if the request was already canceled
      # or the page was closed. We should tolerate these errors.
      debug_puts(err)
    end
  end

  # abort request on request interception.
  #
  # Example:
  #
  #   page.on 'request' do |req|
  #     if req.url.include?("porn")
  #       req.abort
  #     else
  #       req.continue
  #     end
  #   end
  #
  # @param error_code [String|Symbol]
  def abort(error_code: :failed, priority: nil)
    # Request interception is not supported for data: urls.
    return if @url.start_with?('data:')

    error_reason = ERROR_REASONS[error_code.to_s]
    unless error_reason
      raise ArgumentError.new("Unknown error code: #{error_code}")
    end
    assert_interception_allowed
    assert_interception_not_handled

    if priority.nil?
      abort_impl(error_reason)
    end
    @abort_error_reason = error_reason

    if @current_priority.nil? || priority > @current_priority
      @current_strategy = :abort
      @current_priority = priority
    end
  end

  private def abort_impl(error_reason)
    @interception_handled = true

    begin
      @client.send_message('Fetch.failRequest',
        requestId: @interception_id,
        errorReason: error_reason,
      )
    rescue => err
      # In certain cases, protocol will return error if the request was already canceled
      # or the page was closed. We should tolerate these errors.
      debug_puts(err)
    end
  end

  ERROR_REASONS = {
    'aborted' => 'Aborted',
    'accessdenied' => 'AccessDenied',
    'addressunreachable' => 'AddressUnreachable',
    'blockedbyclient' => 'BlockedByClient',
    'blockedbyresponse' => 'BlockedByResponse',
    'connectionaborted' => 'ConnectionAborted',
    'connectionclosed' => 'ConnectionClosed',
    'connectionfailed' => 'ConnectionFailed',
    'connectionrefused' => 'ConnectionRefused',
    'connectionreset' => 'ConnectionReset',
    'internetdisconnected' => 'InternetDisconnected',
    'namenotresolved' => 'NameNotResolved',
    'timedout' => 'TimedOut',
    'failed' => 'Failed',
  }.freeze

  # List taken from https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml with extra 306 and 418 codes.
  STATUS_TEXTS = {
    '100' => 'Continue',
    '101' => 'Switching Protocols',
    '102' => 'Processing',
    '103' => 'Early Hints',
    '200' => 'OK',
    '201' => 'Created',
    '202' => 'Accepted',
    '203' => 'Non-Authoritative Information',
    '204' => 'No Content',
    '205' => 'Reset Content',
    '206' => 'Partial Content',
    '207' => 'Multi-Status',
    '208' => 'Already Reported',
    '226' => 'IM Used',
    '300' => 'Multiple Choices',
    '301' => 'Moved Permanently',
    '302' => 'Found',
    '303' => 'See Other',
    '304' => 'Not Modified',
    '305' => 'Use Proxy',
    '306' => 'Switch Proxy',
    '307' => 'Temporary Redirect',
    '308' => 'Permanent Redirect',
    '400' => 'Bad Request',
    '401' => 'Unauthorized',
    '402' => 'Payment Required',
    '403' => 'Forbidden',
    '404' => 'Not Found',
    '405' => 'Method Not Allowed',
    '406' => 'Not Acceptable',
    '407' => 'Proxy Authentication Required',
    '408' => 'Request Timeout',
    '409' => 'Conflict',
    '410' => 'Gone',
    '411' => 'Length Required',
    '412' => 'Precondition Failed',
    '413' => 'Payload Too Large',
    '414' => 'URI Too Long',
    '415' => 'Unsupported Media Type',
    '416' => 'Range Not Satisfiable',
    '417' => 'Expectation Failed',
    '418' => 'I\'m a teapot',
    '421' => 'Misdirected Request',
    '422' => 'Unprocessable Entity',
    '423' => 'Locked',
    '424' => 'Failed Dependency',
    '425' => 'Too Early',
    '426' => 'Upgrade Required',
    '428' => 'Precondition Required',
    '429' => 'Too Many Requests',
    '431' => 'Request Header Fields Too Large',
    '451' => 'Unavailable For Legal Reasons',
    '500' => 'Internal Server Error',
    '501' => 'Not Implemented',
    '502' => 'Bad Gateway',
    '503' => 'Service Unavailable',
    '504' => 'Gateway Timeout',
    '505' => 'HTTP Version Not Supported',
    '506' => 'Variant Also Negotiates',
    '507' => 'Insufficient Storage',
    '508' => 'Loop Detected',
    '510' => 'Not Extended',
    '511' => 'Network Authentication Required',
  }.freeze
end
