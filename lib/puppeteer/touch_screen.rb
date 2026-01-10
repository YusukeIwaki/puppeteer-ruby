# rbs_inline: enabled

class Puppeteer::TouchScreen
  using Puppeteer::DefineAsyncMethod

  # @rbs client: Puppeteer::CDPSession -- CDP session
  # @rbs keyboard: Puppeteer::Keyboard -- Keyboard state for modifiers
  # @rbs return: void -- No return value
  def initialize(client, keyboard)
    @client = client
    @keyboard = keyboard
    @touch_id_counter = 0
    @touches = []
  end

  # @rbs x: Numeric -- X coordinate
  # @rbs y: Numeric -- Y coordinate
  # @rbs return: void -- No return value
  def tap(x, y)
    touch = touch_start(x, y)
    touch_end_handle(touch)
  end

  define_async_method :async_tap

  # @rbs x: Numeric -- X coordinate
  # @rbs y: Numeric -- Y coordinate
  # @rbs return: Puppeteer::TouchHandle -- Touch handle
  def touch_start(x, y)
    wait_for_touch_frame
    @touch_id_counter += 1
    touch = Puppeteer::TouchHandle.new(self, @touch_id_counter, x: x, y: y)
    @touches << touch
    dispatch_touch_event('touchStart')
    touch
  end

  define_async_method :async_touch_start

  # @rbs x: Numeric -- X coordinate
  # @rbs y: Numeric -- Y coordinate
  # @rbs return: void -- No return value
  def touch_move(x, y)
    touch = @touches.first
    raise ArgumentError.new('No touch points available') unless touch

    touch.move(x, y)
  end

  define_async_method :async_touch_move

  # @rbs return: void -- No return value
  def touch_end
    return if @touches.empty?

    @touches.clear
    dispatch_touch_event('touchEnd')
  end

  define_async_method :async_touch_end

  # @rbs touch: Puppeteer::TouchHandle -- Touch handle to move
  # @rbs return: void -- No return value
  def touch_move_handle(touch)
    assert_active_touch(touch)
    dispatch_touch_event('touchMove')
  end

  # @rbs touch: Puppeteer::TouchHandle -- Touch handle to end
  # @rbs return: void -- No return value
  def touch_end_handle(touch)
    assert_active_touch(touch)
    @touches.delete(touch)
    dispatch_touch_event('touchEnd')
  end

  private def wait_for_touch_frame
    # Touches appear to be lost during the first frame after navigation.
    # This waits a frame before sending the touch.
    # @see https://crbug.com/613219
    @client.send_message('Runtime.evaluate',
      expression: 'new Promise(x => requestAnimationFrame(() => requestAnimationFrame(x)))',
      awaitPromise: true,
    )
  end

  private def dispatch_touch_event(type)
    @client.send_message('Input.dispatchTouchEvent',
      type: type,
      touchPoints: @touches.map { |touch| touch_point(touch) },
      modifiers: @keyboard.modifiers,
    )
  end

  private def touch_point(touch)
    {
      x: touch.x.round,
      y: touch.y.round,
      id: touch.touch_id,
    }
  end

  private def assert_active_touch(touch)
    return if @touches.include?(touch)

    raise ArgumentError.new('Touch handle is not active')
  end
end
