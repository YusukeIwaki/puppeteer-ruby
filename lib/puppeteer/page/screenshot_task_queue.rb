class Puppeteer::Page
  class ScreenshotTaskQueue
    def initialize
      @chain = Concurrent::Promises.fulfilled_future(nil)
    end

    def post_task(&block)
      result = @chain.then { block.call }
      @chain = result.rescue { nil }
      result.value!
    end
  end
end
