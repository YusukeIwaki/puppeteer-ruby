require 'timeout'

class Puppeteer::TimeoutHelper
  # @param timeout_ms [String|Integer|nil]
  # @param default_timeout_ms [Integer]
  def initialize(task_name, timeout_ms:, default_timeout_ms:)
    @task_name = task_name
    @timeout_ms = (timeout_ms || default_timeout_ms).to_i
  end

  def with_timeout(&block)
    if @timeout_ms > 0
      begin
        Timeout.timeout(@timeout_ms / 1000.0, &block)
      rescue Timeout::Error
        raise Puppeteer::TimeoutError.new("waiting for #{@task_name} failed: timeout #{@timeout_ms}ms exceeded")
      end
    else
      block.call
    end
  end
end
