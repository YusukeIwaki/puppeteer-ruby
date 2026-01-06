# rbs_inline: enabled

class Puppeteer::Puppeteer
  # @rbs project_root: String -- Project root directory
  # @rbs preferred_revision: String -- Preferred Chromium revision
  # @rbs is_puppeteer_core: bool -- Whether puppeteer-core mode is enabled
  # @rbs return: void -- No return value
  def initialize(project_root:, preferred_revision:, is_puppeteer_core:)
    @project_root = project_root
    @preferred_revision = preferred_revision
    @is_puppeteer_core = is_puppeteer_core
  end

  class NoViewport ; end

  # @rbs product: String? -- Browser product (chrome only)
  # @rbs channel: (String | Symbol)? -- Browser channel
  # @rbs executable_path: String? -- Path to browser executable
  # @rbs ignore_default_args: Array[String]? -- Arguments to exclude from defaults
  # @rbs handle_SIGINT: bool? -- Handle SIGINT in browser process
  # @rbs handle_SIGTERM: bool? -- Handle SIGTERM in browser process
  # @rbs handle_SIGHUP: bool? -- Handle SIGHUP in browser process
  # @rbs timeout: Integer? -- Launch timeout in milliseconds
  # @rbs dumpio: bool? -- Pipe browser stdout/stderr to current process
  # @rbs env: Hash[untyped, untyped]? -- Environment variables for browser
  # @rbs pipe: bool? -- Use pipe instead of WebSocket
  # @rbs args: Array[String]? -- Additional browser arguments
  # @rbs user_data_dir: String? -- Path to user data directory
  # @rbs devtools: bool? -- Auto-open DevTools
  # @rbs debugging_port: Integer? -- Remote debugging port
  # @rbs headless: bool? -- Run browser in headless mode
  # @rbs ignore_https_errors: bool? -- Ignore HTTPS errors
  # @rbs default_viewport: Puppeteer::Viewport? -- Default viewport
  # @rbs slow_mo: Integer? -- Delay between operations (ms)
  # @rbs wait_for_initial_page: bool? -- Wait for initial page to load
  # @rbs return: Puppeteer::Browser -- Browser instance
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
    args: nil,
    user_data_dir: nil,
    devtools: nil,
    debugging_port: nil,
    headless: nil,
    ignore_https_errors: nil,
    default_viewport: NoViewport.new,
    slow_mo: nil,
    wait_for_initial_page: nil
  )
    product = product.to_s if product
    if product && product != 'chrome'
      raise ArgumentError.new("Unsupported product: #{product}. Only 'chrome' is supported.")
    end

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
      args: args,
      user_data_dir: user_data_dir,
      devtools: devtools,
      debugging_port: debugging_port,
      headless: headless,
      ignore_https_errors: ignore_https_errors,
      default_viewport: default_viewport,
      slow_mo: slow_mo,
      wait_for_initial_page: wait_for_initial_page,
    }
    if default_viewport.is_a?(NoViewport)
      options.delete(:default_viewport)
    end
    options.delete(:wait_for_initial_page) if wait_for_initial_page.nil?

    @product_name = product
    if async_context?
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
    else
      runner = Puppeteer::ReactorRunner.new
      begin
        browser = runner.sync { launcher.launch(options) }
      rescue StandardError
        runner.close
        raise
      end
      proxy = Puppeteer::ReactorRunner::Proxy.new(runner, browser, owns_runner: true)
      if block_given?
        begin
          yield(proxy)
        ensure
          proxy.close
        end
      else
        proxy
      end
    end
  end

  # @rbs browser_ws_endpoint: String? -- Browser WebSocket endpoint
  # @rbs browser_url: String? -- Browser HTTP URL for WebSocket discovery
  # @rbs transport: Puppeteer::WebSocketTransport? -- Pre-connected transport
  # @rbs ignore_https_errors: bool? -- Ignore HTTPS errors
  # @rbs default_viewport: Puppeteer::Viewport? -- Default viewport
  # @rbs slow_mo: Integer? -- Delay between operations (ms)
  # @rbs return: Puppeteer::Browser -- Browser instance
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
    if async_context?
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
    else
      runner = Puppeteer::ReactorRunner.new
      begin
        browser = runner.sync { Puppeteer::BrowserConnector.new(options).connect_to_browser }
      rescue StandardError
        runner.close
        raise
      end
      proxy = Puppeteer::ReactorRunner::Proxy.new(runner, browser, owns_runner: true)
      if block_given?
        begin
          yield(proxy)
        ensure
          proxy.disconnect
        end
      else
        proxy
      end
    end
  end

  # @rbs channel: String? -- Browser channel
  # @rbs return: String -- Executable path
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

  # @rbs return: String -- Product name
  def product
    launcher.product
  end

  private def async_context?
    task = Async::Task.current
    !task.nil?
  rescue RuntimeError, NoMethodError
    false
  end

  # @rbs name: String -- Custom query handler name
  # @rbs query_one: untyped -- Query-one handler
  # @rbs query_all: untyped -- Query-all handler
  # @rbs return: void -- No return value
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

  # @rbs name: String -- Custom query handler name
  # @rbs query_one: untyped -- Query-one handler
  # @rbs query_all: untyped -- Query-all handler
  # @rbs return: untyped -- Block result
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

  # @rbs return: Puppeteer::Devices -- Devices registry
  def devices
    Puppeteer::Devices
  end

  # @rbs return: Puppeteer::NetworkConditions -- Network conditions registry
  def network_conditions
    Puppeteer::NetworkConditions
  end

  # @rbs args: Array[String]? -- Additional arguments
  # @rbs user_data_dir: String? -- Path to user data directory
  # @rbs devtools: bool? -- Enable DevTools
  # @rbs headless: bool? -- Run browser in headless mode
  # @rbs return: Array[String] -- Default launch arguments
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
