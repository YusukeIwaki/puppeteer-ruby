class Puppeteer::Keyboard
  #  * @typedef {Object} KeyDescription
  #  * @property {number} keyCode
  #  * @property {string} key
  #  * @property {string} text
  #  * @property {string} code
  #  * @property {number} location
  class KeyDescription
    def initialize(key_code: nil, key: nil, text: nil, code: nil, location: nil)
      @key_code = key_code
      @key = key
      @text = text
      @code = code
      @location = location
    end

    attr_reader :key_code, :key, :text, :code, :location
  end
end
