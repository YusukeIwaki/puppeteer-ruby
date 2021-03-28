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
end
