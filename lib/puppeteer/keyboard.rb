require_relative './keyboard/key_description'
require_relative './keyboard/us_keyboard_layout'

class Puppeteer::Keyboard
  using Puppeteer::DefineAsyncMethod

  # @param {!Puppeteer.CDPSession} client
  def initialize(client)
    @client = client
    @modifiers = 0
    @pressed_keys = Set.new
  end

  attr_reader :modifiers

  # @param key [String]
  # @param text [String]
  def down(key, text: nil, commands: nil)
    description = key_description_for_string(key)

    auto_repeat = @pressed_keys.include?(description.code)
    @pressed_keys << description.code
    @modifiers |= modifier_bit(description.key)

    sending_text = text || description.text
    params = {
      type: sending_text ? 'keyDown' : 'rawKeyDown',
      modifiers: @modifiers,
      windowsVirtualKeyCode: description.key_code,
      code: description.code,
      key: description.key,
      text: sending_text,
      unmodifiedText: sending_text,
      autoRepeat: auto_repeat,
      location: description.location,
      isKeypad: description.location == 3,
      commands: commands,
    }.compact
    @client.send_message('Input.dispatchKeyEvent', params)
  end

  define_async_method :async_down

  # @param {string} key
  # @return {number}
  private def modifier_bit(key)
    case key
    when 'Alt'
      1
    when 'Control'
      2
    when 'Meta'
      4
    when 'Shift'
      8
    else
      0
    end
  end

  # @param {string} keyString
  # @return {KeyDescription}
  private def key_description_for_string(key_string)
    shift = (@modifiers & 8) != 0
    description = {}
    definition = KEY_DEFINITIONS[key_string.to_sym]
    if !definition
      raise ArgumentError.new("Unknown key: \"#{key_string}\"")
    end

    if definition.key
      description[:key] = definition.key
    end
    if shift && definition.shift_key
      description[:key] = definition.shift_key
    end

    description[:key_code] = definition.key_code || 0

    if shift && definition.shift_key_code
      description[:key_code] = definition.shift_key_code
    end

    if definition.code
      description[:code] = definition.code
    end

    description[:location] = definition.location || 0

    if description[:key].length == 1
      description[:text] = description[:key]
    end

    if definition.text
      description[:text] = definition.text
    end
    if shift && definition.shift_text
      description[:text] = definition.shift_text
    end

    # if any modifiers besides shift are pressed, no text should be sent
    if (@modifiers & ~8) != 0
      description[:text] = ''
    end

    KeyDescription.new(**description)
  end

  # @param key [String]
  def up(key)
    description = key_description_for_string(key)

    @modifiers &= ~(modifier_bit(description.key))
    @pressed_keys.delete(description.code)

    @client.send_message('Input.dispatchKeyEvent',
      type: 'keyUp',
      modifiers: @modifiers,
      key: description.key,
      windowsVirtualKeyCode: description.key_code,
      code: description.code,
      location: description.location,
    )
  end

  define_async_method :async_up

  # @param char [string]
  def send_character(char)
    @client.send_message('Input.insertText', text: char)
  end

  define_async_method :async_send_character

  # @param text [String]
  # @return [Future]
  def type_text(text, delay: nil)
    text.each_char do |char|
      if KEY_DEFINITIONS.include?(char.to_sym)
        press(char, delay: delay)
      else
        if delay
          Puppeteer::AsyncUtils.sleep_seconds(delay.to_i / 1000.0)
        end
        send_character(char)
      end
    end
  end

  define_async_method :async_type_text

  # @param key [String]
  # @param text [String]
  # @return [Future]
  def press(key, delay: nil, text: nil, commands: nil, &block)
    down(key, text: text, commands: commands)
    if delay
      Puppeteer::AsyncUtils.sleep_seconds(delay.to_i / 1000.0)
    end
    if block
      block.call
      if delay
        Puppeteer::AsyncUtils.sleep_seconds(delay.to_i / 1000.0)
      end
    end
    up(key)
  end

  define_async_method :async_press
end
