require 'spec_helper'

# Ruby-specific coverage for the shared screencast session: the one-shot
# Page.screencastFrame listener must be registered before Page.startScreencast
# is sent; otherwise the first frame can arrive unobserved and startup hangs.
# See upstream puppeteer/puppeteer#15389.
RSpec.describe 'Screencasts extensions' do
  describe 'Page.screencast' do
    it 'does not miss the first screencast frame on startup' do
      with_test_state do |page:, **|
        Timeout.timeout(15) do
          recorder = page.screencast
          page.goto('data:text/html,hello')
          sleep 1 # let frames arrive so ffmpeg has input
          recorder.stop
        end
      end
    end
  end
end
