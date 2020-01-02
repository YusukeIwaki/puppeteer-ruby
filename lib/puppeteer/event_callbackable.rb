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

    if kwargs.empty?
      # In Ruby's specification,
      # `method(:x).call(*args, **kwargs)` is equivalent to `x(*args, {})`
      # It often causes unexpected ArgumentError.
      #
      # ----------------
      # def greet
      #   puts 'Hello!'
      # end
      #
      # def call_me(*args, **kwargs)
      #   greet(*args, **kwargs) # => 'Hello!'
      #
      #   method(:greet).call(*args, **kwargs) # => `greet': wrong number of arguments (given 1, expected 0) (ArgumentError)
      # end
      #
      # call_me
      # ----------------
      #
      # This behavior is really annoying, and should be avoided, because we often want to set event handler as below:
      #
      # `on_event 'Some.Event.awesome', &method(:handle_awesome_event)`
      #
      # So Let's avoid it by checking kwargs.
      @event_callbackable_handlers[event_name]&.call(*args)
    else
      @event_callbackable_handlers[event_name]&.call(*args, **kwargs)
    end
  end
end
