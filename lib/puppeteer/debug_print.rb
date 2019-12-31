require 'logger'

module Puppeteer::DebugPrint
  def debug_print(*args, **kwargs)
    @__debug_logger ||= Logger.new(STDOUT)
    @__debug_logger.debug(*args, **kwargs)
  end
end
