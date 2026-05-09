# frozen_string_literal: true

class TestServerSinatraAdapter
  class SinatraRequest
    def initialize(route_request)
      @route_request = route_request
      @env = build_env(route_request.headers)
    end

    attr_reader :env

    private def build_env(headers)
      env = {}
      headers.each do |key, value|
        name = "HTTP_#{key.upcase.tr('-', '_')}"
        env[name] = value
      end
      env
    end
  end

  class RouteContext
    def initialize(request)
      @headers = {}
      @status = 200
      @body = nil
      @request = request
    end

    attr_reader :headers

    def status(value = nil)
      return @status if value.nil?

      @status = value
    end

    def headers(values = nil)
      return @headers if values.nil?

      @headers.merge!(values)
    end

    def halt(status = nil, body = nil, headers = nil)
      status ||= @status
      headers ||= @headers
      body = body.nil? ? @body : body
      throw(:halt, [status, headers, body])
    end

    def cache_control(*values, **options)
      directives = values.map { |value| value.to_s.tr('_', '-') }
      options.each do |key, value|
        directive = key.to_s.tr('_', '-')
        directives << (value == true ? directive : "#{directive}=#{value}")
      end
      @headers['cache-control'] = directives.join(', ')
    end

    def last_modified(value)
      time = value.is_a?(Time) ? value : Time.parse(value.to_s)
      @headers['last-modified'] = time.httpdate

      if_modified_since = @request.env['HTTP_IF_MODIFIED_SINCE']
      return unless if_modified_since

      begin
        since_time = Time.httpdate(if_modified_since)
      rescue ArgumentError
        return
      end

      if since_time.to_i >= time.to_i
        @status = 304
        @body = ''
        halt(@status, @body, @headers)
      end
    end

    def body(value = nil)
      return @body if value.nil?

      @body = value
    end

    def request
      @request
    end

    def response
      self
    end
  end

  def initialize(server)
    @server = server
  end

  def get(path, &block)
    @server.set_route(path) do |route_request, writer|
      route = RouteContext.new(SinatraRequest.new(route_request))
      result = catch(:halt) { route.instance_exec(&block) }

      status, headers, body =
        if result.is_a?(Array) && result.size == 3
          result
        else
          [route.status, route.headers, route.body || result]
        end

      writer.status = status if status
      headers&.each { |key, value| writer.add_header(key, value) }
      writer.write(body.to_s) if body
      writer.finish
    end
  end
end
