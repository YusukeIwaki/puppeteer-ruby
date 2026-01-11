# rbs_inline: enabled

class Puppeteer::TouchHandle
  # @rbs touchscreen: Puppeteer::TouchScreen -- Touchscreen instance
  # @rbs touch_point: Hash[Symbol, Numeric] -- Touch point payload
  # @rbs return: void -- No return value
  def initialize(touchscreen, touch_point)
    @touchscreen = touchscreen
    @touch_point = touch_point
    @started = false
  end

  attr_reader :touch_point

  # @rbs return: void -- No return value
  def start
    if @started
      raise Puppeteer::TouchError.new('Touch has already started')
    end

    @touchscreen.send(:dispatch_touch_event, 'touchStart', [@touch_point])
    @started = true
  end

  # @rbs x: Numeric -- New X coordinate
  # @rbs y: Numeric -- New Y coordinate
  # @rbs return: void -- No return value
  def move(x, y)
    @touch_point[:x] = x.round
    @touch_point[:y] = y.round
    @touchscreen.send(:dispatch_touch_event, 'touchMove', [@touch_point])
  end

  # @rbs return: void -- No return value
  def end
    @touchscreen.send(:dispatch_touch_event, 'touchEnd', [@touch_point])
    @touchscreen.send(:remove_handle, self)
  end
end
