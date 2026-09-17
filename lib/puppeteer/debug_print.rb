require 'logger'

# Debug channel prefixes for the experimental logger factory
# (Puppeteer.launch/connect `logger:` option). Only CDP-relevant channels
# are exposed; WebDriver BiDi channels do not exist in this gem.
module Puppeteer::DebugPrefixes
  CDP_SEND = 'puppeteer:protocol:SEND ►'
  CDP_RECEIVE = 'puppeteer:protocol:RECV ◀'
  ERROR = 'puppeteer:error'
  FFMPEG = 'puppeteer:ffmpeg'
end

# A logger factory receives a debug channel prefix (see
# Puppeteer::DebugPrefixes) and returns a callable emitting logs for that
# channel, or nil when logging is disabled for it. Logging calls must use
# safe navigation (`logger&.call(prefix)&.call(message)`) so a disabled
# channel never crashes.
#
# Example:
#   logger = ->(prefix) do
#     next unless prefix.include?('protocol')
#     ->(*args) { puts("[DEBUG: #{prefix}] #{args.join(' ')}") }
#   end
#   Puppeteer.launch(logger: logger)
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
