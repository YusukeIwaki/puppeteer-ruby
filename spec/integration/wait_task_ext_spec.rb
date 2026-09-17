require 'spec_helper'

# Ruby-specific coverage for MutationPoller shadow-root observation
# (upstream puppeteer/puppeteer#15292). The upstream regressions use pierce
# selectors, which in this gem are served by PQueryHandler's polling loop;
# these tests exercise the MutationPoller itself through wait_for_function
# with mutation polling.
RSpec.describe 'waittask shadow roots' do
  it 'observes shadow roots added after the wait starts' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      watcher = page.async_wait_for_function(
        "() => document.querySelector('div')?.shadowRoot?.querySelector('h1')?.textContent",
        polling: 'mutation',
        timeout: 5000,
      )
      page.evaluate('(tag) => document.body.appendChild(document.createElement(tag)).attachShadow({mode: "open"})', 'div')
      page.evaluate(<<~JAVASCRIPT)
        () => {
          const h1 = document.createElement('h1');
          h1.textContent = 'inside';
          document.querySelector('div').shadowRoot.appendChild(h1);
        }
      JAVASCRIPT
      expect(watcher.wait.json_value).to eq('inside')
    end
  end

  it 'observes shadow roots that predate the wait' do
    with_test_state do |page:, server:, **|
      page.goto(server.empty_page)
      page.evaluate('(tag) => document.body.appendChild(document.createElement(tag)).attachShadow({mode: "open"})', 'div')
      watcher = page.async_wait_for_function(
        "() => document.querySelector('div')?.shadowRoot?.querySelector('h1')?.textContent",
        polling: 'mutation',
        timeout: 5000,
      )
      page.evaluate(<<~JAVASCRIPT)
        () => {
          const h1 = document.createElement('h1');
          h1.textContent = 'inside';
          document.querySelector('div').shadowRoot.appendChild(h1);
        }
      JAVASCRIPT
      expect(watcher.wait.json_value).to eq('inside')
    end
  end
end
