class Puppeteer::Puppeteer
  # @param project_root [String]
  # @param prefereed_revision [String]
  # @param is_puppeteer_core [String]
  def initialize(project_root:, preferred_revision:, is_puppeteer_core:)
    @project_root = project_root
    @preferred_revision = preferred_revision
    @is_puppeteer_core = is_puppeteer_core
  end

  class NoViewport ; end

  # @param product [String]
  # @param channel [String|Symbol]
  # @param executable_path [String]
  # @param ignore_default_args [Array<String>|nil]
  # @param handle_SIGINT [Boolean]
  # @param handle_SIGTERM [Boolean]
  # @param handle_SIGHUP [Boolean]
  # @param timeout [Integer]
  # @param dumpio [Boolean]
  # @param env [Hash]
  # @param pipe [Boolean]
  # @param extra_prefs_firefox [Hash]
  # @param args [Array<String>]
  # @param user_data_dir [String]
  # @param devtools [Boolean]
  # @param headless [Boolean]
  # @param ignore_https_errors [Boolean]
  # @param default_viewport [Puppeteer::Viewport|nil]
  # @param slow_mo [Integer]
  # @return [Puppeteer::Browser]
  def launch(
    product: nil,
    channel: nil,
    executable_path: nil,
    ignore_default_args: nil,
    handle_SIGINT: nil,
    handle_SIGTERM: nil,
    handle_SIGHUP: nil,
    timeout: nil,
    dumpio: nil,
    env: nil,
    pipe: nil,
    extra_prefs_firefox: nil,
    args: nil,
    user_data_dir: nil,
    devtools: nil,
    debugging_port: nil,
    headless: nil,
    ignore_https_errors: nil,
    default_viewport: NoViewport.new,
    slow_mo: nil
  )
    options = {
      channel: channel&.to_s,
      executable_path: executable_path,
      ignore_default_args: ignore_default_args,
      handle_SIGINT: handle_SIGINT,
      handle_SIGTERM: handle_SIGTERM,
      handle_SIGHUP: handle_SIGHUP,
      timeout: timeout,
      dumpio: dumpio,
      env: env,
      pipe: pipe,
      extra_prefs_firefox: extra_prefs_firefox,
      args: args,
      user_data_dir: user_data_dir,
      devtools: devtools,
      debugging_port: debugging_port,
      headless: headless,
      ignore_https_errors: ignore_https_errors,
      default_viewport: default_viewport,
      slow_mo: slow_mo,
    }
    if default_viewport.is_a?(NoViewport)
      options.delete(:default_viewport)
    end

    @product_name = product
    browser = launcher.launch(options)
    if block_given?
      begin
        yield(browser)
      ensure
        browser.close
      end
    else
      browser
    end
  end

  # @param browser_ws_endpoint [String]
  # @param browser_url [String]
  # @param transport [Puppeteer::WebSocketTransport]
  # @param ignore_https_errors [Boolean]
  # @param default_viewport [Puppeteer::Viewport|nil]
  # @param slow_mo [Integer]
  # @return [Puppeteer::Browser]
  def connect(
    browser_ws_endpoint: nil,
    browser_url: nil,
    transport: nil,
    ignore_https_errors: nil,
    default_viewport: nil,
    slow_mo: nil
  )
    options = {
      browser_ws_endpoint: browser_ws_endpoint,
      browser_url: browser_url,
      transport: transport,
      ignore_https_errors: ignore_https_errors,
      default_viewport: default_viewport,
      slow_mo: slow_mo,
    }.compact
    browser = Puppeteer::BrowserConnector.new(options).connect_to_browser
    if block_given?
      begin
        yield(browser)
      ensure
        browser.disconnect
      end
    else
      browser
    end
  end

  # @return [String]
  def executable_path(channel: nil)
    launcher.executable_path(channel: channel)
  end

  private def launcher
    @launcher = Puppeteer::Launcher.new(
      project_root: @project_root,
      preferred_revision: @preferred_revision,
      is_puppeteer_core: @is_puppeteer_core,
      product: @product_name,
    )
  end

  # @return [String]
  def product
    launcher.product
  end

  def register_custom_query_handler(name:, query_one:, query_all:)
    unless name =~ /\A[a-zA-Z]+\z/
      raise ArgumentError.new("Custom query handler names may only contain [a-zA-Z]")
    end

    handler_name = name.to_sym
    if query_handler_manager.query_handlers.key?(handler_name)
      raise ArgumentError.new("A query handler named #{name} already exists")
    end

    handler = Puppeteer::CustomQueryHandler.new(query_one: query_one, query_all: query_all)
    Puppeteer::QueryHandlerManager.instance.query_handlers[handler_name] = handler
  end

  def with_custom_query_handler(name:, query_one:, query_all:, &block)
    unless name =~ /\A[a-zA-Z]+\z/
      raise ArgumentError.new("Custom query handler names may only contain [a-zA-Z]")
    end

    handler_name = name.to_sym

    handler = Puppeteer::CustomQueryHandler.new(query_one: query_one, query_all: query_all)
    query_handler_manager = Puppeteer::QueryHandlerManager.instance
    original = query_handler_manager.query_handlers.delete(handler_name)
    query_handler_manager.query_handlers[handler_name] = handler
    begin
      block.call
    ensure
      if original
        query_handler_manager.query_handlers[handler_name] = original
      else
        query_handler_manager.query_handlers.delete(handler_name)
      end
    end
  end

  # @return [Puppeteer::Devices]
  def devices
    Puppeteer::Devices
  end

  # # @return {Object}
  # def errors
  #   # ???
  # end

  # @return [Puppeteer::NetworkConditions]
  def network_conditions
    Puppeteer::NetworkConditions
  end

  # @param args [Array<String>]
  # @param user_data_dir [String]
  # @param devtools [Boolean]
  # @param headless [Boolean]
  # @return [Array<String>]
  def default_args(args: nil, user_data_dir: nil, devtools: nil, headless: nil)
    options = {
      args: args,
      user_data_dir: user_data_dir,
      devtools: devtools,
      headless: headless,
    }.compact
    launcher.default_args(options)
  end
end
