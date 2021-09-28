class Puppeteer::ElementHandle < Puppeteer::JSHandle
  # A class to represent (x, y)-offset coordinates
  class Offset
    def initialize(x:, y:)
      @x = x
      @y = y
    end

    def self.from(offset)
      case offset
      when nil
        nil
      when Hash
        if offset[:x] && offset[:y]
          Offset.new(x: offset[:x], y: offset[:y])
        else
          raise ArgumentError.new('offset parameter must have x, y coordinates')
        end
      when Offset
        offset
      else
        raise ArgumentError.new('Offset.from(Hash|Offset)')
      end
    end

    attr_reader :x, :y
  end
end
