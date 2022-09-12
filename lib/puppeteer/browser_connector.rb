require_relative './browser'
require_relative './launcher/browser_options'

class Puppeteer::BrowserConnector
  def initialize(**options)
    @browser_options = Puppeteer::Launcher::BrowserOptions.new(options)
    @browser_ws_endpoint = options[:browser_ws_endpoint]
    @browser_url = options[:browser_url]
    @transport = options[:transport]
  end

  # @return [Puppeteer::Browser]
  def connect_to_browser
    version = Puppeteer::Browser::Version.fetch(connection)
    product = version.product.downcase.include?('firefox') ? 'firefox' : 'chrome'

    result = connection.send_message('Target.getBrowserContexts')
    browser_context_ids = result['browserContextIds']

    Puppeteer::Browser.create(
      product: product,
      connection: connection,
      context_ids: browser_context_ids,
      ignore_https_errors: @browser_options.ignore_https_errors?,
      default_viewport: @browser_options.default_viewport,
      process: nil,
      close_callback: -> { connection.send_message('Browser.close') },
      target_filter_callback: @browser_options.target_filter,
      is_page_target_callback: @browser_options.is_page_target,
    )
  end

  private def connection
    @connection ||=
      if @browser_ws_endpoint && @browser_url.nil? && @transport.nil?
        connect_with_browser_ws_endpoint(@browser_ws_endpoint)
      elsif @browser_ws_endpoint.nil? && @browser_url && @transport.nil?
        connect_with_browser_url(@browser_url)
      elsif @browser_ws_endpoint.nil? && @browser_url.nil? && @transport
        connect_with_transport(@transport)
      else
        raise ArgumentError.new("Exactly one of browserWSEndpoint, browserURL or transport must be passed to puppeteer.connect")
      end
  end

  # @return [Puppeteer::Connection]
  private def connect_with_browser_ws_endpoint(browser_ws_endpoint)
    transport = Puppeteer::WebSocketTransport.create(browser_ws_endpoint)
    Puppeteer::Connection.new(browser_ws_endpoint, transport, @browser_options.slow_mo)
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
  private def connect_with_transport(transport)
    Puppeteer::Connection.new('', transport, @browser_options.slow_mo)
  end
end
