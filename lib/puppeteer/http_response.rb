require 'json'

class Puppeteer::HTTPResponse
  include Puppeteer::IfPresent

  class Redirected < StandardError
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
  def initialize(client, request, response_payload)
    @client = client
    @request = request

    @body_loaded_promise = resolvable_future
    @remote_address = RemoteAddress.new(
      ip: response_payload['remoteIPAddress'],
      port: response_payload['remotePort'],
    )

    @status = response_payload['status']
    @status_text = response_payload['statusText']
    @url = request.url
    @from_disk_cache = !!response_payload['fromDiskCache']
    @from_service_worker = !!response_payload['fromServiceWorker']

    @headers = {}
    response_payload['headers'].each do |key, value|
      @headers[key.downcase] = value
    end
    @security_details = if_present(response_payload['securityDetails']) do |security_payload|
      SecurityDetails.new(security_payload)
    end

    @internal = InternalAccessor.new(self)
  end

  attr_reader :internal

  attr_reader :remote_address, :url, :status, :status_text, :headers, :security_details, :request

  # @return [Boolean]
  def ok?
    @status == 0 || (@status >= 200 && @status <= 299)
  end

  def buffer
    await @body_loaded_promise
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
