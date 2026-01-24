# rbs_inline: enabled

module Puppeteer
  module LocatorEvent
    Action = 'action'
  end
end

class Puppeteer::Locator
  include Puppeteer::EventCallbackable

  RETRY_DELAY_SECONDS = 0.1

  class TimeoutController
    def initialize(timeout)
      @timeout = timeout
      @deadline = nil

      return if @timeout.nil? || @timeout == 0

      @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (@timeout / 1000.0)
    end

    attr_reader :timeout

    def remaining_timeout
      return 0 if @timeout == 0
      return nil unless @deadline

      remaining = (@deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)) * 1000.0
      remaining.negative? ? 0 : remaining
    end

    def exceeded?
      return false unless @deadline

      Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline
    end

    def check!(cause = nil)
      return unless exceeded?

      error = Puppeteer::TimeoutError.new("Timed out after waiting #{@timeout}ms")
      error.cause = cause if cause
      raise error
    end
  end

  def initialize
    @visibility = nil
    @timeout = 30_000
    @ensure_element_is_in_viewport = true
    @wait_for_enabled = true
    @wait_for_stable_bounding_box = true
  end

  # @rbs locators: Array[Puppeteer::Locator] -- Locator candidates
  # @rbs return: Puppeteer::Locator -- Locator that races candidates
  def self.race(locators)
    proxy = locators.find { |locator| locator.is_a?(Puppeteer::ReactorRunner::Proxy) }
    return Puppeteer::RaceLocator.create(locators) unless proxy

    runner = proxy.instance_variable_get(:@runner)
    locators.each do |locator|
      next unless locator.is_a?(Puppeteer::ReactorRunner::Proxy)

      locator_runner = locator.instance_variable_get(:@runner)
      unless locator_runner == runner
        raise ArgumentError.new('Locators for race must belong to the same runner')
      end
    end

    runner.sync do
      unwrapped = locators.map { |locator| runner.send(:unwrap, locator) }
      runner.wrap(Puppeteer::RaceLocator.create(unwrapped))
    end
  end

  # @rbs input: String -- Input string to check
  # @rbs return: bool -- Whether string looks like a JS function
  def self.function_string?(input)
    return false unless input.is_a?(String)

    stripped = input.lstrip
    return true if input.include?('=>')
    return true if stripped.start_with?('async function')

    stripped.start_with?('function')
  end

  # @rbs return: Numeric -- Timeout in milliseconds
  def timeout
    @timeout
  end

  # @rbs timeout: Numeric -- Timeout in milliseconds
  # @rbs return: Puppeteer::Locator -- Updated locator
  def set_timeout(timeout)
    locator = _clone
    locator.instance_variable_set(:@timeout, timeout)
    locator
  end

  # @rbs visibility: String? -- 'visible', 'hidden', or nil
  # @rbs return: Puppeteer::Locator -- Updated locator
  def set_visibility(visibility)
    locator = _clone
    locator.instance_variable_set(:@visibility, visibility&.to_s)
    locator
  end

  # @rbs value: bool -- Whether to wait for enabled state
  # @rbs return: Puppeteer::Locator -- Updated locator
  def set_wait_for_enabled(value)
    locator = _clone
    locator.instance_variable_set(:@wait_for_enabled, value)
    locator
  end

  # @rbs value: bool -- Whether to ensure element is in viewport
  # @rbs return: Puppeteer::Locator -- Updated locator
  def set_ensure_element_is_in_the_viewport(value)
    locator = _clone
    locator.instance_variable_set(:@ensure_element_is_in_viewport, value)
    locator
  end

  # @rbs value: bool -- Whether to wait for stable bounding box
  # @rbs return: Puppeteer::Locator -- Updated locator
  def set_wait_for_stable_bounding_box(value)
    locator = _clone
    locator.instance_variable_set(:@wait_for_stable_bounding_box, value)
    locator
  end

  # @rbs locator: Puppeteer::Locator -- Locator to copy options from
  # @rbs return: self -- Locator with copied options
  def copy_options(locator)
    @timeout = locator.timeout
    @visibility = locator.instance_variable_get(:@visibility)
    @wait_for_enabled = locator.instance_variable_get(:@wait_for_enabled)
    @ensure_element_is_in_viewport = locator.instance_variable_get(:@ensure_element_is_in_viewport)
    @wait_for_stable_bounding_box = locator.instance_variable_get(:@wait_for_stable_bounding_box)
    self
  end

  # @rbs return: Puppeteer::Locator -- Cloned locator
  def clone(freeze: nil)
    _clone
  end

  # @rbs return: Puppeteer::JSHandle -- Handle for located value
  def wait_handle
    with_retry('Locator.waitHandle') do |options|
      _wait(options)
    end
  end

  # @rbs return: untyped -- JSON-serializable value
  def wait
    handle = wait_handle
    begin
      return nil if handle.is_a?(Puppeteer::ElementHandle)

      handle.json_value
    ensure
      handle.dispose
    end
  end

  # @rbs mapper: String -- JS mapper function
  # @rbs return: Puppeteer::Locator -- Mapped locator
  def map(mapper)
    Puppeteer::MappedLocator.new(_clone, lambda { |handle, _options|
      handle.evaluate_handle(mapper)
    })
  end

  # @rbs predicate: String -- JS predicate function
  # @rbs return: Puppeteer::Locator -- Filtered locator
  def filter(predicate)
    Puppeteer::FilteredLocator.new(_clone, lambda { |handle, options|
      result = handle.frame.wait_for_function(predicate, args: [handle], timeout: options[:timeout])
      result.dispose
      true
    })
  end

  # @rbs predicate: Proc -- Handle predicate
  # @rbs return: Puppeteer::Locator -- Filtered locator
  def filter_handle(predicate)
    Puppeteer::FilteredLocator.new(_clone, predicate)
  end

  # @rbs mapper: Proc -- Handle mapper
  # @rbs return: Puppeteer::Locator -- Mapped locator
  def map_handle(mapper)
    Puppeteer::MappedLocator.new(_clone, mapper)
  end

  # @rbs delay: Numeric? -- Delay between down and up (ms)
  # @rbs button: String? -- Mouse button
  # @rbs click_count: Integer? -- Deprecated click count
  # @rbs count: Integer? -- Number of clicks
  # @rbs offset: Hash[Symbol, Numeric]? -- Click offset
  # @rbs return: void -- No return value
  def click(delay: nil, button: nil, click_count: nil, count: nil, offset: nil)
    perform_action('Locator.click',
      conditions: [
        method(:ensure_element_is_in_viewport_if_needed),
        method(:wait_for_stable_bounding_box_if_needed),
        method(:wait_for_enabled_if_needed),
      ]) do |handle, _options|
      handle.click(delay: delay, button: button, click_count: click_count, count: count, offset: offset)
    end
  end

  # @rbs value: String -- Value to fill
  # @rbs return: void -- No return value
  def fill(value)
    perform_action('Locator.fill',
      conditions: [
        method(:ensure_element_is_in_viewport_if_needed),
        method(:wait_for_stable_bounding_box_if_needed),
        method(:wait_for_enabled_if_needed),
      ]) do |handle, _options|
      fill_element(handle, value)
    end
  end

  # @rbs return: void -- No return value
  def hover
    perform_action('Locator.hover',
      conditions: [
        method(:ensure_element_is_in_viewport_if_needed),
        method(:wait_for_stable_bounding_box_if_needed),
      ]) do |handle, _options|
      handle.hover
    end
  end

  # @rbs scroll_top: Numeric? -- Scroll top position
  # @rbs scroll_left: Numeric? -- Scroll left position
  # @rbs return: void -- No return value
  def scroll(scroll_top: nil, scroll_left: nil)
    perform_action('Locator.scroll',
      conditions: [
        method(:ensure_element_is_in_viewport_if_needed),
        method(:wait_for_stable_bounding_box_if_needed),
      ]) do |handle, _options|
      js = <<~JAVASCRIPT
        (el, scrollTop, scrollLeft) => {
          if (scrollTop !== undefined && scrollTop !== null) {
            el.scrollTop = scrollTop;
          }
          if (scrollLeft !== undefined && scrollLeft !== null) {
            el.scrollLeft = scrollLeft;
          }
        }
      JAVASCRIPT
      handle.evaluate(js, scroll_top, scroll_left)
    end
  end

  # @rbs event_name: String -- Event name
  # @rbs block: Proc -- Event handler
  # @rbs return: Puppeteer::Locator -- Locator for chaining
  def on(event_name, &block)
    add_event_listener(event_name, &block)
    self
  end

  # @rbs event_name: String -- Event name
  # @rbs block: Proc -- Event handler
  # @rbs return: Puppeteer::Locator -- Locator for chaining
  def once(event_name, &block)
    observe_first(event_name, &block)
    self
  end

  protected def _clone
    raise NotImplementedError
  end

  protected def _wait(_options)
    raise NotImplementedError
  end

  private def perform_action(name, conditions:, &block)
    with_retry(name) do |options|
      handle = _wait(options)
      begin
        conditions.each do |condition|
          condition.call(handle, options)
        end
        emit_event(Puppeteer::LocatorEvent::Action)
        block.call(handle, options)
        nil
      rescue => err
        begin
          handle.dispose
        rescue StandardError
          # Ignore disposal errors after a failed action.
        end
        raise err
      end
    end
  end

  private def with_retry(_name, &block)
    timeout_controller = TimeoutController.new(@timeout)
    last_error = nil

    loop do
      timeout_controller.check!(last_error)

      options = build_action_options(timeout_controller)
      begin
        return block.call(options)
      rescue => err
        last_error = err
        timeout_controller.check!(last_error)

        Puppeteer::AsyncUtils.sleep_seconds(RETRY_DELAY_SECONDS)
      end
    end
  end

  private def build_action_options(timeout_controller)
    {
      timeout: timeout_controller.remaining_timeout,
      timeout_controller: timeout_controller,
    }
  end

  private def wait_for_enabled_if_needed(handle, options)
    return unless @wait_for_enabled

    js = <<~JAVASCRIPT
      element => {
        if (!(element instanceof HTMLElement)) {
          return true;
        }
        const isNativeFormControl = [
          'BUTTON',
          'INPUT',
          'SELECT',
          'TEXTAREA',
          'OPTION',
          'OPTGROUP',
        ].includes(element.nodeName);
        return !isNativeFormControl || !element.hasAttribute('disabled');
      }
    JAVASCRIPT

    result = handle.frame.wait_for_function(js, args: [handle], timeout: options[:timeout])
    result.dispose
  end

  private def wait_for_stable_bounding_box_if_needed(handle, options)
    return unless @wait_for_stable_bounding_box

    js = <<~JAVASCRIPT
      element => {
        return new Promise(resolve => {
          window.requestAnimationFrame(() => {
            const rect1 = element.getBoundingClientRect();
            window.requestAnimationFrame(() => {
              const rect2 = element.getBoundingClientRect();
              resolve([
                { x: rect1.x, y: rect1.y, width: rect1.width, height: rect1.height },
                { x: rect2.x, y: rect2.y, width: rect2.width, height: rect2.height },
              ]);
            });
          });
        });
      }
    JAVASCRIPT

    loop do
      rects = handle.evaluate(js)
      rect1 = rects[0]
      rect2 = rects[1]
      if rect1 && rect2 &&
         rect1['x'] == rect2['x'] &&
         rect1['y'] == rect2['y'] &&
         rect1['width'] == rect2['width'] &&
         rect1['height'] == rect2['height']

        return
      end

      options[:timeout_controller].check!
      Puppeteer::AsyncUtils.sleep_seconds(RETRY_DELAY_SECONDS)
    end
  end

  private def ensure_element_is_in_viewport_if_needed(handle, options)
    return unless @ensure_element_is_in_viewport

    loop do
      intersects = handle.intersecting_viewport?(threshold: 0)
      return if intersects

      handle.scroll_into_view_if_needed

      intersects = handle.intersecting_viewport?(threshold: 0)
      return if intersects

      options[:timeout_controller].check!
      Puppeteer::AsyncUtils.sleep_seconds(RETRY_DELAY_SECONDS)
    end
  end

  private def fill_element(handle, value)
    input_type = handle.evaluate(<<~JAVASCRIPT)
      el => {
        if (el instanceof HTMLSelectElement) {
          return 'select';
        }
        if (el instanceof HTMLTextAreaElement) {
          return 'typeable-input';
        }
        if (el instanceof HTMLInputElement) {
          if (
            new Set([
              'textarea',
              'text',
              'url',
              'tel',
              'search',
              'password',
              'number',
              'email',
            ]).has(el.type)
          ) {
            return 'typeable-input';
          }
          return 'other-input';
        }

        if (el.isContentEditable) {
          return 'contenteditable';
        }

        return 'unknown';
      }
    JAVASCRIPT

    case input_type
    when 'select'
      handle.select(value)
    when 'contenteditable', 'typeable-input'
      text_to_type = handle.evaluate(<<~JAVASCRIPT, value)
        (input, newValue) => {
          const currentValue = input.isContentEditable
            ? input.innerText
            : input.value;

          if (
            newValue.length <= currentValue.length ||
            !newValue.startsWith(input.value)
          ) {
            if (input.isContentEditable) {
              input.innerText = '';
            } else {
              input.value = '';
            }
            return newValue;
          }
          const originalValue = input.isContentEditable
            ? input.innerText
            : input.value;

          if (input.isContentEditable) {
            input.innerText = '';
            input.innerText = originalValue;
          } else {
            input.value = '';
            input.value = originalValue;
          }
          return newValue.substring(originalValue.length);
        }
      JAVASCRIPT
      text_to_type = text_to_type.to_s
      handle.type_text(text_to_type)
    when 'other-input'
      handle.focus
      handle.evaluate(<<~JAVASCRIPT, value)
        (input, newValue) => {
          input.value = newValue;
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
        }
      JAVASCRIPT
    else
      raise Puppeteer::Error.new('Element cannot be filled out.')
    end
  end
