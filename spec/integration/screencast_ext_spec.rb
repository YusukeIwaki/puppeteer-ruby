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

    it 'streams output to the file while recording' do
      Dir.mktmpdir('puppeteer-screencast-') do |directory|
        with_test_state do |page:, **|
          path = File.join(directory, 'streaming.webm')
          recorder = page.screencast(path: path)
          page.goto('data:text/html,<div id="t">0</div><script>setInterval(() => { document.getElementById("t").textContent = Date.now(); }, 16);</script>')
          # Upstream pipes FFmpeg stdout to the file continuously, so output
          # must be observable before stopping.
          Timeout.timeout(30) do
            sleep 0.2 until File.size(path) > 0
          end
          size_before_stop = File.size(path)
          recorder.stop
          expect(size_before_stop).to be > 0
          expect(File.size(path)).to be >= size_before_stop
        end
      end
    end
  end
end
