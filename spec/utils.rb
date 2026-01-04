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
