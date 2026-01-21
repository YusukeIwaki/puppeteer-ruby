# ref: https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/common/Errors.ts

# The base class for all Puppeteer-specific errors
class Puppeteer::Error < StandardError
  attr_writer :cause

  def cause
    return nil if @cause.equal?(self)

    stack = Thread.current[:puppeteer_cause_stack] ||= []
    return nil if stack.include?(object_id)

    stack << object_id
    begin
      @cause || super
    ensure
      stack.pop
      Thread.current[:puppeteer_cause_stack] = nil if stack.empty?
    end
  end
end

class Puppeteer::TimeoutError < Puppeteer::Error; end

class Puppeteer::TouchError < Puppeteer::Error; end
