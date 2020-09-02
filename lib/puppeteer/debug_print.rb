require 'logger'

module Puppeteer::DebugPrint
  if Puppeteer.env.debug?
    def debug_puts(*args, **kwargs)
      @__debug_logger ||= Logger.new($stdout)
      @__debug_logger.debug(*args, **kwargs)
    end

    def debug_print(*args)
      print(*args)
    end
  else
    def debug_puts(*args, **kwargs)
    end

    def debug_print(*args)
    end
  end
end
