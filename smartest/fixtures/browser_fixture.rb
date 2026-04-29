# frozen_string_literal: true

class BrowserFixture < Smartest::Fixture
  class << self
    def ensure_browser!
      $shared_browser_mutex ||= Mutex.new
      $shared_browser_mutex.synchronize do
        if $shared_browser&.connected?
          $shared_browser
        else
          browser = Puppeteer.launch(**$default_launch_options)
          $shared_browser = browser
          ($shared_browsers ||= []) << browser
          browser
        end
      end
    end

    def close_all!
      ($shared_browsers || []).reverse_each do |browser|
        browser.close if browser&.connected?
      rescue StandardError
        nil
      end
    ensure
      $shared_browsers = []
      $shared_browser = nil
    end
  end

  suite_fixture :browser do
    browser = BrowserFixture.ensure_browser!
    cleanup do
      BrowserFixture.close_all!
    end
    browser
  end
end
