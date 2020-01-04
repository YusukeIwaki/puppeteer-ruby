class Puppeteer::NetworkManager
  include Puppeteer::EventCallbackable

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
    @request_id_to_request_with_be_sent_event

    @extra_http_headers = {}

    @offline = false

    # /** @type {!Set<string>} */
    # this._attemptedAuthentications = new Set();
    @user_request_interception_enabled = false
    @protocol_request_interception_enabled = false
    @user_cache_disabled = false
    # /** @type {!Map<string, string>} */
    # this._requestIdToInterceptionId = new Map();
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
      uploadThroughput: -1
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
        patterns: [{urlPattern: '*'}],
      )
    else
      update_protocol_cache_disabled
      @client.send_message('Fetch.disable')
    end
  end

  private def update_protocol_cache_disabled
    cache_disabled = @user_cache_disabled || @protocol_request_interception_enabled
    @client.send_message('Network.setCacheDisabled', cacheDisabled: cache_disabled)
  end
end
