class Puppeteer::ElementHandle < Puppeteer::JSHandle
  # A class to represent (x, y)-coordinates
  # supporting + and / operators.
  class Point
    def initialize(x:, y:)
      @x = x
      @y = y
    end

    def +(other)
      Point.new(
        x: @x + other.x,
        y: @y + other.y,
      )
    end

    def /(num)
      Point.new(
        x: @x / num,
        y: @y / num,
      )
    end

    def ==(other)
      case other
      when Hash
        @x == other[:x] && @y == other[:y]
      when Point
        @x == other.x && @y == other.y
      else
        super
      end
    end

    attr_reader :x, :y
  end
end
