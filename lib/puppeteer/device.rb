class Puppeteer::Device
  class Viewport
    # @param width [int]
    # @param height [int]
    # @param device_scale_factor [double]
    # @param is_mobile [boolean]
    # @param has_touch [boolean]
    # @param is_landscape [boolean]
    def initialize(
          width:,
          height:,
          device_scale_factor:,
          is_mobile:,
          has_touch:,
          is_landscape:)
      @width = width
      @height = height
      @device_scale_factor = device_scale_factor
      @is_mobile = is_mobile
      @has_touch = has_touch
      @is_landscape = is_landscape
    end

    attr_reader :width, :height, :device_scale_factor

    def mobile?
      @is_mobile
    end

    def has_touch?
      @has_touch
    end

    def landscape?
      @is_landscape
    end
  end

  # @param name [String]
  # @param user_agent [String]
  # @param viewport [Viewport]
  def initialize(name:, user_agent:, viewport:)
    @name = name
    @user_agent = user_agent
    @viewport = viewport
  end

  attr_reader :name, :user_agent, :viewport
end
