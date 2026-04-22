require 'spec_helper'

RSpec.describe 'Extensions' do
  let(:simple_extension_path) { File.expand_path('../assets/simple-extension', __dir__) }
  let(:extension_with_page_path) { File.expand_path('../assets/extension-with-page', __dir__) }

  def skip_unless_extensions_supported(browser)
    browser.extensions
  rescue Puppeteer::Connection::ProtocolError => err
    if err.message.include?('Method not available')
      skip('Extensions CDP domain is not available in this Chromium build')
    end
    raise
  end

  it 'should list extensions and their properties', sinatra: true do
    with_browser(enable_extensions: true) do |browser|
      skip_unless_extensions_supported(browser)
      extension_id = browser.install_extension(simple_extension_path)

      begin
        target = browser.wait_for_target(
          predicate: ->(candidate) { candidate.url.include?(extension_id) && candidate.type == 'service_worker' },
          timeout: 5000,
        )
        expect(target).not_to be_nil

        extensions = browser.extensions
        extension = extensions[extension_id]
        expect(extension).not_to be_nil
        expect(extension.name).to eq('Simple extension')
        expect(extension.version).to eq('0.1')
        expect(extension.path).to eq(simple_extension_path)
        expect(extension.enabled).to eq(true)
      ensure
        browser.uninstall_extension(extension_id)
      end
    end
  end

  it 'should trigger extension action', sinatra: true do
    with_browser(enable_extensions: true) do |browser|
      skip_unless_extensions_supported(browser)
      with_test_state(browser: browser) do |page:, server:, **|
        extension_id = browser.install_extension(extension_with_page_path)
        begin
          extension = browser.extensions[extension_id]
          expect(extension).not_to be_nil

          page.goto(server.empty_page)
          page.trigger_extension_action(extension)

          worker_target = browser.wait_for_target(
            predicate: ->(candidate) { candidate.url.include?(extension_id) && candidate.type == 'service_worker' },
            timeout: 5000,
          )
          expect(worker_target).not_to be_nil
        ensure
          browser.uninstall_extension(extension_id)
        end
      end
    end
  end

  it 'should expose extension realms on page', sinatra: true do
    with_browser(enable_extensions: true) do |browser|
      skip_unless_extensions_supported(browser)
      with_test_state(browser: browser) do |page:, server:, **|
        extension_id = browser.install_extension(simple_extension_path)
        begin
          page.goto(server.empty_page)

          realm = nil
          20.times do
            realm = page.extension_realms.find { |candidate| candidate.origin&.include?(extension_id) }
            break if realm
            Puppeteer::AsyncUtils.sleep_seconds(0.1)
          end

          expect(realm).not_to be_nil
          expect(realm.origin).to include("chrome-extension://#{extension_id}")
          expect(realm.extension&.id).to eq(extension_id)
          expect(realm.evaluate('() => globalThis.thisIsTheContentScript')).to eq(true)
        ensure
          browser.uninstall_extension(extension_id)
        end
      end
    end
  end
end
