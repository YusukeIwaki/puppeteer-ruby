require 'logger'

module Puppeteer::DebugPrint
  def debug_puts(*args, **kwargs)
    return unless Puppeteer.env.debug?

    @__debug_logger ||= Logger.new($stdout)
    @__debug_logger.debug(*args, **kwargs)
  end

  def debug_print(*args)
    return unless Puppeteer.env.debug?

    print(*args)
  end
end
