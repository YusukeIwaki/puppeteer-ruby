# ref: https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/common/Errors.ts

# The base class for all Puppeteer-specific errors
class Puppeteer::Error < StandardError
  attr_writer :cause

  def cause
    @cause || super
  end
end

class Puppeteer::TimeoutError < Puppeteer::Error; end

class Puppeteer::TouchError < Puppeteer::Error; end

class Puppeteer::AbortError < Puppeteer::Error
  def initialize(message = 'aborted')
    super(message)
  end
end