end

class Puppeteer::FunctionLocator < Puppeteer::Locator
  # @rbs page_or_frame: Puppeteer::Page | Puppeteer::Frame -- Page or frame
  # @rbs func: String -- JS function to evaluate
  # @rbs return: Puppeteer::Locator -- Function locator
  def self.create(page_or_frame, func)
    new(page_or_frame, func).set_timeout(default_timeout_for(page_or_frame))
  end

  def initialize(page_or_frame, func)
    super()
    @page_or_frame = page_or_frame
    @func = func
  end

  protected def _clone
    self.class.new(@page_or_frame, @func).copy_options(self)
  end

  protected def _wait(options)
    @page_or_frame.wait_for_function(@func, timeout: options[:timeout])
  end

  def self.default_timeout_for(page_or_frame)
    if page_or_frame.respond_to?(:default_timeout)
      page_or_frame.default_timeout
    else
      page_or_frame.page.default_timeout
    end
  end

  private_class_method :default_timeout_for
end

class Puppeteer::DelegatedLocator < Puppeteer::Locator
  def initialize(delegate)
    super()
    @delegate = delegate
    copy_options(@delegate)
  end

  protected def delegate
    @delegate
  end

  def set_timeout(timeout)
    locator = super
    locator.instance_variable_set(:@delegate, @delegate.set_timeout(timeout))
    locator
  end

  def set_visibility(visibility)
    locator = super
    locator.instance_variable_set(:@delegate, @delegate.set_visibility(visibility))
    locator
  end

  def set_wait_for_enabled(value)
    locator = super
    locator.instance_variable_set(:@delegate, @delegate.set_wait_for_enabled(value))
    locator
  end

  def set_ensure_element_is_in_the_viewport(value)
    locator = super
    locator.instance_variable_set(:@delegate, @delegate.set_ensure_element_is_in_the_viewport(value))
    locator
  end

  def set_wait_for_stable_bounding_box(value)
    locator = super
    locator.instance_variable_set(:@delegate, @delegate.set_wait_for_stable_bounding_box(value))
    locator
  end

  protected def _clone
    raise NotImplementedError
  end

  protected def _wait(_options)
    raise NotImplementedError
  end
