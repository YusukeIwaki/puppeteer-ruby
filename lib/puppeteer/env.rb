class Puppeteer::Env
  # indicates whether DEBUG=1 is specified.
  #
  # @return [Boolean]
  def debug?
    ['1', 'true'].include?(ENV['DEBUG'].to_s)
  end

  def ci?
    ['1', 'true'].include?(ENV['CI'].to_s)
  end
end

class Puppeteer
  def self.env
    Puppeteer::Env.new
  end
end
