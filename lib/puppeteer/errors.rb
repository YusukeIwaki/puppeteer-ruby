# ref: https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/common/Errors.ts

# The base class for all Puppeteer-specific errors
class Puppeteer::Error < StandardError; end

class Puppeteer::TimeoutError < Puppeteer::Error; end
