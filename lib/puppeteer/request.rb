class Puppeteer::Request
  include Puppeteer::DebugPrint

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

    # @param response [Puppeteer::Response]
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
    @headers = {}
    event['request']['headers'].each do |key, value|
      @headers[key.downcase] = value
    end
    @from_memory_cache = false

    @internal = InternalAccessor.new(self)
  end

  attr_reader :internal
  attr_reader :url, :resource_type, :method, :post_data, :headers, :response, :frame

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


  def continue(url: nil, method: nil, post_data: nil, headers: nil)
    # Request interception is not supported for data: urls.
    return if @url.start_with?('data:')

    unless @allow_interception
      raise 'Request Interception is not enabled!'
    end
    if @interception_handled
      raise 'Request is already handled!'
    end
    @interception_handled = true

    overrides = {
      url: url,
      method: method,
      post_data: post_data,
      headers: headers_to_array(headers),
    }.compact
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

  def respond
    # async respond(response: {
    #   status: number;
    #   headers: Record<string, string>;
    #   contentType: string;
    #   body: string|Buffer;
    # }): Promise<void> {
    #   // Mocking responses for dataURL requests is not currently supported.
    #   if (this._url.startsWith('data:'))
    #     return;
    #   assert(this._allowInterception, 'Request Interception is not enabled!');
    #   assert(!this._interceptionHandled, 'Request is already handled!');
    #   this._interceptionHandled = true;

    #   const responseBody: Buffer | null = response.body && helper.isString(response.body) ? Buffer.from(response.body) : response.body as Buffer || null;

    #   const responseHeaders: Record<string, string> = {};
    #   if (response.headers) {
    #     for (const header of Object.keys(response.headers))
    #       responseHeaders[header.toLowerCase()] = response.headers[header];
    #   }
    #   if (response.contentType)
    #     responseHeaders['content-type'] = response.contentType;
    #   if (responseBody && !('content-length' in responseHeaders))
    #     responseHeaders['content-length'] = String(Buffer.byteLength(responseBody));

    #   await this._client.send('Fetch.fulfillRequest', {
    #     requestId: this._interceptionId,
    #     responseCode: response.status || 200,
    #     responsePhrase: STATUS_TEXTS[response.status || 200],
    #     responseHeaders: headersArray(responseHeaders),
    #     body: responseBody ? responseBody.toString('base64') : undefined,
    #   }).catch(error => {
    #     // In certain cases, protocol will return error if the request was already canceled
    #     // or the page was closed. We should tolerate these errors.
    #     debugError(error);
    #   });
    # }
  end

  def abort(error_code: :failed)
    # Request interception is not supported for data: urls.
    return if @url.start_with?('data:')

    error_reason = ERROR_REASONS[error_code.to_s]
    unless error_reason
      raise ArgumentError.new("Unknown error code: #{error_code}")
    end
    unless @allow_interception
      raise 'Request Interception is not enabled!'
    end
    if @interception_handled
      raise 'Request is already handled!'
    end
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
end
