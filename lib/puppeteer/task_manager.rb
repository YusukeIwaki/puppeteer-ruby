class Puppeteer::TaskManager
  def initialize
    @tasks = Set.new
  end

  def add(task)
    @tasks << task
  end

  def delete(task)
    @tasks.delete(task)
  end

  def terminate_all(error)
    @tasks.each do |task|
      task.terminate(error)
    end
    @tasks.clear
  end

  def async_rerun_all
    Async do
      Puppeteer::AsyncUtils.await_promise_all(*@tasks.map(&:async_rerun))
    end
  end
end
