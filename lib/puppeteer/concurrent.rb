module Puppeteer::Concurrent
  extend Concurrent::Promises::FactoryMethods

  @thread_pool = Concurrent::FixedThreadPool.new(5)

  def self.default_executor
    @thread_pool
  end
end
