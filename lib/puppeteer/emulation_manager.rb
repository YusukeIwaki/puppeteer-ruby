class Puppeteer::EmulationManager
  include Puppeteer::DebugPrint
  using Puppeteer::DefineAsyncMethod

  # @param {!Puppeteer.CDPSession} client
  def initialize(client)
    @client = client
    @emulating_mobile = false
    @has_touch = false
    @viewport = nil
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
    return unless @viewport

    promises = viewport_promises(client, @viewport)
    Async do
      Puppeteer::AsyncUtils.await_promise_all(*promises)
    rescue => err
      debug_puts(err)
    end
  end

  # @param viewport [Puppeteer::Viewport]
  # @return [true|false]
  def emulate_viewport(viewport)
    mobile = viewport.mobile?
    has_touch = viewport.has_touch?

    apply_viewport(@client, viewport)
    @viewport = viewport

    reload_needed = @emulating_mobile != mobile || @has_touch != has_touch
    @emulating_mobile = mobile
    @has_touch = has_touch
    reload_needed
  end

  private def apply_viewport(client, viewport)
    Puppeteer::AsyncUtils.await_promise_all(*viewport_promises(client, viewport))
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
end
