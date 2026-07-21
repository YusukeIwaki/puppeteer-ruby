require 'spec_helper'

RSpec.describe 'Workers (Ruby-specific regression coverage)' do
  it 'should timeout if the predicate promise never settles' do
    with_test_state do |page:, **|
      worker_created = Async::Promise.new
      page.once('workercreated') { |worker| worker_created.resolve(worker) }
      page.evaluate('() => new Worker("data:text/javascript,1")')
      worker = worker_created.wait

      expect do
        worker.wait_for_function('() => new Promise(() => {})', timeout: 50)
      end.to raise_error(Puppeteer::WaitTask::TimeoutError, /Waiting failed/)
    end
  end
end
