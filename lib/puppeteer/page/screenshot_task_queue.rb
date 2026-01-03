class Puppeteer::Page
  class ScreenshotTaskQueue
    def initialize
      @chain = Async::Promise.new.tap { |promise| promise.resolve(nil) }
    end

    def post_task(&block)
      previous = @chain
      result_promise = Async::Promise.new
      @chain = result_promise

      Async do
        begin
          previous.wait
          result = block.call
          result_promise.resolve(result)
        rescue => err
          result_promise.reject(err)
        end
      end

      result_promise.wait
    end
  end
end
