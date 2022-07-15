module Puppeteer::Concurrent
  extend Concurrent::Promises::FactoryMethods

  POOL_SIZE = 8

  @thread_pool = Concurrent::FixedThreadPool.new(POOL_SIZE)

  def self.default_executor
    @thread_pool
  end
end
