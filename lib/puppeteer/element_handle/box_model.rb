class Puppeteer::ElementHandle < Puppeteer::JSHandle
  class BoxModel
    QUAD_ATTRIBUTE_NAMES = %i(content padding border margin)
    # @param result [Hash]
    # @param offset [Point]
    def initialize(result_model, offset:)
      QUAD_ATTRIBUTE_NAMES.each do |attr_name|
        quad = result_model[attr_name.to_s]
        instance_variable_set(
          :"@#{attr_name}",
          quad.each_slice(2).map { |x, y| Point.new(x: x, y: y) + offset },
        )
      end
      @width = result_model['width']
      @height = result_model['height']
    end
    attr_reader(*QUAD_ATTRIBUTE_NAMES)
    attr_reader :width, :height
  end
end
