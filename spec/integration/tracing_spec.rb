require 'spec_helper'
require 'tmpdir'

RSpec.describe 'Tracing', skip: Puppeteer.env.firefox? do
  let(:output_file) { "trace-#{SecureRandom.hex(8)}.json" }
  after do
    File.delete(output_file) if File.exist?(output_file)
  end

  it 'should output a trace', sinatra: true do
    page.tracing.start(screenshots: true, path: output_file)
    page.goto("#{server_prefix}/grid.html")
    page.tracing.stop
    expect(File.exist?(output_file)).to eq(true)
  end

  it 'should run with custom categories if provided' do
    page.tracing.start(
      path: output_file,
      categories: ['disabled-by-default-v8.cpu_profiler.hires'],
    )
    page.tracing.stop

    trace_json = JSON.parse(File.read(output_file))
    expect(trace_json.dig('metadata', 'trace-config')).to include('disabled-by-default-v8.cpu_profiler.hires')
  end

  it 'should throw if tracing on two pages' do
    page.tracing.start(path: output_file)
    new_page = page.browser.new_page
    expect { new_page.tracing.start(path: output_file) }.to raise_error(/Tracing has already been started/)
  end

  it 'should return a buffer', sinatra: true do
    page.tracing.start(screenshots: true, path: output_file)
    page.goto("#{server_prefix}/grid.html")
    trace = page.tracing.stop
    expect(trace).to eq(File.read(output_file))
  end

  it 'should work without options', sinatra: true do
    page.tracing.start
    page.goto("#{server_prefix}/grid.html")
    trace = page.tracing.stop
    expect(trace.length).to be > 1000
  end

  it 'should support a buffer without a path', sinatra: true do
    page.tracing.start(screenshots: true)
    page.goto("#{server_prefix}/grid.html")
    trace = page.tracing.stop
    expect(trace).to include('screenshot')
  end

  it 'should properly fail if readProtocolStream errors out' do
    page.tracing.start(path: File.expand_path(__dir__))
    expect { page.tracing.stop }.to raise_error(/Is a directory/)
  end
end
