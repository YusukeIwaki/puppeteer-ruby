require 'json'
require 'tempfile'
require 'spec_helper'

RSpec.describe 'Page#capture_heap_snapshot' do
  it 'should capture heap snapshot' do
    with_test_state do |page:, **|
      Tempfile.create(['heap-snapshot', '.heapsnapshot']) do |snapshot|
        page.capture_heap_snapshot(path: snapshot.path)

        expect(File.exist?(snapshot.path)).to eq(true)
        parsed = JSON.parse(File.read(snapshot.path))
        expect(parsed['snapshot']).not_to be_nil
        expect(parsed['nodes']).not_to be_nil
        expect(parsed['edges']).not_to be_nil
      end
    end
  end
end
