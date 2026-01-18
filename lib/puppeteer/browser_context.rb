require 'async/semaphore'
require 'uri'

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
    @closed = false
    @screenshot_semaphore = nil
    @screenshot_operations_count = 0
  end

  attr_reader :id

  class ScreenshotGuard
    def initialize(semaphore, on_release: nil)
      @semaphore = semaphore
      @on_release = on_release
      @released = false
    end

    def release
      return if @released

      @released = true
      @semaphore.release
      @on_release&.call
    end
    alias_method :close, :release
  end

  def ==(other)
    other = other.__getobj__ if other.is_a?(Puppeteer::ReactorRunner::Proxy)
    return true if equal?(other)
    return false unless other.is_a?(Puppeteer::BrowserContext)
    return false if @id.nil? || other.id.nil?

    @id == other.id
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

  def start_screenshot
    semaphore = @screenshot_semaphore || Async::Semaphore.new(1)
    @screenshot_semaphore = semaphore
    @screenshot_operations_count += 1
    semaphore.acquire
    ScreenshotGuard.new(semaphore, on_release: lambda {
      @screenshot_operations_count -= 1
      @screenshot_semaphore = nil if @screenshot_operations_count.zero?
    })
  end

  def wait_for_screenshot_operations
    semaphore = @screenshot_semaphore
    return nil unless semaphore

    semaphore.acquire
    ScreenshotGuard.new(semaphore)
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
  def pages(include_all: false)
    targets.select { |target|
      target.type == 'page' ||
        ((target.type == 'other' || include_all) && @browser.is_page_target_callback&.call(target.target_info))
    }.map(&:page).compact
  end

  def incognito?
    !!@id
  end

  def closed?
    @closed || !@browser.browser_contexts.include?(self)
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
    'persistent-storage' => 'durableStorage',
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
    guard = wait_for_screenshot_operations
    @browser.create_page_in_context(@id)
  ensure
    guard&.release
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
    @closed = true
  end

  # @return [Array<Hash>]
  def cookies
    params = { browserContextId: @id }.compact
    response = @connection.send_message('Storage.getCookies', params)
    response.fetch('cookies', []).map do |cookie|
      normalized = cookie.dup
      partition_key = cookie['partitionKey']
      if partition_key
        normalized['partitionKey'] = convert_partition_key_from_cdp(partition_key)
      end
      normalized['sameParty'] = cookie['sameParty'] || false
      normalized
    end
  end

  # @param cookies [Array<Hash>]
  def set_cookie(*cookies)
    items = cookies.map do |cookie|
      normalized = normalize_cookie_hash(cookie)
      partition_key = normalized.delete('partitionKey') || normalized.delete('partition_key')
      normalized['partitionKey'] = convert_partition_key_for_cdp(partition_key) if partition_key
      normalized
    end
    @connection.send_message('Storage.setCookies', {
      browserContextId: @id,
      cookies: items,
    }.compact)
  end

  # @param cookies [Array<Hash>]
  def delete_cookie(*cookies)
    items = cookies.map do |cookie|
      normalized = normalize_cookie_hash(cookie)
      normalized['expires'] = 1
      normalized
    end
    set_cookie(*items)
  end

  # @param filters [Array<Hash>]
  def delete_matching_cookies(*filters)
    cookies_to_delete = cookies.select do |cookie|
      filters.any? do |filter|
        filter_name = hash_value(filter, 'name')
        next false unless filter_name == cookie['name']

        filter_domain = hash_value(filter, 'domain')
        next true if filter_domain && filter_domain == cookie['domain']

        filter_path = hash_value(filter, 'path')
        next true if filter_path && filter_path == cookie['path']

        filter_partition_key = hash_value(filter, 'partitionKey', 'partition_key')
        if filter_partition_key && cookie['partitionKey']
          if cookie['partitionKey'].is_a?(String)
            raise Puppeteer::Error.new('Unexpected string partition key')
          end

          cookie_partition_source_origin = hash_value(cookie['partitionKey'], 'sourceOrigin', 'source_origin')
          filter_partition_source_origin =
            if filter_partition_key.is_a?(String)
              filter_partition_key
            else
              hash_value(filter_partition_key, 'sourceOrigin', 'source_origin')
            end

          next true if filter_partition_source_origin == cookie_partition_source_origin
        end

        filter_url = hash_value(filter, 'url')
        if filter_url
          url = URI.parse(filter_url)
          url_path = url.path.to_s.empty? ? '/' : url.path
          next true if url.hostname == cookie['domain'] && url_path == cookie['path']
        end

        true
      end
    end

    delete_cookie(*cookies_to_delete)
  end

  private def normalize_cookie_hash(cookie)
    cookie.each_with_object({}) do |(key, value), normalized|
      normalized[key.to_s] = value
    end
  end

  private def hash_value(hash, *keys)
    return nil unless hash

    keys.each do |key|
      return hash[key] if hash.key?(key)
      return hash[key.to_sym] if key.is_a?(String) && hash.key?(key.to_sym)
      return hash[key.to_s] if key.is_a?(Symbol) && hash.key?(key.to_s)
    end
    nil
  end

  private def convert_partition_key_for_cdp(partition_key)
    return nil if partition_key.nil?
    return { topLevelSite: partition_key, hasCrossSiteAncestor: false } if partition_key.is_a?(String)

    source_origin = hash_value(partition_key, 'sourceOrigin', 'source_origin')
    has_cross_site_ancestor = hash_value(partition_key, 'hasCrossSiteAncestor', 'has_cross_site_ancestor')
    {
      topLevelSite: source_origin,
      hasCrossSiteAncestor: has_cross_site_ancestor.nil? ? false : has_cross_site_ancestor,
    }
  end

  private def convert_partition_key_from_cdp(partition_key)
    return nil if partition_key.nil?
    return partition_key if partition_key.is_a?(String)

    {
      'sourceOrigin' => hash_value(partition_key, 'topLevelSite', 'top_level_site'),
      'hasCrossSiteAncestor' => hash_value(partition_key, 'hasCrossSiteAncestor', 'has_cross_site_ancestor'),
    }.compact
  end
end
