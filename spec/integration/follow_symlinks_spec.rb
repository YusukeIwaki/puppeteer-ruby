require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe 'followSymlinks' do
  def with_symlink_fixtures(follow_symlinks:)
    skip('Symlinks require privileges on Windows') if Puppeteer.env.windows?

    Dir.mktmpdir('pptr-symlink-') do |tmp_dir|
      script_file = File.join(tmp_dir, 'script.js')
      script_symlink = File.join(tmp_dir, 'script-link.js')
      File.write(script_file, 'window.__injected = 123;')
      begin
        File.symlink(script_file, script_symlink)
      rescue SystemCallError, NotImplementedError
        skip('Symlinks are not supported in this environment')
      end

      style_file = File.join(tmp_dir, 'style.css')
      style_symlink = File.join(tmp_dir, 'style-link.css')
      File.write(style_file, 'body { background-color: rgb(0, 255, 0); }')
      File.symlink(style_file, style_symlink)

      Puppeteer.set_follow_symlinks(follow_symlinks)
      begin
        yield(
          tmp_dir: tmp_dir,
          script_file: script_file,
          script_symlink: script_symlink,
          style_file: style_file,
          style_symlink: style_symlink)
      ensure
        Puppeteer.set_follow_symlinks(true)
      end
    end
  end

  describe 'when follow_symlinks is false' do
    it 'should reject addScriptTag with a symlinked path', sinatra: true do
      with_symlink_fixtures(follow_symlinks: false) do |script_symlink:, **|
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)

          expect {
            page.add_script_tag(path: script_symlink)
          }.to raise_error(Errno::ELOOP)
        end
      end
    end

    it 'should allow addScriptTag with a regular file path', sinatra: true do
      with_symlink_fixtures(follow_symlinks: false) do |script_file:, **|
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)

          page.add_script_tag(path: script_file)
          expect(page.evaluate('() => globalThis.__injected')).to eq(123)
        end
      end
    end

    it 'should reject addStyleTag with a symlinked path', sinatra: true do
      with_symlink_fixtures(follow_symlinks: false) do |style_symlink:, **|
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)

          expect {
            page.add_style_tag(path: style_symlink)
          }.to raise_error(Errno::ELOOP)
        end
      end
    end

    it 'should allow addStyleTag with a regular file path', sinatra: true do
      with_symlink_fixtures(follow_symlinks: false) do |style_file:, **|
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)

          page.add_style_tag(path: style_file)
          result = page.evaluate('() => window.getComputedStyle(document.body).getPropertyValue("background-color")')
          expect(result).to eq('rgb(0, 255, 0)')
        end
      end
    end

    it 'should reject screenshot to an existing symlink path', sinatra: true do
      with_symlink_fixtures(follow_symlinks: false) do |tmp_dir:, **|
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)

          target_file = File.join(tmp_dir, 'screenshot.png')
          link_file = File.join(tmp_dir, 'screenshot-link.png')
          File.write(target_file, 'placeholder')
          File.symlink(target_file, link_file)

          expect {
            page.screenshot(path: link_file)
          }.to raise_error(Errno::ELOOP)
        end
      end
    end

    it 'should reject pdf to an existing symlink path', sinatra: true do
      with_symlink_fixtures(follow_symlinks: false) do |tmp_dir:, **|
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)

          target_file = File.join(tmp_dir, 'output.pdf')
          link_file = File.join(tmp_dir, 'output-link.pdf')
          File.write(target_file, 'placeholder')
          File.symlink(target_file, link_file)

          expect {
            page.pdf(path: link_file)
          }.to raise_error(Errno::ELOOP)
        end
      end
    end

    it 'should reject screencast to an existing symlink path', sinatra: true do
      with_symlink_fixtures(follow_symlinks: false) do |tmp_dir:, **|
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)

          target_file = File.join(tmp_dir, 'recording.webm')
          link_file = File.join(tmp_dir, 'recording-link.webm')
          File.write(target_file, 'placeholder')
          File.symlink(target_file, link_file)

          expect {
            page.screencast(path: link_file)
          }.to raise_error(Errno::ELOOP)
        end
      end
    end
  end

  describe 'when follow_symlinks is true (default)' do
    it 'should allow addScriptTag with a symlinked path', sinatra: true do
      with_symlink_fixtures(follow_symlinks: true) do |script_symlink:, **|
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)

          page.add_script_tag(path: script_symlink)
          expect(page.evaluate('() => globalThis.__injected')).to eq(123)
        end
      end
    end

    it 'should allow addStyleTag with a symlinked path', sinatra: true do
      with_symlink_fixtures(follow_symlinks: true) do |style_symlink:, **|
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)

          page.add_style_tag(path: style_symlink)
          result = page.evaluate('() => window.getComputedStyle(document.body).getPropertyValue("background-color")')
          expect(result).to eq('rgb(0, 255, 0)')
        end
      end
    end

    it 'should allow screenshot to a symlink path', sinatra: true do
      with_symlink_fixtures(follow_symlinks: true) do |tmp_dir:, **|
        with_test_state do |page:, server:, **|
          page.goto(server.empty_page)

          target_file = File.join(tmp_dir, 'screenshot-target.png')
          link_file = File.join(tmp_dir, 'screenshot-default-link.png')
          File.write(target_file, 'placeholder')
          File.symlink(target_file, link_file)

          page.screenshot(path: link_file)
          expect(File.size(target_file)).to be > 0
        end
      end
    end
  end
end
