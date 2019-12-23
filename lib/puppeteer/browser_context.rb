class Puppeteer::BrowserContext
  # @param {!Puppeteer.Connection} connection
  # @param {!Browser} browser
  # @param {?string} contextId
  def initialize(connection, browser, context_id)
    @connection = connection
    @browser = browser
    @id = context_id
  end

  # /**
  #  * @return {!Array<!Target>} target
  #  */
  # targets() {
  #   return this._browser.targets().filter(target => target.browserContext() === this);
  # }

  # /**
  #  * @param {function(!Target):boolean} predicate
  #  * @param {{timeout?: number}=} options
  #  * @return {!Promise<!Target>}
  #  */
  # waitForTarget(predicate, options) {
  #   return this._browser.waitForTarget(target => target.browserContext() === this && predicate(target), options);
  # }

  # /**
  #  * @return {!Promise<!Array<!Puppeteer.Page>>}
  #  */
  # async pages() {
  #   const pages = await Promise.all(
  #       this.targets()
  #           .filter(target => target.type() === 'page')
  #           .map(target => target.page())
  #   );
  #   return pages.filter(page => !!page);
  # }

  def incognito?
    !@id
  end

  # /**
  #  * @param {string} origin
  #  * @param {!Array<string>} permissions
  #  */
  # async overridePermissions(origin, permissions) {
  #   const webPermissionToProtocol = new Map([
  #     ['geolocation', 'geolocation'],
  #     ['midi', 'midi'],
  #     ['notifications', 'notifications'],
  #     ['push', 'push'],
  #     ['camera', 'videoCapture'],
  #     ['microphone', 'audioCapture'],
  #     ['background-sync', 'backgroundSync'],
  #     ['ambient-light-sensor', 'sensors'],
  #     ['accelerometer', 'sensors'],
  #     ['gyroscope', 'sensors'],
  #     ['magnetometer', 'sensors'],
  #     ['accessibility-events', 'accessibilityEvents'],
  #     ['clipboard-read', 'clipboardRead'],
  #     ['clipboard-write', 'clipboardWrite'],
  #     ['payment-handler', 'paymentHandler'],
  #     // chrome-specific permissions we have.
  #     ['midi-sysex', 'midiSysex'],
  #   ]);
  #   permissions = permissions.map(permission => {
  #     const protocolPermission = webPermissionToProtocol.get(permission);
  #     if (!protocolPermission)
  #       throw new Error('Unknown permission: ' + permission);
  #     return protocolPermission;
  #   });
  #   await this._connection.send('Browser.grantPermissions', {origin, browserContextId: this._id || undefined, permissions});
  # }

  # async clearPermissionOverrides() {
  #   await this._connection.send('Browser.resetPermissions', {browserContextId: this._id || undefined});
  # }

  #  * @return {!Promise<!Puppeteer.Page>}
  def new_page
    @browser.create_page_in_context(@id)
  end

  # @return [Browser]
  def browser
    @browser
  end

  def close
    if !@id
      raise 'Non-incognito profiles cannot be closed!'
    end
    @browser.dispose_context(@id)
  end
end
