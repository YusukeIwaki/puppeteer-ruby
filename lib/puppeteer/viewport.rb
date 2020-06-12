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

  def merge(
        width: nil,
        height: nil,
        device_scale_factor: nil,
        is_mobile: nil,
        has_touch: nil,
        is_landscape: nil)

    Puppeteer::Viewport.new(
      width: width || @width,
      height: height || @height,
      device_scale_factor: device_scale_factor || @device_scale_factor,
      is_mobile: is_mobile.nil? ? @is_mobile : is_mobile,
      has_touch: has_touch.nil? ? @has_touch : has_touch,
      is_landscape: is_landscape.nil? ? @is_landscape : is_landscape,
    )
  end
end
