require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe 'Download', sinatra: true do
  def wait_for_file_existence(file_path, timeout: 1.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until File.exist?(file_path)
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "Exceeded timeout of #{(timeout * 1000).to_i} ms for watching #{file_path}"
      end
      sleep 0.05
    end
  end

  before do
    @temp_dir = Dir.mktmpdir('downloads-')
  end

  after do
    FileUtils.rm_rf(@temp_dir) if @temp_dir
  end

  describe 'Browser.createBrowserContext' do
    it 'should download to configured location' do
      with_test_state(create_page: false, incognito: false) do |browser:, server:, **|
        context = browser.create_browser_context(
          download_behavior: {
            policy: 'allow',
            download_path: @temp_dir,
          },
        )
        page = context.new_page
        page.goto("#{server.prefix}/download.html")
        page.click('#download')
        wait_for_file_existence(File.join(@temp_dir, 'download.txt'))
      ensure
        page&.close unless page&.closed?
        context&.close unless context&.closed?
      end
    end

    it 'should not download to location' do
      with_test_state(create_page: false, incognito: false) do |browser:, server:, **|
        context = browser.create_browser_context(
          download_behavior: {
            policy: 'deny',
            download_path: '/tmp',
          },
        )
        page = context.new_page
        page.goto("#{server.prefix}/download.html")
        page.click('#download')
        expect {
          wait_for_file_existence(File.join(@temp_dir, 'download.txt'))
        }.to raise_error(/Exceeded timeout/)
      ensure
        page&.close unless page&.closed?
        context&.close unless context&.closed?
      end
    end
  end
end
