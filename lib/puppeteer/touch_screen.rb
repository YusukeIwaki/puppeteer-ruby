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
    touch.end
  end

  define_async_method :async_tap

  # @rbs x: Numeric -- X coordinate
  # @rbs y: Numeric -- Y coordinate
  # @rbs return: Puppeteer::TouchHandle -- Touch handle
  def touch_start(x, y)
    @touch_id_counter += 1
    touch_point = {
      x: x.round,
      y: y.round,
      radiusX: 0.5,
      radiusY: 0.5,
      force: 0.5,
      id: @touch_id_counter,
    }
    touch = Puppeteer::TouchHandle.new(self, touch_point)
    touch.start
    @touches << touch
    touch
  end

  define_async_method :async_touch_start

  # @rbs x: Numeric -- X coordinate
  # @rbs y: Numeric -- Y coordinate
  # @rbs return: void -- No return value
  def touch_move(x, y)
    touch = @touches.first
    raise Puppeteer::TouchError.new('Must start a new Touch first') unless touch

    touch.move(x, y)
  end

  define_async_method :async_touch_move

  # @rbs return: void -- No return value
  def touch_end
    touch = @touches.shift
    raise Puppeteer::TouchError.new('Must start a new Touch first') unless touch

    touch.end
  end

  define_async_method :async_touch_end

  # @rbs touch: Puppeteer::TouchHandle -- Touch handle to remove
  # @rbs return: void -- No return value
  private def remove_handle(touch)
    index = @touches.index(touch)
    return unless index

    @touches.delete_at(index)
  end

  # @rbs type: String -- Touch event type
  # @rbs touch_points: Array[Hash[Symbol, Numeric]] -- Touch points payload
  # @rbs return: void -- No return value
  private def dispatch_touch_event(type, touch_points)
    @client.send_message('Input.dispatchTouchEvent',
      type: type,
      touchPoints: touch_points,
      modifiers: @keyboard.modifiers,
    )
  end
end
