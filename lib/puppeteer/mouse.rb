class Puppeteer::Mouse
  using Puppeteer::AsyncAwaitBehavior

  module Button
    NONE = 'none'
    LEFT = 'left'
    RIGHT = 'right'
    MIDDLE = 'middle'
  end

  # @param {Puppeteer.CDPSession} client
  # @param keyboard [Puppeteer::Keyboard]
  def initialize(client, keyboard)
    @client = client
    @keyboard = keyboard

    @x = 0
    @y = 0
    @button = Button::NONE
  end

  # @param x [number]
  # @param y [number]
  # @param steps [number]
  def move(x, y, steps: nil)
    move_steps = (steps || 1).to_i

    from_x = @x
    from_y = @y
    @x = x
    @y = y

    return if move_steps <= 0

    move_steps.times do |i|
      n = i + 1
      @client.send_message('Input.dispatchMouseEvent',
        type: 'mouseMoved',
        button: @button,
        x: from_x + (@x - from_x) * n / move_steps,
        y: from_y + (@y - from_y) * n / move_steps,
        modifiers: @keyboard.modifiers,
      )
    end
  end

  define_async_method_for :move

  # @param x [number]
  # @param y [number]
  # @param {!{delay?: number, button?: "left"|"right"|"middle", clickCount?: number}=} options
  def click(x, y, delay: nil, button: nil, click_count: nil)
    # await_all(async_move, async_down, async_up) often breaks the order of CDP commands.
    # D, [2020-04-15T17:09:47.895895 #88683] DEBUG -- : RECV << {"id"=>23, "result"=>{"layoutViewport"=>{"pageX"=>0, "pageY"=>1, "clientWidth"=>375, "clientHeight"=>667}, "visualViewport"=>{"offsetX"=>0, "offsetY"=>0, "pageX"=>0, "pageY"=>1, "clientWidth"=>375, "clientHeight"=>667, "scale"=>1, "zoom"=>1}, "contentSize"=>{"x"=>0, "y"=>0, "width"=>375, "height"=>2007}}, "sessionId"=>"0B09EA5E18DEE403E525B3E7FCD7E225"}
    # D, [2020-04-15T17:09:47.898422 #88683] DEBUG -- : SEND >> {"sessionId":"0B09EA5E18DEE403E525B3E7FCD7E225","method":"Input.dispatchMouseEvent","params":{"type":"mouseReleased","button":"left","x":0,"y":0,"modifiers":0,"clickCount":1},"id":24}
    # D, [2020-04-15T17:09:47.899711 #88683] DEBUG -- : SEND >> {"sessionId":"0B09EA5E18DEE403E525B3E7FCD7E225","method":"Input.dispatchMouseEvent","params":{"type":"mousePressed","button":"left","x":0,"y":0,"modifiers":0,"clickCount":1},"id":25}
    # D, [2020-04-15T17:09:47.900237 #88683] DEBUG -- : SEND >> {"sessionId":"0B09EA5E18DEE403E525B3E7FCD7E225","method":"Input.dispatchMouseEvent","params":{"type":"mouseMoved","button":"left","x":187,"y":283,"modifiers":0},"id":26}
    # So we execute them sequential
    move(x, y)
    down(button: button, click_count: click_count)
    if delay
      sleep(delay / 1000.0)
    end
    up(button: button, click_count: click_count)
  end

  define_async_method_for :click

  # @param {!{button?: "left"|"right"|"middle", clickCount?: number}=} options
  def down(button: nil, click_count: nil)
    @button = button || Button::LEFT
    @client.send_message('Input.dispatchMouseEvent',
      type: 'mousePressed',
      button: @button,
      x: @x,
      y: @y,
      modifiers: @keyboard.modifiers,
      clickCount: click_count || 1,
    )
  end

  define_async_method_for :down

  # @param {!{button?: "left"|"right"|"middle", clickCount?: number}=} options
  def up(button: nil, click_count: nil)
    @button = Button::NONE
    @client.send_message('Input.dispatchMouseEvent',
      type: 'mouseReleased',
      button: button || Button::LEFT,
      x: @x,
      y: @y,
      modifiers: @keyboard.modifiers,
      clickCount: click_count || 1,
    )
  end

  define_async_method_for :up
end
