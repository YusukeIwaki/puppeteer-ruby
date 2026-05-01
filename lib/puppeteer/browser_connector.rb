require_relative './browser'
require_relative './chrome_user_data_dir'
require_relative './launcher/browser_options'

class Puppeteer::BrowserConnector
  def initialize(options)
    @browser_options = Puppeteer::Launcher::BrowserOptions.new(options)
    @browser_ws_endpoint = options[:browser_ws_endpoint]
    @browser_url = options[:browser_url]
    @transport = options[:transport]
    @channel = options[:channel]
  end

  # @return [Puppeteer::Browser]
  def connect_to_browser
    version = Puppeteer::Browser::Version.fetch(connection)
    product_name = version.product.to_s.downcase
    if product_name.include?('firefox')
      raise Puppeteer::Error.new('Firefox CDP support has been removed. Use puppeteer-bidi for Firefox automation.')
    end
    product = 'chrome'

    result = connection.send_message('Target.getBrowserContexts')
    browser_context_ids = result['browserContextIds']

    Puppeteer::Browser.create(
      product: product,
      connection: connection,
      context_ids: browser_context_ids,
      ignore_https_errors: @browser_options.ignore_https_errors?,
      default_viewport: @browser_options.default_viewport,
      network_enabled: @browser_options.network_enabled,
      issues_enabled: @browser_options.issues_enabled,
      block_list: @browser_options.block_list,
      process: nil,
      close_callback: -> { connection.send_message('Browser.close') },
      target_filter_callback: @browser_options.target_filter,
      is_page_target_callback: @browser_options.is_page_target,
    )
  end

  private def connection
    @connection ||= begin
      connection_options = [@browser_ws_endpoint, @browser_url, @transport, @channel]
      unless connection_options.count { |option| !!option } == 1
        raise ArgumentError.new('Exactly one of browserWSEndpoint, browserURL, transport or channel must be passed to puppeteer.connect')
      end

      if @transport
        connect_with_transport(@transport)
      elsif @browser_ws_endpoint
        connect_with_browser_ws_endpoint(@browser_ws_endpoint)
      elsif @browser_url
        connect_with_browser_url(@browser_url)
      elsif @channel
        connect_with_channel(@channel)
      else
        raise ArgumentError.new('Invalid connection options')
      end
    end
  end

  # @return [Puppeteer::Connection]
  private def connect_with_browser_ws_endpoint(browser_ws_endpoint)
    transport = Puppeteer::WebSocketTransport.create(browser_ws_endpoint)
    Puppeteer::Connection.new(
      browser_ws_endpoint,
      transport,
      @browser_options.slow_mo,
      protocol_timeout: @browser_options.protocol_timeout,
    )
  end

  # @return [Puppeteer::Connection]
  private def connect_with_browser_url(browser_url)
    require 'net/http'
    uri = URI(browser_url)
    uri.path = '/json/version'
    response_body = Net::HTTP.get(uri)
    json = JSON.parse(response_body)
    connection_url = json['webSocketDebuggerUrl']
    connect_with_browser_ws_endpoint(connection_url)
  end

  # @return [Puppeteer::Connection]
  private def connect_with_channel(channel)
    port_path = File.join(
      Puppeteer::ChromeUserDataDir.resolve_default(channel),
      'DevToolsActivePort',
    )

    begin
      file_content = File.read(port_path, mode: 'r:ASCII')
      raw_port, raw_path = file_content.lines.map(&:strip).reject(&:empty?)
      unless raw_port && raw_path
        raise Puppeteer::Error.new("Invalid DevToolsActivePort '#{file_content}' found")
      end

      port = raw_port.to_i
      if port <= 0 || port > 65_535
        raise Puppeteer::Error.new("Invalid port '#{raw_port}' found")
      end

      connect_with_browser_ws_endpoint("ws://localhost:#{port}#{raw_path}")
    rescue StandardError
      raise Puppeteer::Error.new("Could not find DevToolsActivePort for #{channel} at #{port_path}")
    end
  end

  # @return [Puppeteer::Connection]
  private def connect_with_transport(transport)
    Puppeteer::Connection.new(
      '',
      transport,
      @browser_options.slow_mo,
      protocol_timeout: @browser_options.protocol_timeout,
    )
  end
end
