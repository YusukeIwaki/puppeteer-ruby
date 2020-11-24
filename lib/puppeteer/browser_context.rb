class Puppeteer::BrowserContext
  include Puppeteer::EventCallbackable
  using Puppeteer::DefineAsyncMethod

  # @param {!Puppeteer.Connection} connection
  # @param {!Browser} browser
  # @param {?string} contextId
  def initialize(connection, browser, context_id)
    @connection = connection
    @browser = browser
    @id = context_id
  end

  EVENT_MAPPINGS = {
    targetcreated: BrowserContextEmittedEvents::TargetCreated,
    targetchanged: BrowserContextEmittedEvents::TargetChanged,
    targetdestroyed: BrowserContextEmittedEvents::TargetDestroyed,
  }

  # @param event_name [Symbol] either of :disconnected, :targetcreated, :targetchanged, :targetdestroyed
  def on(event_name, &block)
    unless EVENT_MAPPINGS.has_key?(event_name.to_sym)
      raise ArgumentError.new("Unknown event name: #{event_name}. Known events are #{EVENT_MAPPINGS.keys.join(", ")}")
    end

    add_event_listener(EVENT_MAPPINGS[event_name.to_sym], &block)
  end

  # @param event_name [Symbol]
  def once(event_name, &block)
    unless EVENT_MAPPINGS.has_key?(event_name.to_sym)
      raise ArgumentError.new("Unknown event name: #{event_name}. Known events are #{EVENT_MAPPINGS.keys.join(", ")}")
    end

    observe_first(EVENT_MAPPINGS[event_name.to_sym], &block)
  end

  # @return {!Array<!Target>} target
  def targets
    @browser.targets.select { |target| target.browser_context == self }
  end

  # @param predicate [Proc(Puppeteer::Target -> Boolean)]
  # @return [Puppeteer::Target]
  def wait_for_target(predicate:, timeout: nil)
    @browser.wait_for_target(
      predicate: ->(target) { target.browser_context == self && predicate.call(target) },
      timeout: timeout,
    )
  end

  # @!method async_wait_for_target(predicate:, timeout: nil)
  #
  # @param predicate [Proc(Puppeteer::Target -> Boolean)]
  define_async_method :async_wait_for_target

  # @return {!Promise<!Array<!Puppeteer.Page>>}
  def pages
    targets.select { |target| target.type == 'page' }.map(&:page).reject { |page| !page }
  end

  def incognito?
    !!@id
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

  # @return [Future<Puppeteer::Page>]
  def new_page
    @browser.create_page_in_context(@id)
  end

  # @return [Browser]
  def browser
    @browser
  end

  def close
    unless @id
      raise 'Non-incognito profiles cannot be closed!'
    end
    @browser.dispose_context(@id)
  end
end
