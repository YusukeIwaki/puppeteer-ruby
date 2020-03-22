class Puppeteer::EmulationManager
  using Puppeteer::AsyncAwaitBehavior

  # @param {!Puppeteer.CDPSession} client
  def initialize(client)
    @client = client
    @emulating_mobile = false
    @has_touch = false
  end

  # @param viewport [Puppeteer::Viewport]
  # @return {Promise<boolean>}
  def emulate_viewport(viewport)
    mobile = viewport.mobile?
    width = viewport.width
    height = viewport.height
    device_scale_factor = viewport.device_scale_factor
    # /** @type {Protocol.Emulation.ScreenOrientation} */
    # const screenOrientation = viewport.isLandscape ? { angle: 90, type: 'landscapePrimary' } : { angle: 0, type: 'portraitPrimary' };
    has_touch = viewport.has_touch?

    await Concurrent::Promises.zip(
      @client.send_message('Emulation.setDeviceMetricsOverride',
        mobile: mobile,
        width: width,
        height: height,
        deviceScaleFactor: device_scale_factor,
        # screenOrientation: screen_orientation,
      ),
      @client.send_message('Emulation.setTouchEmulationEnabled',
        enabled: has_touch,
      ),
    )

    reload_needed = @emulating_mobile != mobile || @hasTouch != has_touch;
    @emulating_mobile = mobile
    @has_touch = has_touch
    return reload_needed
  end
end
