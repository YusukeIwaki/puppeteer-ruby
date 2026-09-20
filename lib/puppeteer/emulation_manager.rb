class Puppeteer::EmulationManager
  include Puppeteer::DebugPrint
  using Puppeteer::DefineAsyncMethod

  # @param {!Puppeteer.CDPSession} client
  def initialize(client, logger: nil)
    @client = client
    @logger = logger
    @emulating_mobile = false
    @has_touch = false
    @viewport = nil
    @locale = nil
    @locale_configured = false
    @secondary_clients = Set.new
  end

  def update_client(client)
    @client = client
    @secondary_clients.delete(client)
  end

  def register_speculative_session(client)
    @secondary_clients << client
    client.once(CDPSessionEmittedEvents::Disconnected) do
      @secondary_clients.delete(client)
    end
    promises = []
    promises.concat(viewport_promises(client, @viewport)) if @viewport
    if @locale_configured
      promises << client.async_send_message(
        'Emulation.setLocaleOverride',
        { locale: @locale }.compact,
      )
    end
    return if promises.empty?

    Async do
      Puppeteer::AsyncUtils.await_promise_all(*promises)
    rescue => err
      log_error(err)
    end
  end

  # @param viewport [Puppeteer::Viewport, nil] -- Viewport settings, or nil to clear emulation
  # @return [true|false]
  def emulate_viewport(viewport)
    unless viewport
      return false if @viewport.nil?

      clear_viewport(@client)
      @viewport = nil

      reload_needed = @emulating_mobile != false || @has_touch != false
      @emulating_mobile = false
      @has_touch = false
      return reload_needed
    end

    mobile = viewport.mobile?
    has_touch = viewport.has_touch?

    apply_viewport(@client, viewport)
    @viewport = viewport

    reload_needed = @emulating_mobile != mobile || @has_touch != has_touch
    @emulating_mobile = mobile
    @has_touch = has_touch
    reload_needed
  end

  private def clear_viewport(client)
    Puppeteer::AsyncUtils.await_promise_all(
      client.async_send_message('Emulation.clearDeviceMetricsOverride'),
      client.async_send_message('Emulation.setTouchEmulationEnabled', enabled: false),
    )
  rescue => err
    log_error(err)
  end

  # Forwards errors to the custom error logger (when configured) while
  # preserving the traditional DEBUG output.
  private def log_error(error)
    @logger&.call(Puppeteer::DebugPrefixes::ERROR)&.call(error)
    debug_puts(error)
  end

  private def apply_viewport(client, viewport)
    Puppeteer::AsyncUtils.await_promise_all(*viewport_promises(client, viewport))
  rescue => err
    # Some targets (e.g. DevTools windows) do not support metrics override;
    # log and continue like upstream, but re-raise anything else.
    if err.message.to_s.include?('Target does not support metrics override')
      log_error(err)
    else
      raise
    end
  end

  private def viewport_promises(client, viewport)
    mobile = viewport.mobile?
    width = viewport.width
    height = viewport.height
    device_scale_factor = viewport.device_scale_factor
    screen_orientation =
      if viewport.landscape?
        { angle: 90, type: 'landscapePrimary' }
      else
        { angle: 0, type: 'portraitPrimary' }
      end
    has_touch = viewport.has_touch?

    [
      client.async_send_message('Emulation.setDeviceMetricsOverride',
        mobile: mobile,
        width: width,
        height: height,
        deviceScaleFactor: device_scale_factor,
        screenOrientation: screen_orientation,
      ),
      client.async_send_message('Emulation.setTouchEmulationEnabled',
        enabled: has_touch,
      ),
    ]
  end

  define_async_method :async_emulate_viewport

  # @rbs locale: String? -- Locale to emulate, or nil to disable emulation
  # @rbs return: void -- No return value
  def emulate_locale(locale)
    @locale = locale
    @locale_configured = true
    clients = [@client, *@secondary_clients]
    promises = clients.map do |client|
      client.async_send_message(
        'Emulation.setLocaleOverride',
        { locale: locale }.compact,
      )
    end
    Puppeteer::AsyncUtils.await_promise_all(*promises)
  end

  define_async_method :async_emulate_locale
end