end

class Puppeteer::FilteredLocator < Puppeteer::DelegatedLocator
  def initialize(base, predicate)
    super(base)
    @predicate = predicate
  end

  protected def _clone
    self.class.new(delegate.clone, @predicate).copy_options(self)
  end

  protected def _wait(options)
    handle = delegate.send(:_wait, options)
    result = @predicate.call(handle, options)
    return handle if result

    raise Puppeteer::Error.new('Locator predicate did not match')
  end
end

class Puppeteer::MappedLocator < Puppeteer::DelegatedLocator
  def initialize(base, mapper)
    super(base)
    @mapper = mapper
  end

  protected def _clone
    self.class.new(delegate.clone, @mapper).copy_options(self)
  end

  protected def _wait(options)
    handle = delegate.send(:_wait, options)
    @mapper.call(handle, options)
  end
end

class Puppeteer::NodeLocator < Puppeteer::Locator
  # @rbs page_or_frame: Puppeteer::Page | Puppeteer::Frame -- Page or frame
  # @rbs selector: String -- Selector
  # @rbs return: Puppeteer::Locator -- Node locator
  def self.create(page_or_frame, selector)
    new(page_or_frame, selector).set_timeout(default_timeout_for(page_or_frame))
  end

  # @rbs page_or_frame: Puppeteer::Page | Puppeteer::Frame -- Page or frame
  # @rbs handle: Puppeteer::ElementHandle -- Element handle
  # @rbs return: Puppeteer::Locator -- Node locator
  def self.create_from_handle(page_or_frame, handle)
    new(page_or_frame, handle).set_timeout(default_timeout_for(page_or_frame))
  end

  def initialize(page_or_frame, selector_or_handle)
    super()
    @page_or_frame = page_or_frame
    @selector_or_handle = selector_or_handle
  end

  protected def _clone
    self.class.new(@page_or_frame, @selector_or_handle).copy_options(self)
  end

  protected def _wait(options)
    handle = if @selector_or_handle.is_a?(String)
      selector = @selector_or_handle
      if (p_selectors = parse_p_selector(selector))
        wait_for_any_selector(p_selectors, options)
      else
        @page_or_frame.wait_for_selector(selector, visible: false, timeout: options[:timeout])
      end
    else
      @selector_or_handle
    end

    raise Puppeteer::Error.new('No element found for selector') unless handle

    wait_for_visibility_if_needed(handle, options)
    handle
  end

  private def wait_for_visibility_if_needed(handle, options)
    return unless @visibility

    loop do
      case @visibility
      when 'visible'
        return if handle.visible?
      when 'hidden'
        return if handle.hidden?
      end

      options[:timeout_controller].check!
      Puppeteer::AsyncUtils.sleep_seconds(RETRY_DELAY_SECONDS)
    end
  end

  private def parse_p_selector(selector)
    return nil unless selector.include?('::-p-')

    parts = selector.split(',').map(&:strip)
    selectors = parts.map do |part|
      if (match = part.match(/^::\-p\-text\((.*)\)$/))
        "text/#{match[1]}"
      elsif (match = part.match(/^::\-p\-xpath\((.*)\)$/))
        xpath = match[1]
        if xpath.start_with?('/')
          xpath = ".//#{xpath.sub(%r{^/+}, '')}"
        end
        "xpath/#{xpath}"
      else
        return nil
      end
    end
    selectors
  end

  private def wait_for_any_selector(selectors, options)
    loop do
      selectors.each do |selector|
        handle = @page_or_frame.query_selector(selector)
        return handle if handle
      end

      options[:timeout_controller].check!
      Puppeteer::AsyncUtils.sleep_seconds(RETRY_DELAY_SECONDS)
    end
  end

  def self.default_timeout_for(page_or_frame)
    if page_or_frame.respond_to?(:default_timeout)
      page_or_frame.default_timeout
    else
      page_or_frame.page.default_timeout
    end
  end

  private_class_method :default_timeout_for
end

class Puppeteer::RaceLocator < Puppeteer::Locator
  def self.create(locators)
    array = check_locator_array(locators)
    new(array)
  end

  def initialize(locators)
    super()
    @locators = locators
  end

  protected def _clone
    self.class.new(@locators.map(&:clone)).copy_options(self)
  end

  protected def _wait(options)
    tasks = @locators.map do |locator|
      proc { locator.send(:_wait, options) }
    end
    Puppeteer::AsyncUtils.await_promise_race(*tasks)
  end

  def self.check_locator_array(locators)
    unless locators.is_a?(Array)
      raise ArgumentError.new('Unknown locator for race candidate')
    end

    locators.each do |locator|
      unless locator.is_a?(Puppeteer::Locator)
        raise ArgumentError.new('Unknown locator for race candidate')
      end
    end

    locators
  end

  private_class_method :check_locator_array
end
