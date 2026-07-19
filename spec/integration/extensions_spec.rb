require 'spec_helper'

RSpec.describe 'extensions' do
  let(:simple_extension_path) { File.expand_path('../assets/simple-extension', __dir__) }
  let(:extension_with_page_path) { File.expand_path('../assets/extension-with-page', __dir__) }

  def with_extension_browser(&block)
    with_browser(enable_extensions: true) do |browser|
      skip_unless_extensions_supported(browser)
      expect(browser.ws_endpoint).to start_with('ws://')
      block.call(browser, $shared_test_server)
    end
  end

  def skip_unless_extensions_supported(browser)
    browser.extensions
  rescue Puppeteer::Connection::ProtocolError => err
    if err.message.include?('Method not available') || err.message.include?("wasn't found")
      skip('Extensions CDP domain is not available in this Chromium build')
    end
    raise
  end

  def assert_no_service_worker_reported(browser, extension_id)
    target = browser.targets.find do |candidate|
      candidate.url.include?(extension_id) && candidate.type == 'service_worker'
    end
    expect(target).to be_nil
  end

  it 'service_worker target type should be available' do
    with_extension_browser do |browser|
      extension_id = browser.install_extension(simple_extension_path)
      target = browser.wait_for_target(
        predicate: ->(candidate) { candidate.type == 'service_worker' },
      )
      expect(target).to be_truthy

      browser.uninstall_extension(extension_id)
      assert_no_service_worker_reported(browser, extension_id)
    end
  end

  it 'can evaluate in the service worker' do
    with_extension_browser do |browser|
      extension_id = browser.install_extension(simple_extension_path)
      target = browser.wait_for_target(
        predicate: ->(candidate) { candidate.type == 'service_worker' },
      )
      worker = target.worker
      expect(worker.evaluate('() => globalThis.MAGIC')).to eq(42)

      browser.uninstall_extension(extension_id)
      assert_no_service_worker_reported(browser, extension_id)
    end
  end

  it 'should list extensions and their properties' do
    with_extension_browser do |browser|
      extension_id = browser.install_extension(simple_extension_path)
      target = browser.wait_for_target(
        predicate: lambda { |candidate|
          candidate.url.include?(extension_id) && candidate.type == 'service_worker'
        },
      )
      expect(target).to be_truthy

      extension = browser.extensions[extension_id]
      expect(extension).to be_truthy
      expect(extension.name).to eq('Simple extension')
      expect(extension.version).to eq('0.1')
      expect(extension.path).to eq(simple_extension_path)
      expect(extension.enabled).to eq(true)
      expect(extension.id).to eq(extension_id)

      browser.uninstall_extension(extension_id)
      assert_no_service_worker_reported(browser, extension_id)
    end
  end

  it 'should list extension workers' do
    with_extension_browser do |browser|
      extension_id = browser.install_extension(simple_extension_path)
      extension = browser.extensions[extension_id]
      page = browser.new_page
      begin
        extension.trigger_action(page)
        browser.wait_for_target(
          predicate: lambda { |candidate|
            candidate.url.include?(extension_id) && candidate.type == 'service_worker'
          },
        )
        expect(extension.workers.length).to be > 0
      ensure
        page.close unless page.closed?
        browser.uninstall_extension(extension_id)
      end
      assert_no_service_worker_reported(browser, extension_id)
    end
  end

  it 'should trigger extension action' do
    with_extension_browser do |browser|
      page = browser.new_page
      extension_id = browser.install_extension(simple_extension_path)
      begin
        extension = browser.extensions[extension_id]
        page.trigger_extension_action(extension)
        target = browser.wait_for_target(
          predicate: lambda { |candidate|
            candidate.url.include?(extension_id) && candidate.type == 'service_worker'
          },
        )
        expect(target).to be_truthy
      ensure
        page.close unless page.closed?
        browser.uninstall_extension(extension_id)
      end
      assert_no_service_worker_reported(browser, extension_id)
    end
  end

  it 'should list extension pages', sinatra: true do
    with_extension_browser do |browser, server|
      extension_id = browser.install_extension(extension_with_page_path)
      extension = browser.extensions[extension_id]
      page = browser.new_page
      begin
        page.goto(server.empty_page)
        extension.trigger_action(page)
        browser.wait_for_target(
          predicate: lambda { |candidate|
            candidate.url.include?(extension_id) && candidate.type == 'service_worker'
          },
        )
        browser.wait_for_target(
          predicate: lambda { |candidate|
            candidate.url.include?('popup.html') && candidate.url.include?(extension_id)
          },
        )

        pages = extension.pages
        expect(pages.length).to be >= 1
        expect(pages.any? { |extension_page| extension_page.url.include?('popup.html') }).to eq(true)
      ensure
        page.close unless page.closed?
        browser.uninstall_extension(extension_id)
      end
      assert_no_service_worker_reported(browser, extension_id)
    end
  end

  it 'should capture console logs from extension pages', sinatra: true do
    with_extension_browser do |browser, server|
      extension_id = browser.install_extension(extension_with_page_path)
      extension = browser.extensions[extension_id]
      page = browser.new_page
      begin
        page.goto(server.empty_page)
        page.trigger_extension_action(extension)
        browser.wait_for_target(
          predicate: lambda { |candidate|
            candidate.url.include?(extension_id) && candidate.type == 'service_worker'
          },
        )
        popup_target = browser.wait_for_target(
          predicate: lambda { |candidate|
            candidate.url.include?('popup.html') && candidate.url.include?(extension_id)
          },
        )
        extension_page = popup_target.as_page
        message = Async::Promise.new
        extension_page.on('console') { |console_message| message.resolve(console_message.text) }
        extension_page.evaluate('() => console.log("hello from extension page")')
        expect(message.wait).to eq('hello from extension page')
      ensure
        page.close unless page.closed?
        browser.uninstall_extension(extension_id)
      end
      assert_no_service_worker_reported(browser, extension_id)
    end
  end

  it 'should capture console logs from extension workers', sinatra: true do
    with_extension_browser do |browser, server|
      extension_id = browser.install_extension(extension_with_page_path)
      extension = browser.extensions[extension_id]
      page = browser.new_page
      begin
        page.goto(server.empty_page)
        extension.trigger_action(page)
        worker_target = browser.wait_for_target(
          predicate: lambda { |candidate|
            candidate.url.include?(extension_id) && candidate.type == 'service_worker'
          },
        )
        worker = worker_target.worker
        message_to_log = 'hello from extension worker'
        message = Async::Promise.new
        worker.on('console') do |console_message|
          message.resolve(console_message.text) if console_message.text == message_to_log
        end
        worker.evaluate('(text) => console.log(text)', message_to_log)
        expect(message.wait).to eq(message_to_log)
      ensure
        page.close unless page.closed?
        browser.uninstall_extension(extension_id)
      end
      assert_no_service_worker_reported(browser, extension_id)
    end
  end

  it 'should remove extension from list after uninstall' do
    with_extension_browser do |browser|
      extension_id = browser.install_extension(simple_extension_path)
      target = browser.wait_for_target(
        predicate: lambda { |candidate|
          candidate.url.include?(extension_id) && candidate.type == 'service_worker'
        },
      )
      expect(target).to be_truthy
      expect(browser.extensions.key?(extension_id)).to eq(true)

      browser.uninstall_extension(extension_id)
      assert_no_service_worker_reported(browser, extension_id)
      expect(browser.extensions.key?(extension_id)).to eq(false)
    end
  end

  it 'should be available in Incognito profiles if enabledInIncognito is true', sinatra: true do
    with_extension_browser do |browser, server|
      extension_id = browser.install_extension(
        simple_extension_path,
        enabled_in_incognito: true,
      )
      context = browser.create_browser_context
      page = context.new_page
      begin
        page.goto(server.empty_page)
        target = browser.wait_for_target(
          predicate: lambda { |candidate|
            candidate.url.include?(extension_id) && candidate.type == 'service_worker'
          },
        )
        expect(target).to be_truthy

        content_script_realm = page.extension_realms.find do |realm|
          realm.extension&.id == extension_id
        end
        expect(content_script_realm).to be_truthy
        expect(content_script_realm.evaluate('() => globalThis.thisIsTheContentScript')).to eq(true)
      ensure
        browser.uninstall_extension(extension_id)
        context.close unless context.closed?
      end
      assert_no_service_worker_reported(browser, extension_id)
    end
  end

  it 'should expose extension realms on page', sinatra: true do
    with_extension_browser do |browser, server|
      extension_id = browser.install_extension(simple_extension_path)
      page = browser.new_page
      begin
        page.goto(server.empty_page)
        realm = page.extension_realms.find { |candidate| candidate.origin&.include?(extension_id) }
        expect(realm).to be_truthy
        expect(realm.origin).to include("chrome-extension://#{extension_id}")
        expect(realm.extension&.id).to eq(extension_id)
        expect(realm.evaluate('() => globalThis.thisIsTheContentScript')).to eq(true)
      ensure
        page.close unless page.closed?
        browser.uninstall_extension(extension_id)
      end
      assert_no_service_worker_reported(browser, extension_id)
    end
  end
end
