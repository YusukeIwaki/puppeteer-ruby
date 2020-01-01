class Puppeteer::NetworkManager
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

  private def update_protocol_request_interception
  end
end
