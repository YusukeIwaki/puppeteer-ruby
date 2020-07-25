module Utils
  module AttachFrame
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
end
