class Puppeteer::TouchScreen
  using Puppeteer::DefineAsyncMethod

  # @param {Puppeteer.CDPSession} client
  # @param keyboard [Puppeteer::Keyboard]
  def initialize(client, keyboard)
    @client = client
    @keyboard = keyboard
  end

  # @param x [number]
  # @param y [number]
  def tap(x, y)
    # Touches appear to be lost during the first frame after navigation.
    # This waits a frame before sending the tap.
    # @see https://crbug.com/613219
    @client.send_message('Runtime.evaluate',
      expression: 'new Promise(x => requestAnimationFrame(() => requestAnimationFrame(x)))',
      awaitPromise: true,
    )

    touch_points = [
      { x: x.round, y: y.round },
    ]
    @client.send_message('Input.dispatchTouchEvent',
      type: 'touchStart',
      touchPoints: touch_points,
      modifiers: @keyboard.modifiers,
    )
    @client.send_message('Input.dispatchTouchEvent',
      type: 'touchEnd',
      touchPoints: [],
      modifiers: @keyboard.modifiers,
    )
  end

  define_async_method :async_tap
end
