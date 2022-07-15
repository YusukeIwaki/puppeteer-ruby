require 'spec_helper'

RSpec.describe Puppeteer::Concurrent do
  context 'with button page', sinatra: true do
    before {
      page.goto("#{server_prefix}/input/button.html")
    }

    it 'should click button without spawning too many threads' do
      50.times do |i|
        page.goto("#{server_prefix}/input/button.html")
        page.evaluate("() => {
            new Promise((resolve, reject) => {
              setTimeout(() => {
                resolve();
              }, 0);
            });
          }")
        await_all(
          page.async_click('button'),
        )
      end
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
      expect(Thread.list.count).to be be_within(4).of(Puppeteer::Concurrent::POOL_SIZE)
    end
  end
end
