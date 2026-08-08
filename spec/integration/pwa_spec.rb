require 'spec_helper'

RSpec.describe 'PWA' do
  def with_pwa_test_state(&block)
    # The `PWA` CDP domain is only available over a pipe connection.
    with_browser(pipe: true) do |browser|
      with_test_state(browser: browser, create_page: false, incognito: false, &block)
    end
  end

  def install_test_pwa(browser, server, display_mode = nil)
    manifest_id = "#{server.prefix}/pwa/"
    start_url = "#{server.prefix}/pwa/index.html"
    returned_id = browser.install_pwa(
      manifest_id: manifest_id,
      install_url_or_bundle_url: start_url,
      display_mode: display_mode,
    )
    expect(returned_id).to eq(manifest_id)
    { manifest_id: manifest_id, start_url: start_url }
  end

  it 'installs and uninstalls a PWA' do
    with_pwa_test_state do |browser:, server:, **|
      manifest_id = install_test_pwa(browser, server)[:manifest_id]

      # getPWAState resolves for an installed app.
      installed_state = browser.get_pwa_state(manifest_id: manifest_id)
      expect(installed_state['badgeCount']).to eq(0)
      expect(installed_state['fileHandlers']).to be_a(Array)

      browser.uninstall_pwa(manifest_id: manifest_id)

      # After uninstall, querying the app state should reject.
      expect do
        browser.get_pwa_state(manifest_id: manifest_id)
      end.to raise_error(Puppeteer::Connection::ProtocolError)
    end
  end

  it 'launches an installed PWA and returns its Page' do
    with_pwa_test_state do |browser:, server:, **|
      test_pwa = install_test_pwa(browser, server, 'standalone')
      manifest_id = test_pwa[:manifest_id]
      start_url = test_pwa[:start_url]

      page = browser.launch_pwa(manifest_id: manifest_id)
      begin
        expect(page.url).to eq(start_url)
        is_standalone = page.evaluate(<<~JAVASCRIPT)
          () => {
            return matchMedia('(display-mode: standalone)').matches;
          }
        JAVASCRIPT
        expect(is_standalone).to eq(true)
      ensure
        page.close rescue nil
        browser.uninstall_pwa(manifest_id: manifest_id) rescue nil
      end
    end
  end

  it 'launches an installed PWA at an explicit url' do
    with_pwa_test_state do |browser:, server:, **|
      test_pwa = install_test_pwa(browser, server, 'standalone')
      manifest_id = test_pwa[:manifest_id]
      start_url = test_pwa[:start_url]

      page = browser.launch_pwa(manifest_id: manifest_id, url: start_url)
      begin
        expect(page.url).to eq(start_url)
      ensure
        page.close rescue nil
        browser.uninstall_pwa(manifest_id: manifest_id) rescue nil
      end
    end
  end

  it 'installs a PWA with a standalone display mode' do
    with_pwa_test_state do |browser:, server:, **|
      manifest_id = "#{server.prefix}/pwa/"
      start_url = "#{server.prefix}/pwa/index.html"

      browser.install_pwa(
        manifest_id: manifest_id,
        install_url_or_bundle_url: start_url,
        display_mode: 'standalone',
      )

      page = browser.launch_pwa(manifest_id: manifest_id)
      begin
        is_standalone = page.evaluate(<<~JAVASCRIPT)
          () => {
            return matchMedia('(display-mode: standalone)').matches;
          }
        JAVASCRIPT
        expect(is_standalone).to eq(true)
      ensure
        page.close rescue nil
        browser.uninstall_pwa(manifest_id: manifest_id) rescue nil
      end
    end
  end
end
