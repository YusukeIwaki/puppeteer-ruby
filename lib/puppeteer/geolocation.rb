class Puppeteer::Geolocation
  # @param latitude [Fixnum]
  # @param longitude [Fixnum]
  # @param accuracy [Fixnum]
  def initialize(latitude:, longitude:, accuracy: 0)
    unless (-180..180).include?(longitude)
      raise ArgumentError.new("Invalid longitude \"#{longitude}\": precondition -180 <= LONGITUDE <= 180 failed.")
    end
    unless (-90..90).include?(latitude)
      raise ArgumentError.new("Invalid latitude \"#{latitude}\": precondition -90 <= LATITUDE <= 90 failed.")
    end
    if accuracy < 0
      raise ArgumentError.new("Invalid accuracy \"#{longitude}\": precondition 0 <= ACCURACY failed.")
    end

    @latitude = latitude
    @longitude = longitude
    @accuracy = accuracy
  end

  def to_h
    { latitude: @latitude, longitude: @longitude, accuracy: @accuracy }
  end
end
