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
  # @return [Future]
  async def move(x, y, steps: nil)
    move_steps = (steps || 1).to_i

    from_x = @x
    from_y = @y
    @x = x
    @y = y

    return if move_steps <= 0

    move_steps.times do |i|
      n = i + 1
      await @client.send_message('Input.dispatchMouseEvent',
        type: 'mouseMoved',
        button: @button,
        x: from_x + (@x - from_x) * n / steps,
        y: from_y + (@y - from_y) * n / steps,
        modifiers: @keyboard.modifiers,
      )
    end
  end

  # @param x [number]
  # @param y [number]
  # @param {!{delay?: number, button?: "left"|"right"|"middle", clickCount?: number}=} options
  # @return [Future]
  async def click(x, y, delay: nil, button: nil, click_count: nil)
    if delay
      await Concurrent::Promises.zip(
        move(x, y),
        down(button: button, click_count: click_count),
      )
      sleep(delay / 1000.0)
      await up(button: button, click_count: click_count)
    else
      await Concurrent::Promises.zip(
        move(x, y),
        down(button: button, click_count: click_count),
        up(button: button, click_count: click_count),
      )
    end
  end

  # @param {!{button?: "left"|"right"|"middle", clickCount?: number}=} options
  # @return [Future]
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

  # @param {!{button?: "left"|"right"|"middle", clickCount?: number}=} options
  # @return [Future]
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
end
