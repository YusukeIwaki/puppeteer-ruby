class Puppeteer::BrowserContext
  # @param {!Puppeteer.Connection} connection
  # @param {!Browser} browser
  # @param {?string} contextId
  def initialize(connection, browser, context_id)
    @connection = connection
    @browser = browser
    @id = context_id
  end

  # @return {!Array<!Target>} target
  def targets
    @browser.targets.select{ |target| target.browser_context == self }
  end

  # @param {function(!Target):boolean} predicate
  # @param {{timeout?: number}=} options
  # @return {!Promise<!Target>}
  def wait_for_target(predicate:, timeout: nil)
    @browser.wait_for_target(
      predicate: ->(target) { target.browser_context == self && predicate.call(target) },
      timeout: timeout
    )
  end

  # @return {!Promise<!Array<!Puppeteer.Page>>}
  def pages
    targets.select{ |target| target.type == 'page' }.map(&:page).reject{ |page| !page }
  end

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

  def handle_browser_context_target_created(target)
  end

  def handle_browser_context_target_destroyed(target)
  end

  def handle_browser_context_target_changed(target)
  end
end
