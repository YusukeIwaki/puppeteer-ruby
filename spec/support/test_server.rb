# frozen_string_literal: true

require 'async'
require 'async/http/server'
require 'async/http/client'
require 'async/http/endpoint'
require 'protocol/http/response'
require 'socket'
require 'timeout'
require 'time'
require 'uri'
require 'openssl'

module TestServer
  SSL_CERT_PATH = File.expand_path('ssl/cert.pem', __dir__)
  SSL_KEY_PATH = File.expand_path('ssl/key.pem', __dir__)

  def self.ssl_context
    @ssl_context ||= begin
      context = OpenSSL::SSL::SSLContext.new
      context.cert = OpenSSL::X509::Certificate.new(File.read(SSL_CERT_PATH))
      context.key = OpenSSL::PKey::RSA.new(File.read(SSL_KEY_PATH))
      context
    end
  end

  def self.client_ssl_context
    @client_ssl_context ||= begin
      context = OpenSSL::SSL::SSLContext.new
      context.verify_mode = OpenSSL::SSL::VERIFY_NONE
      context
    end
  end

  class Server
    attr_reader :port, :prefix, :cross_process_prefix, :empty_page

    DEFAULT_TIMEOUT = 5 # seconds

    def initialize(scheme: 'http', ssl_context: nil, port: nil)
      @scheme = scheme
      @ssl_context = ssl_context
      @port = port || find_available_port
      @prefix = "#{@scheme}://localhost:#{@port}"
      @cross_process_prefix = "#{@scheme}://127.0.0.1:#{@port}"
      @empty_page = "#{@prefix}/empty.html"
      @assets_directory = File.expand_path('../assets', __dir__)

      @routes = {}
      @routes_mutex = Mutex.new

      @request_promises = {}
      @request_promises_mutex = Mutex.new

      @server_thread = nil

      @ready_mutex = Mutex.new
      @ready_condition = ConditionVariable.new
      @ready = false
      @server_error = nil
    end

    def start
      return if @server_thread&.alive?

      @server_thread = Thread.new do
        run_server
      rescue StandardError => error
        signal_server_failure(error)
      end

      wait_until_ready
      wait_for_server
    end

    def stop
      clear_routes

      shutdown_server
      if @server_thread&.alive?
        @server_thread.join(1)
        if @server_thread.alive?
          @server_thread.kill
          @server_thread.join(1)
        end
      end
      @server_thread = nil

      @ready_mutex.synchronize do
        @ready = false
        @server_error = nil
      end
    end

    def clear_routes
      @routes_mutex.synchronize { @routes.clear }
      @request_promises_mutex.synchronize { @request_promises.clear }
      @csp_headers_mutex&.synchronize { @csp_headers&.clear }
    end

    def set_route(path, &block)
      @routes_mutex.synchronize do
        @routes[path] = block
      end
    end

    def set_redirect(from, to)
      set_route(from) do |_request, writer|
        writer.status = 302
        writer.add_header('location', to)
        writer.finish
      end
    end

    def set_csp(path, csp_value)
      # Store CSP headers for specific paths
      @csp_headers ||= {}
      @csp_headers_mutex ||= Mutex.new
      @csp_headers_mutex.synchronize do
        @csp_headers[path] = csp_value
      end
    end

    def get_csp(path)
      return nil unless @csp_headers
      @csp_headers_mutex.synchronize do
        @csp_headers[path]
      end
    end

    def wait_for_request(path, timeout: nil)
      promise = RequestPromise.new

      @request_promises_mutex.synchronize do
        @request_promises[path] ||= []
        @request_promises[path] << promise
      end

      duration = timeout || DEFAULT_TIMEOUT

      if (task = current_async_task)
        task.with_timeout(duration) do
          promise.wait
        end
      else
        Timeout.timeout(duration) do
          promise.wait
        end
      end
    rescue Async::TimeoutError, Timeout::Error
      raise "Timeout waiting for request to #{path}"
    end

    private def run_server
      Sync do
        endpoint = Async::HTTP::Endpoint.parse(
          "#{@scheme}://127.0.0.1:#{@port}",
          ssl_context: @ssl_context,
        )
        server = Async::HTTP::Server.for(endpoint) do |request|
          handle_request(request)
        end

        register_server(server)

        begin
          server.run
        ensure
          server.close
        end
      end
    end

    private def handle_request(request)
      raw_path = request.path
      path = strip_query(raw_path)
      handler = lookup_route(path)
      body = request.body&.read
      route_request = RouteRequest.new(request, body: body)

      notify_request(path, RequestRecord.new(route_request, body))

      if handler
        respond_with_handler(handler, route_request)
      else
        serve_static_asset(request)
      end
    rescue StandardError => error
      warn("[TestServer] Unhandled exception for #{request&.path}: #{error.class}: #{error.message}")
      ::Protocol::HTTP::Response[500, [['content-type', 'text/plain; charset=utf-8']], ['Internal Server Error']]
    ensure
      request.body&.close
    end

    private def respond_with_handler(handler, route_request)
      writer = ResponseWriter.new

      begin
        handler.call(route_request, writer)
      rescue StandardError => error
        warn("[TestServer] Route handler error for #{route_request.path}: #{error.class}: #{error.message}")
        writer.status = 500
        writer.write('Internal Server Error')
        writer.finish
      ensure
        writer.finish unless writer.finished?
      end

      writer.wait_for_finish

      status = writer.status
      body = writer.body
      headers = writer.headers
      unless headers.key?('content-type')
        path = route_request.path
        ext = File.extname(path)
        content_type = ext.empty? ? 'text/html; charset=utf-8' : mime_type_for(path)
        headers['content-type'] = content_type
      end

      ::Protocol::HTTP::Response[status, headers.to_a, [body]]
    end

    private def serve_static_asset(request)
      return method_not_allowed(request) unless %w[GET HEAD].include?(request.method)

      path = strip_query(request.path)
      relative_path = path == '/' ? '/index.html' : path
      sanitized = sanitize_path(relative_path)

      unless sanitized
        return ::Protocol::HTTP::Response[400, [['content-type', 'text/plain; charset=utf-8']], ['Bad Request']]
      end

      file_path = File.join(@assets_directory, sanitized)

      unless File.file?(file_path)
        return ::Protocol::HTTP::Response[404, [['content-type', 'text/plain; charset=utf-8']], ['Not Found']]
      end

      body = File.binread(file_path)
      headers = {
        'content-type' => mime_type_for(file_path),
      }
      if sanitized.start_with?('cached/')
        headers['cache-control'] = 'public, max-age=31536000'
        headers['last-modified'] = File.mtime(file_path).utc.httpdate
      end

      # Add CSP header if set for this path
      csp = get_csp(path)
      headers['content-security-policy'] = csp if csp

      response_body = request.method == 'HEAD' ? '' : body

      ::Protocol::HTTP::Response[200, headers.to_a, [response_body]]
    end

    private def method_not_allowed(_request)
      headers = [
        ['content-type', 'text/plain; charset=utf-8'],
        ['allow', 'GET, HEAD'],
      ]
      ::Protocol::HTTP::Response[405, headers, ['Method Not Allowed']]
    end

    private def lookup_route(path)
      @routes_mutex.synchronize do
        @routes[path]
      end
    end

    private def notify_request(path, request)
      promises = nil
      @request_promises_mutex.synchronize do
        promises = @request_promises.delete(path)
      end
      promises&.each { |promise| promise.resolve(request) }
    end

    private def register_server(_server)
      @ready_mutex.synchronize do
        @ready = true
        @ready_condition.broadcast
      end
    end

    private def shutdown_server
      @ready_mutex.synchronize do
        @ready = false
      end
    end

    private def wait_until_ready
      @ready_mutex.synchronize do
        until @ready || @server_error
          @ready_condition.wait(@ready_mutex)
        end
      end

      raise @server_error if @server_error
    end

    private def signal_server_failure(error)
      @ready_mutex.synchronize do
        @server_error = error
        @ready_condition.broadcast
      end
    end

    private def sanitize_path(path)
      clean = path.sub(%r{^/}, '')
      full_path = File.expand_path(clean, @assets_directory)
      return nil unless full_path.start_with?(@assets_directory)

      full_path[@assets_directory.length + 1..]
    end

    private def strip_query(path)
      return '' if path.nil?

      path.split('?', 2).first
    end

    private def mime_type_for(file_path)
      ext = File.extname(file_path)
      case ext
      when '.html' then 'text/html; charset=utf-8'
      when '.htm' then 'text/html; charset=utf-8'
      when '.css' then 'text/css; charset=utf-8'
      when '.js' then 'application/javascript; charset=utf-8'
      when '.json' then 'application/json; charset=utf-8'
      when '.png' then 'image/png'
      when '.jpg', '.jpeg' then 'image/jpeg'
      when '.gif' then 'image/gif'
      when '.svg' then 'image/svg+xml'
      when '.woff' then 'font/woff'
      when '.woff2' then 'font/woff2'
      when '.txt' then 'text/plain; charset=utf-8'
      else 'application/octet-stream'
      end
    end

    private def find_available_port
      server = TCPServer.new('127.0.0.1', 0)
      port = server.addr[1]
      server.close
      port
    end

    private def wait_for_server
      endpoint = Async::HTTP::Endpoint.parse(
        @prefix,
        ssl_context: @scheme == 'https' ? TestServer.client_ssl_context : nil,
      )

      Sync do |task|
        task.with_timeout(10) do
          client = Async::HTTP::Client.new(endpoint)

          begin
            loop do
              begin
                response = client.get('/empty.html')
                status = response.status
                response.finish
                break if status < 500
              rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, Errno::ECONNRESET, SocketError
                task.sleep(0.1)
                next
              end

              task.sleep(0.05)
            end
          ensure
            client.close
          end
        end
      end
    rescue Async::TimeoutError
      raise 'Test server failed to start'
    end

    private def current_async_task
      Async::Task.current
    rescue RuntimeError
      nil
    end
  end

  class RouteRequest
    attr_reader :method, :headers

    def initialize(request, body: nil)
      @request = request
      @method = request.method
      @body = body
      @headers = {}
      request.headers.each do |field|
        if field.respond_to?(:name) && field.respond_to?(:value)
          key = field.name
          value = field.value
        else
          key, value = field
        end

        @headers[key.to_s.downcase] = value
      end
    end

    def path
      return '' unless @request&.path

      @request.path.split('?', 2).first
    end
    alias path_info path

    def query
      @request.query
    end

    def params
      return {} unless query
      URI.decode_www_form(query).to_h
    end

    def body
      return @body if @body
      return nil unless @request.body

      @body = @request.body.read
    end
  end

  class RequestRecord
    attr_reader :method, :headers, :path, :post_body

    def initialize(route_request, body)
      @method = route_request.method
      @headers = route_request.headers
      @path = route_request.path
      # Match Puppeteer testserver: treat request body as UTF-8 text.
      @post_body = normalize_post_body(body)
    end

    private def normalize_post_body(body)
      return nil unless body

      utf8_body = body.dup
      utf8_body.force_encoding(Encoding::UTF_8)
      utf8_body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
  end

  class RequestPromise
    def initialize
      @resolved = false
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @request = nil
    end

    def resolve(request)
      @mutex.synchronize do
        @request = request
        @resolved = true
        @condition.broadcast
      end
    end

    def wait
      @mutex.synchronize do
        @condition.wait(@mutex) unless @resolved
      end
      @request
    end

    def resolved?
      @mutex.synchronize { @resolved }
    end
  end

  class ResponseWriter
    attr_reader :body
    attr_accessor :status

    def initialize
      @body = +''
      @status = 200
      @headers = {}
      @finished = false
      @mutex = Mutex.new
      @condition = ConditionVariable.new
    end

    def write(data)
      @mutex.synchronize do
        @body << data.to_s
      end
    end

    def add_header(name, value)
      normalized = normalize_header_name(name)
      @mutex.synchronize do
        @headers[normalized] = value
      end
    end

    def headers
      @mutex.synchronize do
        @headers.dup
      end
    end

    def finish(status: nil, headers: nil)
      @mutex.synchronize do
        return if @finished

        @status = status if status
        headers&.each do |key, value|
          @headers[normalize_header_name(key)] = value
        end

        @finished = true
        @condition.broadcast
      end
    end

    def finished?
      @mutex.synchronize { @finished }
    end

    def wait_for_finish
      until finished?
        if (async_task = current_async_task)
          async_task.sleep(0.01)
        else
          @mutex.synchronize do
            @condition.wait(@mutex, 0.05) unless @finished
          end
        end
      end
    end

    private def current_async_task
      Async::Task.current
    rescue RuntimeError
      nil
    end

    private def normalize_header_name(name)
      name.to_s.downcase
    end
  end
end
