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
  # @param location [Location]
  def initialize(log_type, text, args, location)
    @log_type = log_type
    @text = text
    @args = args
    @location = location
  end

  attr_reader :log_type, :text, :args, :location
end
