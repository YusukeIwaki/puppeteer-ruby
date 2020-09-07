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

  # check if running on macOS
  def darwin?
    RUBY_PLATFORM.include?('darwin')
  end

  # @return [String|NilClass] chrome, firefox, nil
  def product
    (%w(chrome firefox) & [ENV['PUPPETEER_PRODUCT']]).first
  end

  def chrome?
    product == 'chrome'
  end

  def firefox?
    product == 'firefox'
  end
end

class Puppeteer
  def self.env
    Puppeteer::Env.new
  end
end
