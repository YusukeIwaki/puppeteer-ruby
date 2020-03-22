require_relative './keyboard/key_description'
require_relative './keyboard/us_keyboard_layout'

class Puppeteer::Keyboard
  using Puppeteer::AsyncAwaitBehavior

  # @param {!Puppeteer.CDPSession} client
  def initialize(client)
    @client = client
    @modifiers = 0
    @pressed_keys = Set.new
  end

  attr_reader :modifiers

  # @param key [String]
  # @param text [String]
  # @return [Future]
  def down(key, text: nil)
    description = key_description_for_string(key)

    auto_repeat = @pressed_keys.include?(description.code)
    @pressed_keys << description.code
    @modifiers |= modifier_bit(description.key)

    sending_text = text || description.text
    params = {
      type: sending_text ? 'keyDown' : 'rawKeyDown',
      modifiers: this._modifiers,
      windowsVirtualKeyCode: description.keyCode,
      code: description.code,
      key: description.key,
      text: sending_text,
      unmodifiedText: sending_text,
      autoRepeat: auto_repeat,
      location: description.location,
      isKeypad: description.location == 3,
    }.compact
    @client.send_message('Input.dispatchKeyEvent', params);
  end

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
    shift = @modifiers & 8
    description = {}
    definition = KEY_DEFINITIONS[key_string]
    if !definition
      raise ArgumentError.new("Unknown key: \"#{keyString}\"")
    end

    if definition.key
      description[:key] = definition.key
    end
    if shift && definition.shift_key
      description[:key] = definition.shift_key
    end

    if definition.key_code
      description[:key_code] = definition.key_code
    end
    if shift && definition.shift_key_code
      description[:key_code] = definition.shift_key_code
    end

    if definition.code
      description[:code] = definition.code
    end

    if definition.location
      description[:location] = definition.location
    end

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
    if @modifiers & ~8
      description[:text] = ''
    end

    KeyDescription.new(**description)
  end

  # @param key [String]
  # @return [Future]
  def up(key)
    description = key_description_for_string(key)

    @modifiers &= ~(modifier_bit(description.key))
    @pressed_keys.delete(description.code)

    @client.send_message('Input.dispatchKeyEvent',
      type: 'keyUp',
      modifiers: @modifiers,
      key: description.key,
      windowsVirtualKeyCode: description.keyCode,
      code: description.code,
      location: description.location,
    )
  end

  # @param char [string]
  # @return [Future]
  def send_character(char)
    @client.send_message('Input.insertText', text: char)
  end

  # @param {string} text
  #
  def type(text, delay: nil)
    text.each_char do |char|
      if KEY_DEFINITIONS.include?(char)
        press(char, delay: delay)
      else
        if delay
          sleep(delay.to_i / 1000.0)
        end
        send_character(char)
      end
    end
  end

  # @param key [String]
  # @return [Future]
  async def press(key, delay: nil)
    await down(key)
    if delay
      sleep(delay.to_i / 1000.0)
    end
    await up(key)
  end
end
