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

  # @param event_name [Symbol] either of :disconnected, :targetcreated, :targetchanged, :targetdestroyed
  def on(event_name, &block)
    unless BrowserContextEmittedEvents.values.include?(event_name.to_s)
      raise ArgumentError.new("Unknown event name: #{event_name}. Known events are #{BrowserContextEmittedEvents.values.to_a.join(", ")}")
    end

    super(event_name.to_s, &block)
  end

  # @param event_name [Symbol]
  def once(event_name, &block)
    unless BrowserContextEmittedEvents.values.include?(event_name.to_s)
      raise ArgumentError.new("Unknown event name: #{event_name}. Known events are #{BrowserContextEmittedEvents.values.to_a.join(", ")}")
    end

    super(event_name.to_s, &block)
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

  WEB_PERMISSION_TO_PROTOCOL = {
    'geolocation' => 'geolocation',
    'midi' => 'midi',
    'notifications' => 'notifications',
    # TODO: push isn't a valid type?
    # 'push' => 'push',
    'camera' => 'videoCapture',
    'microphone' => 'audioCapture',
    'background-sync' => 'backgroundSync',
    'ambient-light-sensor' => 'sensors',
    'accelerometer' => 'sensors',
    'gyroscope' => 'sensors',
    'magnetometer' => 'sensors',
    'accessibility-events' => 'accessibilityEvents',
    'clipboard-read' => 'clipboardReadWrite',
    'clipboard-write' => 'clipboardReadWrite',
    'payment-handler' => 'paymentHandler',
    'idle-detection' => 'idleDetection',
    # chrome-specific permissions we have.
    'midi-sysex' => 'midiSysex',
  }.freeze

  # @param origin [String]
  # @param permissions [Array<String>]
  def override_permissions(origin, permissions)
    protocol_permissions = permissions.map do |permission|
      WEB_PERMISSION_TO_PROTOCOL[permission] or raise ArgumentError.new("Unknown permission: #{permission}")
    end
    @connection.send_message('Browser.grantPermissions', {
      origin: origin,
      browserContextId: @id,
      permissions: protocol_permissions,
    }.compact)
  end

  def clear_permission_overrides
    if @id
      @connection.send_message('Browser.resetPermissions', browserContextId: @id)
    else
      @connection.send_message('Browser.resetPermissions')
    end
  end

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
