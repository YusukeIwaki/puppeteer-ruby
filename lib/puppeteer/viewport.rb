class Puppeteer::Viewport
  # @param width [int]
  # @param height [int]
  # @param device_scale_factor [double]
  # @param is_mobile [boolean]
  # @param has_touch [boolean]
  # @param is_landscape [boolean]
  def initialize(
        width:,
        height:,
        device_scale_factor: 1.0,
        is_mobile: false,
        has_touch: false,
        is_landscape: false)
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
