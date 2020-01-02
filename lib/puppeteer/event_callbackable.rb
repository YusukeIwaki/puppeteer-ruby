module Puppeteer::EventCallbackable
  def on_event(event_name, &block)
    @event_callbackable_handlers ||= {}
    @event_callbackable_handlers[event_name] = block
  end

  def ignore_event(event_name)
    @event_callbackable_handlers ||= {}
    @event_callbackable_handlers.delete(event_name)
  end

  def emit_event(event_name, *args, **kwargs)
    @event_callbackable_handlers ||= {}
    @event_callbackable_handlers[event_name]&.call(*args, **kwargs)
  end
end
