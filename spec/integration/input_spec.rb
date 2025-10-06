require 'spec_helper'

RSpec.describe 'input tests' do
  describe 'input' do
    it_fails_firefox 'should upload the file', sinatra: true do
      page.goto("#{server_prefix}/input/fileupload.html")
      filepath = File.join('spec', 'assets', 'file-to-upload.txt')
      input = page.query_selector('input')
      js = <<~JAVASCRIPT
      (e) => {
        globalThis._inputEvents = [];
        e.addEventListener('change', (ev) =>
          globalThis._inputEvents.push(ev.type)
        );
        e.addEventListener('input', (ev) =>
          globalThis._inputEvents.push(ev.type)
        );
      }
      JAVASCRIPT
      page.evaluate(js, input)
      input.upload_file(filepath)
      expect(page.evaluate('(e) => e.files[0].name', input)).to eq('file-to-upload.txt')
      expect(page.evaluate('(e) => e.files[0].type', input)).to eq('text/plain')
      expect(page.evaluate('() => globalThis._inputEvents')).to eq(%w(input change))
      js = <<~JAVASCRIPT
      (e) => {
        const reader = new FileReader();
        const promise = new Promise((fulfill) => (reader.onload = fulfill));
        reader.readAsText(e.files[0]);
        return promise.then(() => reader.result);
      }
      JAVASCRIPT
      expect(page.evaluate(js, input)).to eq('contents of the file')
    end
  end

  describe 'Page#wait_for_file_chooser' do
    it_fails_firefox 'should work when file input is attached to DOM' do
      page.content = '<input type=file>'
      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      expect(chooser).to be_a(Puppeteer::FileChooser)
    end
    it_fails_firefox 'should work when file input is not attached to DOM' do
      js = <<~JAVASCRIPT
      () => {
        const el = document.createElement('input');
        el.type = 'file';
        el.click();
      }
      JAVASCRIPT

      chooser = page.wait_for_file_chooser do
        page.evaluate(js)
      end
      expect(chooser).to be_a(Puppeteer::FileChooser)
    end
    it 'should respect timeout' do
      expect { page.wait_for_file_chooser(timeout: 1) }.to raise_error(/waiting for filechooser failed: timeout 1ms exceeded/)
    end
    it 'should respect default timeout when there is no custom timeout' do
      page.default_timeout = 1
      expect { page.wait_for_file_chooser }.to raise_error(/waiting for filechooser failed: timeout 1ms exceeded/)
    end
    it 'should prioritize exact timeout over default timeout' do
      page.default_timeout = 5000
      expect { page.wait_for_file_chooser(timeout: 1) }.to raise_error(/waiting for filechooser failed: timeout 1ms exceeded/)
    end
    it_fails_firefox 'should work with no timeout' do
      js = <<~JAVASCRIPT
      () => {
        setTimeout(() => {
          const el = document.createElement('input');
          el.type = 'file';
          el.click();
        }, 50)
      }
      JAVASCRIPT

      chooser = page.wait_for_file_chooser do
        page.evaluate(js)
      end
      expect(chooser).to be_a(Puppeteer::FileChooser)
    end
    it_fails_firefox 'should return the same file chooser when there are many watchdogs simultaneously' do
      page.content = '<input type=file>'
      choosers = Concurrent::Promises
        .zip(
          page.async_wait_for_file_chooser,
          page.async_wait_for_file_chooser,
          page.async_eval_on_selector('input', '(input) => input.click()'),
        ).value!
        .first(2)
      expect(choosers.first).to eq(choosers.last)
    end
  end

  describe 'FileChooser#accept' do
    let(:filepath) { File.join('spec', 'assets', 'file-to-upload.txt') }

    it_fails_firefox 'should accept single file' do
      page.content = "<input type=file oninput='javascript:console.timeStamp()'>"
      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      chooser.accept(filepath)
      expect(page.eval_on_selector('input', "(input) => input.files.length")).to eq(1)
      expect(page.eval_on_selector('input', "(input) => input.files[0].name")).to eq("file-to-upload.txt")
    end
    it_fails_firefox 'should be able to read selected file' do
      page.content = '<input type=file>'
      Concurrent::Promises.future(
        &Puppeteer::ConcurrentRubyUtils.future_with_logging do
        chooser = page.wait_for_file_chooser
        chooser.accept(filepath)
        end
      )
      js = <<~JAVASCRIPT
      async (picker) => {
        picker.click();
        await new Promise((x) => (picker.oninput = x));
        const reader = new FileReader();
        const promise = new Promise((fulfill) => (reader.onload = fulfill));
        reader.readAsText(picker.files[0]);
        return promise.then(() => reader.result);
      }
      JAVASCRIPT
      expect(page.eval_on_selector('input', js)).to eq('contents of the file')
    end
    it_fails_firefox 'should be able to reset selected files with empty file list' do
      page.content = '<input type=file>'

      Concurrent::Promises.future(
        &Puppeteer::ConcurrentRubyUtils.future_with_logging do
        chooser = page.wait_for_file_chooser
        chooser.accept(filepath)
        end
      )
      js = <<~JAVASCRIPT
      async (picker) => {
        picker.click();
        await new Promise((x) => (picker.oninput = x));
        return picker.files.length;
      }
      JAVASCRIPT
      expect(page.eval_on_selector('input', js)).to eq(1)

      Concurrent::Promises.future(
        &Puppeteer::ConcurrentRubyUtils.future_with_logging do
        chooser = page.wait_for_file_chooser
        chooser.accept([])
        end
      )
      js = <<~JAVASCRIPT
      async (picker) => {
        picker.click();
        await new Promise((x) => (picker.oninput = x));
        return picker.files.length;
      }
      JAVASCRIPT
      expect(page.eval_on_selector('input', js)).to eq(0)
    end
    it_fails_firefox 'should not accept multiple files for single-file input' do
      page.content = '<input type=file>'
      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      pprt_png = File.join('spec', 'assets', 'pptr.png')
      expect { chooser.accept([filepath, pprt_png]) }.to raise_error(/Multiple file uploads only work with <input type=file multiple>/)
    end
    it_fails_firefox 'should succeed even for non-existent files' do
      page.content = '<input type=file>'
      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      chooser.accept(['file-does-not-exist.txt'])
    end
    it_fails_firefox 'should error on read of non-existent files' do
      page.content = '<input type=file>'
      Concurrent::Promises.future(
        &Puppeteer::ConcurrentRubyUtils.future_with_logging do
        chooser = page.wait_for_file_chooser
        chooser.accept(['file-does-not-exist.txt'])
        end
      )
      js = <<~JAVASCRIPT
      async (picker) => {
        picker.click();
        await new Promise((x) => (picker.oninput = x));
        const reader = new FileReader();
        const promise = new Promise((fulfill) => (reader.onerror = fulfill));
        reader.readAsText(picker.files[0]);
        return promise.then(() => false);
      }
      JAVASCRIPT
      expect(page.eval_on_selector('input', js)).to eq(false)
    end
    it_fails_firefox 'should fail when accepting file chooser twice' do
      page.content = '<input type=file>'
      chooser = page.wait_for_file_chooser do
        page.eval_on_selector('input', '(input) => input.click()')
      end
      chooser.accept([])
      expect { chooser.accept([]) }.to raise_error(/Cannot accept FileChooser which is already handled!/)
    end
  end

  describe 'FileChooser#cancel' do
    it_fails_firefox 'should cancel dialog' do
      # Consider file chooser canceled if we can summon another one.
      # There's no reliable way in WebPlatform to see that FileChooser was
      # canceled.

      page.content = '<input type=file>'
      chooser = page.wait_for_file_chooser do
        page.eval_on_selector('input', '(input) => input.click()')
      end
      chooser.cancel

      # If this resolves, than we successfully canceled file chooser.
      Timeout.timeout(2) do
        chooser = page.wait_for_file_chooser do
          page.eval_on_selector('input', '(input) => input.click()')
        end
      end
    end

    it_fails_firefox 'should fail when canceling file chooser twice' do
      page.content = '<input type=file>'
      chooser = page.wait_for_file_chooser do
        page.eval_on_selector('input', '(input) => input.click()')
      end
      chooser.cancel
      expect { chooser.cancel }.to raise_error(/Cannot cancel FileChooser which is already handled!/)
    end
  end

  describe 'FileChooser#multiple?' do
    it_fails_firefox 'should work for single file pick' do
      page.content = '<input type=file>'
      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      expect(chooser).not_to be_multiple
    end
    it_fails_firefox 'should work for "multiple"' do
      page.content = '<input multiple type=file>'
      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      expect(chooser).to be_multiple
    end
    it_fails_firefox 'should work for "webkitdirectory"' do
      page.content = '<input multiple webkitdirectory type=file>'
      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      expect(chooser).to be_multiple
    end
  end
end
