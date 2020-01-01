class Puppeteer::TimeoutSettings
  DEFAULT_TIMEOUT = 30000

  attr_writer :default_timeout, :default_navigation_timeout

  # @return {number}
  def navigation_timeout
    @default_navigation_timeout || @default_timeout || DEFAULT_TIMEOUT
  end

  # @return {number}
  def timeout
    @default_timeout || DEFAULT_TIMEOUT
  end
end
