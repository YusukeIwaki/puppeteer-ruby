require 'spec_helper'

RSpec.describe 'Frame (white-box / Ruby-specific)' do
  include Utils::AttachFrame

  describe '#execution_context' do
    it 'should work', sinatra: true do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        attach_frame(page, 'frame1', server.empty_page)
        expect(page.frames.size).to eq(2)

        frames = page.frames
        contexts = frames.map(&:execution_context)
        expect(contexts).to all(be_truthy)
        expect(contexts.first).not_to eq(contexts.last)

        contexts.each_with_index do |context, i|
          context.evaluate("() => (globalThis.a = #{i + 1})")
        end
        values = contexts.map { |context| context.evaluate('() => globalThis.a') }
        expect(values).to eq([1, 2])
      end
    end
  end

  describe 'Frame Management' do
    it 'should report frame.name()', sinatra: true do
      with_test_state do |page:, server:, **|
        page.goto(server.empty_page)
        attach_frame(page, 'theFrameId', server.empty_page)
        js = <<~JAVASCRIPT
        (url) => {
          const frame = document.createElement('iframe');
          frame.name = 'theFrameName';
          frame.src = url;
          document.body.appendChild(frame);
          return new Promise((x) => (frame.onload = x));
        }
        JAVASCRIPT
        page.evaluate(js, server.empty_page)
        expect(page.frames.map(&:name)).to eq(['', 'theFrameId', 'theFrameName'])
      end
    end
  end
end
