require 'test_helper'

describe 'Page issue events' do
  include Utils::WaitEvent

  it 'should emit issue event when CSP violation occurs', sinatra: true do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/csp.html")
      issue_promise = async_promise { wait_for_event(page, 'issue') }
      page.add_script_tag(content: 'console.log("CSP test")')
      issue = issue_promise.wait
      expect(issue).not_to be_nil
      expect(issue.code).to eq('ContentSecurityPolicyIssue')
    end
  end

  it 'should be able to disable issues support', sinatra: true do
    with_browser(issues_enabled: false) do |browser|
      with_test_state(browser: browser) do |page:, server:, **|
        issue_emitted = false
        listener = ->(_issue) { issue_emitted = true }
        page.on('issue', &listener)
        page.goto("#{server.prefix}/csp.html")
        Puppeteer::AsyncUtils.sleep_seconds(0.3)
        expect(issue_emitted).to eq(false)
      ensure
        page&.off('issue', listener)
      end
    end
  end
end
