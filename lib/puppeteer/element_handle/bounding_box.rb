class Puppeteer::ElementHandle < Puppeteer::JSHandle
  class BoundingBox
    def initialize(x:, y:, width:, height:)
      @x = x
      @y = y
      @width = width
      @height = height
    end

    attr_reader :x, :y, :width, :height
  end
end
