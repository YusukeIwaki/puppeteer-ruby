require 'spec_helper'

RSpec.describe Puppeteer::FrameManager do
  class TestSession
    include Puppeteer::EventCallbackable

    def async_send_message(*)
      Async::Promise.new.tap { |promise| promise.resolve({}) }
    end

    def send_message(*)
      {}
    end
  end

  let(:client) { TestSession.new }
  let(:page) { double(Puppeteer::Page).as_null_object }
  let(:timeout_settings) { Puppeteer::TimeoutSettings.new }
  let(:instance) { described_class.new(client, page, false, timeout_settings) }

  describe 'lifecycle events' do
    it 'queues lifecycle events until the frame tree is handled' do
      event = {
        'frameId' => 'frame-1',
        'loaderId' => 'loader-1',
        'name' => 'networkAlmostIdle',
      }
      frame_tree = {
        'frame' => {
          'id' => 'frame-1',
          'parentId' => nil,
          'url' => 'http://example.test',
          'urlFragment' => '',
        },
      }

      instance.send(:prepare_frame_tree_handling)
      instance.handle_lifecycle_event(event)

      instance.handle_frame_tree(client, frame_tree)
      instance.send(:finish_frame_tree_handling)

      expect(instance.main_frame.lifecycle_events).to include('networkAlmostIdle')
    end
  end
end
