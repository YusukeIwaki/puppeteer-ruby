require 'mime/types'

class Puppeteer::Page
  # /**
  #  * @typedef {Object} ScreenshotOptions
  #  * @property {string=} type
  #  * @property {string=} path
  #  * @property {boolean=} fullPage
  #  * @property {{x: number, y: number, width: number, height: number}=} clip
  #  * @property {number=} quality
  #  * @property {boolean=} omitBackground
  #  * @property {string=} encoding
  #  */
  class ScreenshotOptions
    # @params options [Hash]
    def initialize(options)
      if options[:type]
        unless [:png, :jpeg, :webp].include?(options[:type].to_sym)
          raise ArgumentError.new("Unknown options.type value: #{options[:type]}")
        end
        @type = options[:type]
      elsif options[:path]
        mime_types = MIME::Types.type_for(options[:path])
        if mime_types.include?('image/png')
          @type = 'png'
        elsif mime_types.include?('image/jpeg')
          @type = 'jpeg'
        elsif mime_types.include?('image/webp')
          @type = 'webp'
        else
          raise ArgumentError.new("Unsupported screenshot mime type resolved: #{mime_types}, path: #{options[:path]}")
        end
      end
      @type ||= 'png'

      if options[:quality]
        unless @type == 'jpeg'
          raise ArgumentError.new("options.quality is unsupported for the #{@type} screenshots")
        end
        unless options[:quality].is_a?(Numeric)
          raise ArgumentError.new("Expected options.quality to be a number but found #{options[:quality].class}")
        end
        quality = options[:quality].to_i
        unless (0..100).include?(quality)
          raise ArgumentError.new("Expected options.quality to be between 0 and 100 (inclusive), got #{quality}")
        end
        @quality = quality
      end

      if options[:clip] && options[:full_page]
        raise ArgumentError.new('options.clip and options.fullPage are exclusive')
      end

      # if (options.clip) {
      #   assert(typeof options.clip.x === 'number', 'Expected options.clip.x to be a number but found ' + (typeof options.clip.x));
      #   assert(typeof options.clip.y === 'number', 'Expected options.clip.y to be a number but found ' + (typeof options.clip.y));
      #   assert(typeof options.clip.width === 'number', 'Expected options.clip.width to be a number but found ' + (typeof options.clip.width));
      #   assert(typeof options.clip.height === 'number', 'Expected options.clip.height to be a number but found ' + (typeof options.clip.height));
      #   assert(options.clip.width !== 0, 'Expected options.clip.width not to be 0.');
      #   assert(options.clip.height !== 0, 'Expected options.clip.height not to be 0.');
      # }

      @path = options[:path]
      @full_page = options[:full_page]
      @clip = options[:clip]
      @omit_background = options[:omit_background]
      @encoding = options[:encoding]
    end

    attr_reader :type, :quality, :path, :clip, :encoding

    def full_page?
      @full_page
    end

    def omit_background?
      @omit_background
    end
  end
end
