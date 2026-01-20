module Utils ; end

module Utils::AttachFrame
  def attach_frame(page, frame_id, url)
    js = <<~JAVASCRIPT
    async function attachFrame(frameId, url) {
      const frame = document.createElement('iframe');
      frame.src = url;
      frame.id = frameId;
      document.body.appendChild(frame);
      await new Promise((x) => (frame.onload = x));
      return frame;
    }
    JAVASCRIPT
    page.evaluate_handle(js, frame_id, url).as_element.content_frame
  end
end

module Utils::DetachFrame
  def detach_frame(page, frame_id)
    js = <<~JAVASCRIPT
    function detachFrame(frameId) {
      const frame = document.getElementById(frameId);
      frame.remove();
    }
    JAVASCRIPT
    page.evaluate(js, frame_id)
  end
end

module Utils::NavigateFrame
  def navigate_frame(page, frame_id, url)
    js = <<~JAVASCRIPT
    function navigateFrame(frameId, url) {
      const frame = document.getElementById(frameId);
      frame.src = url;
      return new Promise((x) => (frame.onload = x));
    }
    JAVASCRIPT
    page.evaluate(js, frame_id, url)
  end
end

module Utils::DumpFrames
  def dump_frames(frame, indentation = '')
    description = frame.url.gsub(/:\d+\//, ':<PORT>/')
    if frame.name && frame.name.length > 0
      description = "#{description} (#{frame.name})"
    end
    ["#{indentation}#{description}"] + frame.child_frames.flat_map do |child|
      dump_frames(child, "    #{indentation}")
    end
  end
end

module Utils::Favicon
  def favicon_request?(request_or_response)
    url = request_or_response.url
    url.include?('favicon.ico')
  end
end

module Utils::WaitEvent
  def wait_for_event(emitter, event_name, timeout_ms: 5000, predicate: nil)
    predicate ||= ->(_event) { true }
    promise = Async::Promise.new
    listener = nil
    listener = lambda do |*args|
      event = args.first
      next unless predicate.call(event)

      emitter.off(event_name, listener)
      promise.resolve(event)
    end
    emitter.on(event_name, &listener)

    begin
      Puppeteer::AsyncUtils.async_timeout(timeout_ms, promise).wait
    ensure
      emitter.off(event_name, listener)
    end
  end
end
