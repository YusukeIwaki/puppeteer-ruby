require 'json'
require 'tempfile'
require 'spec_helper'

RSpec.describe 'Page#capture_heap_snapshot' do
  it 'should capture heap snapshot to a file' do
    with_test_state do |page:, **|
      page.goto('about:blank')
      page.evaluate(<<~JAVASCRIPT)
        () => {
          globalThis.__heap_snapshot_test_data = new Array(1000).fill('x'.repeat(100));
        }
      JAVASCRIPT

      Tempfile.create(['heap-snapshot', '.heapsnapshot']) do |snapshot|
        page.capture_heap_snapshot(path: snapshot.path)

        expect(File.size(snapshot.path)).to be > 0
        parsed = JSON.parse(File.read(snapshot.path))
        expect(parsed).to be_a(Hash)
      end
    end
  end
end
