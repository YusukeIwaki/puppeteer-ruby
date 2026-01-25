require 'spec_helper'

class FakeCdpSession
  def initialize
    @handlers = {}
    @get_frame_tree_called = Async::Promise.new
    @frame_tree_promise = Async::Promise.new
    @session_id = 'session-1'
  end

  attr_reader :get_frame_tree_called, :frame_tree_promise

  def id
    @session_id
  end

  def on_event(event_name, &block)
    @handlers[event_name] = block
  end

  def emit(event_name, payload)
    @handlers[event_name]&.call(payload)
  end

  def async_send_message(method, _params = {})
    case method
    when 'Page.getFrameTree'
      @get_frame_tree_called.resolve(true) unless @get_frame_tree_called.resolved?
      @frame_tree_promise
    else
      Async::Promise.new.tap { |promise| promise.resolve({}) }
    end
  end

  def send_message(_method, _params = {})
    {}
  end
end

RSpec.describe Puppeteer::FrameManager do
  it 'replays lifecycle events received before the frame tree is ready' do
    client = FakeCdpSession.new
    page = double(Puppeteer::Page).as_null_object
    timeout_settings = Puppeteer::TimeoutSettings.new
    manager = described_class.new(client, page, false, timeout_settings, network_enabled: false)

    frame_id = 'frame-1'
    loader_id = 'loader-1'
    frame_tree = {
      'frame' => {
        'id' => frame_id,
        'url' => 'https://example.test',
      },
    }

    Async do
      init_task = manager.async_init('target-id')
      client.get_frame_tree_called.wait

      client.emit('Page.lifecycleEvent', {
        'frameId' => frame_id,
        'loaderId' => loader_id,
        'name' => 'init',
      })

      client.frame_tree_promise.resolve({ 'frameTree' => frame_tree })
      init_task.wait
    end.wait

    frame = manager.main_frame
    expect(frame.loader_id).to eq(loader_id)
    expect(frame.lifecycle_events).to include('init')
  end
end
