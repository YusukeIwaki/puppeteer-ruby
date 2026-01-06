# rbs_inline: enabled

class Puppeteer::Mouse
  using Puppeteer::DefineAsyncMethod

  module Button
    NONE = 'none'
    LEFT = 'left'
    RIGHT = 'right'
    MIDDLE = 'middle'
    BACK = 'back'
    FORWARD = 'forward'
  end

  module ButtonFlag
    NONE = 0
    LEFT = 1
    RIGHT = 1 << 1
    MIDDLE = 1 << 2
    BACK = 1 << 3
    FORWARD = 1 << 4
  end

  # @rbs client: Puppeteer::CDPSession -- CDP session
  # @rbs keyboard: Puppeteer::Keyboard -- Keyboard instance
  # @rbs return: void -- No return value
  def initialize(client, keyboard)
    @client = client
    @keyboard = keyboard

    @base_state = {
      position: {
        x: 0,
        y: 0,
      },
      buttons: ButtonFlag::NONE,
    }
    @transactions = []
    @state_mutex = Mutex.new
    @dispatch_mutex = Mutex.new
  end

  # @rbs return: void -- No return value
  def reset
    [
      [ButtonFlag::RIGHT, Button::RIGHT],
      [ButtonFlag::MIDDLE, Button::MIDDLE],
      [ButtonFlag::LEFT, Button::LEFT],
      [ButtonFlag::FORWARD, Button::FORWARD],
      [ButtonFlag::BACK, Button::BACK],
    ].each do |flag, button|
      up(button: button) if (state[:buttons] & flag) != 0
    end
    if state[:position][:x] != 0 || state[:position][:y] != 0
      move(0, 0)
    end
  end

  define_async_method :async_reset

  # @rbs x: Numeric -- X coordinate
  # @rbs y: Numeric -- Y coordinate
  # @rbs steps: Integer? -- Number of intermediate steps
  # @rbs return: void -- No return value
  def move(x, y, steps: nil)
    move_steps = (steps || 1).to_i

    from = state[:position]
    to = {
      x: x,
      y: y,
    }

    return if move_steps <= 0

    1.upto(move_steps) do |i|
      with_transaction do |update_state|
        update_state.call(
          position: {
            x: from[:x] + (to[:x] - from[:x]) * i / move_steps.to_f,
            y: from[:y] + (to[:y] - from[:y]) * i / move_steps.to_f,
          },
        )
        current_state = state
        buttons = current_state[:buttons]
        position = current_state[:position]
        @client.send_message('Input.dispatchMouseEvent',
          type: 'mouseMoved',
          modifiers: @keyboard.modifiers,
          buttons: buttons,
          button: button_from_pressed_buttons(buttons),
          x: position[:x],
          y: position[:y],
        )
      end
    end
  end

  define_async_method :async_move

  # @rbs x: Numeric -- X coordinate
  # @rbs y: Numeric -- Y coordinate
  # @rbs delay: Numeric? -- Delay between down and up (ms)
  # @rbs button: String? -- Mouse button
  # @rbs click_count: Integer? -- Click count to report
  # @rbs count: Integer? -- Number of click repetitions
  # @rbs return: void -- No return value
  def click(x, y, delay: nil, button: nil, click_count: nil, count: nil)
    count ||= 1
    click_count ||= count
    if count < 1
      raise Puppeteer::Error.new('Click must occur a positive number of times.')
    end
    # Serialize click sequences to keep event ordering stable under thread-based concurrency.
    @dispatch_mutex.synchronize do
      move(x, y)
      if click_count == count
        1.upto(count - 1) do |i|
          down(button: button, click_count: i)
          up(button: button, click_count: i)
        end
      end
      down(button: button, click_count: click_count)
      if !delay.nil?
        Puppeteer::AsyncUtils.sleep_seconds(delay / 1000.0)
      end
      up(button: button, click_count: click_count)
    end
  end

  define_async_method :async_click

  # @rbs button: String? -- Mouse button
  # @rbs click_count: Integer? -- Click count to report
  # @rbs return: void -- No return value
  def down(button: nil, click_count: nil)
    button ||= Button::LEFT
    flag = button_flag(button)
    with_transaction do |update_state|
      update_state.call(
        buttons: state[:buttons] | flag,
      )
      current_state = state
      position = current_state[:position]
      @client.send_message('Input.dispatchMouseEvent',
        type: 'mousePressed',
        modifiers: @keyboard.modifiers,
        clickCount: click_count || 1,
        buttons: current_state[:buttons],
        button: button,
        x: position[:x],
        y: position[:y],
      )
    end
  end

  define_async_method :async_down

  # @rbs button: String? -- Mouse button
  # @rbs click_count: Integer? -- Click count to report
  # @rbs return: void -- No return value
  def up(button: nil, click_count: nil)
    button ||= Button::LEFT
    flag = button_flag(button)
    with_transaction do |update_state|
      update_state.call(
        buttons: state[:buttons] & ~flag,
      )
      current_state = state
      position = current_state[:position]
      @client.send_message('Input.dispatchMouseEvent',
        type: 'mouseReleased',
        modifiers: @keyboard.modifiers,
        clickCount: click_count || 1,
        buttons: current_state[:buttons],
        button: button,
        x: position[:x],
        y: position[:y],
      )
    end
  end

  define_async_method :async_up

  # Dispatches a `mousewheel` event.
  #
  # @rbs delta_x: Numeric -- Scroll delta X
  # @rbs delta_y: Numeric -- Scroll delta Y
  # @rbs return: void -- No return value
  def wheel(delta_x: 0, delta_y: 0)
    current_state = state
    position = current_state[:position]
    @client.send_message('Input.dispatchMouseEvent',
      type: 'mouseWheel',
      x: position[:x],
      y: position[:y],
      deltaX: delta_x,
      deltaY: delta_y,
      modifiers: @keyboard.modifiers,
      pointerType: 'mouse',
      buttons: current_state[:buttons],
    )
  end

  # @rbs start: Puppeteer::ElementHandle::Point -- Drag start point
  # @rbs target: Puppeteer::ElementHandle::Point -- Drag end point
  # @rbs return: Hash[String, untyped] -- Drag data payload
  def drag(start, target)
    promise = Async::Promise.new.tap do |future|
      @client.once('Input.dragIntercepted') do |event|
        future.resolve(event['data'])
      end
    end
    move(start.x, start.y)
    down
    move(target.x, target.y)
    promise.wait
  end

  # @rbs target: Puppeteer::ElementHandle::Point -- Drag target point
  # @rbs data: Hash[String, untyped] -- Drag data payload
  # @rbs return: void -- No return value
  def drag_enter(target, data)
    @client.send_message('Input.dispatchDragEvent',
      type: 'dragEnter',
      x: target.x,
      y: target.y,
      modifiers: @keyboard.modifiers,
      data: data,
    )
  end

  # @rbs target: Puppeteer::ElementHandle::Point -- Drag target point
  # @rbs data: Hash[String, untyped] -- Drag data payload
  # @rbs return: void -- No return value
  def drag_over(target, data)
    @client.send_message('Input.dispatchDragEvent',
      type: 'dragOver',
      x: target.x,
      y: target.y,
      modifiers: @keyboard.modifiers,
      data: data,
    )
  end

  # @rbs target: Puppeteer::ElementHandle::Point -- Drag target point
  # @rbs data: Hash[String, untyped] -- Drag data payload
  # @rbs return: void -- No return value
  def drop(target, data)
    @client.send_message('Input.dispatchDragEvent',
      type: 'drop',
      x: target.x,
      y: target.y,
      modifiers: @keyboard.modifiers,
      data: data,
    )
  end

  # @rbs start: Puppeteer::ElementHandle::Point -- Drag start point
  # @rbs target: Puppeteer::ElementHandle::Point -- Drag end point
  # @rbs delay: Numeric? -- Delay before drop (ms)
  # @rbs return: void -- No return value
  def drag_and_drop(start, target, delay: nil)
    data = drag(start, target)
    drag_enter(target, data)
    drag_over(target, data)
    if delay
      Puppeteer::AsyncUtils.sleep_seconds(delay / 1000.0)
    end
    drop(target, data)
    up
  end

  private def state
    @state_mutex.synchronize do
      merged = {
        position: {
          x: @base_state[:position][:x],
          y: @base_state[:position][:y],
        },
        buttons: @base_state[:buttons],
      }
      @transactions.each do |transaction|
        if transaction.key?(:position)
          merged[:position] = transaction[:position]
        end
        if transaction.key?(:buttons)
          merged[:buttons] = transaction[:buttons]
        end
      end
      merged
    end
  end

  # @rbs block: Proc -- Block receiving state update callback
  # @rbs return: untyped -- Block result
  private def with_transaction(&block)
    transaction = {}
    @state_mutex.synchronize do
      @transactions << transaction
    end

    begin
      update_state = lambda do |updates|
        @state_mutex.synchronize do
          transaction.merge!(updates)
        end
      end
      block.call(update_state)

      @state_mutex.synchronize do
        @base_state = merge_state(@base_state, transaction)
        @transactions.delete(transaction)
      end
    rescue
      @state_mutex.synchronize do
        @transactions.delete(transaction)
      end
      raise
    end
  end

  private def merge_state(base_state, transaction)
    merged = base_state.dup
    merged[:position] = transaction[:position] if transaction.key?(:position)
    merged[:buttons] = transaction[:buttons] if transaction.key?(:buttons)
    merged
  end

  private def button_flag(button)
    case button
    when Button::LEFT
      ButtonFlag::LEFT
    when Button::RIGHT
      ButtonFlag::RIGHT
    when Button::MIDDLE
      ButtonFlag::MIDDLE
    when Button::BACK
      ButtonFlag::BACK
    when Button::FORWARD
      ButtonFlag::FORWARD
    else
      raise Puppeteer::Error.new("Unsupported mouse button: #{button}")
    end
  end

  private def button_from_pressed_buttons(buttons)
    if (buttons & ButtonFlag::LEFT) != 0
      Button::LEFT
    elsif (buttons & ButtonFlag::RIGHT) != 0
      Button::RIGHT
    elsif (buttons & ButtonFlag::MIDDLE) != 0
      Button::MIDDLE
    elsif (buttons & ButtonFlag::BACK) != 0
      Button::BACK
    elsif (buttons & ButtonFlag::FORWARD) != 0
      Button::FORWARD
    else
      Button::NONE
    end
  end
end
