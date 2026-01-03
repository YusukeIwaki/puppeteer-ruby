require 'json'

class Puppeteer::HTTPResponse
  include Puppeteer::IfPresent

  class Redirected < Puppeteer::Error
    def initialize
      super('Response body is unavailable for redirect responses')
    end
  end

  # defines methods used only in NetworkManager
  class InternalAccessor
    def initialize(response)
      @response = response
    end

    def body_loaded_promise
      @response.instance_variable_get(:@body_loaded_promise)
    end
  end

  class RemoteAddress
    def initialize(ip:, port:)
      @ip = ip
      @port = port
    end
    attr_reader :ip, :port
  end

  # @param client [Puppeteer::CDPSession]
  # @param request [Puppeteer::HTTPRequest]
  # @param response_payload [Hash]
  # @param extra_info [Hash|nil]
  def initialize(client, request, response_payload, extra_info)
    @client = client
    @request = request

    @body_loaded_promise = Async::Promise.new
    @remote_address = RemoteAddress.new(
      ip: response_payload['remoteIPAddress'],
      port: response_payload['remotePort'],
    )

    @status_text = parse_štatus_text_from_extra_info(extra_info) || response_payload['statusText']
    @url = request.url
    @from_disk_cache = !!response_payload['fromDiskCache']
    @from_service_worker = !!response_payload['fromServiceWorker']

    @status = extra_info ? extra_info['statusCode'] : response_payload['status']
    @headers = {}
    headers = extra_info ? extra_info['headers'] : response_payload['headers']
    headers.each do |key, value|
      @headers[key.downcase] = value
    end
    @security_details = if_present(response_payload['securityDetails']) do |security_payload|
      SecurityDetails.new(security_payload)
    end

    @internal = InternalAccessor.new(self)
  end

  attr_reader :internal

  attr_reader :remote_address, :url, :status, :status_text, :headers, :security_details, :request

  def inspect
    values = %i[remote_address url status status_text headers security_details request].map do |sym|
      value = instance_variable_get(:"@#{sym}")
      "@#{sym}=#{value}"
    end
    "#<Puppeteer::HTTPRequest #{values.join(' ')}>"
  end

  private def parse_štatus_text_from_extra_info(extra_info)
    return nil if !extra_info || !extra_info['headersText']
    first_line = extra_info['headersText'].split("\r").first
    return nil unless first_line
    /[^ ]* [^ ]* (.*)/.match(first_line) do |m|
      return m[1]
    end

    nil
  end

  # @return [Boolean]
  def ok?
    @status == 0 || (@status >= 200 && @status <= 299)
  end

  def buffer
    @body_loaded_promise.wait
    response = @client.send_message('Network.getResponseBody', requestId: @request.internal.request_id)
    if response['base64Encoded']
      Base64.decode64(response['body'])
    else
      response['body']
    end
  end

  # @param text [String]
  def text
    buffer
  end

  # @param json [Hash]
  def json
    JSON.parse(text)
  end

  def from_cache?
    @from_disk_cache || @request.internal.from_memory_cache?
  end

  def from_service_worker?
    @from_service_worker
  end

  def frame
    @request.frame
  end

  class SecurityDetails
    def initialize(security_payload)
      @subject_name = security_payload['subjectName']
      @issuer = security_payload['issuer']
      @valid_from = security_payload['validFrom']
      @valid_to = security_payload['validTo']
      @protocol = security_payload['protocol']
    end

    attr_reader :subject_name, :issuer, :valid_from, :valid_to, :protocol
  end
end
