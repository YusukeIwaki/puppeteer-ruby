class Puppeteer::Env
  # indicates whether DEBUG=1 is specified.
  #
  # @return [Boolean]
  def debug?
    ['1', 'true'].include?(ENV['DEBUG'])
  end
end

class Puppeteer
  def self.env
    Puppeteer::Env.new
  end
end
