# rbs_inline: enabled

class Puppeteer::TouchHandle
  # @rbs touchscreen: Puppeteer::TouchScreen -- Touchscreen instance
  # @rbs touch_id: Integer -- Touch identifier
  # @rbs x: Numeric -- X coordinate
  # @rbs y: Numeric -- Y coordinate
  # @rbs return: void -- No return value
  def initialize(touchscreen, touch_id, x:, y:)
    @touchscreen = touchscreen
    @touch_id = touch_id
    @x = x
    @y = y
  end

  attr_reader :touch_id, :x, :y

  # @rbs x: Numeric -- New X coordinate
  # @rbs y: Numeric -- New Y coordinate
  # @rbs return: void -- No return value
  def move(x, y)
    @x = x
    @y = y
    @touchscreen.touch_move_handle(self)
  end

  # @rbs return: void -- No return value
  def end
    @touchscreen.touch_end_handle(self)
  end
end
