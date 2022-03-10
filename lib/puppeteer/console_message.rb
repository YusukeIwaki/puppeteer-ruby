class Puppeteer::ConsoleMessage
  class Location
    def initialize(url:, line_number:, column_number: nil)
      @url = url
      @line_number = line_number
      @column_number = column_number
    end

    attr_reader :url, :line_number, :column_number
  end

  # @param log_type [String]
  # @param text [String]
  # @param args [Array<Puppeteer::JSHandle>]
  # @param stack_trace_locations [Array<Location>]
  def initialize(log_type, text, args, stack_trace_locations)
    @log_type = log_type
    @text = text
    @args = args
    @stack_trace_locations = stack_trace_locations
  end

  attr_reader :log_type, :text, :args

  # @return [Location]
  def location
    @stack_trace_locations.first
  end

  # @return [Array<Location>]
  def stack_trace
    @stack_trace_locations
  end
end
