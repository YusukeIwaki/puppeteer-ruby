require 'securerandom'

module Puppeteer::EventCallbackable
  class EventListeners
    include Enumerable

    def initialize
      @listeners = {}
    end

    # @return [String] Listener ID
    def add(&block)
      id = SecureRandom.hex(8)
      @listeners[id] = block
      id
    end

    # @param id [String] Listener ID returned on #add
    def delete(id)
      @listeners.delete(id)
    end

    # @implement Enumerable#each
    def each(&block)
      @listeners.values.each(&block)
    end
  end

  def add_event_listener(event_name, &block)
    @event_listeners ||= {}
    (@event_listeners[event_name] ||= EventListeners.new).add(&block)
  end

  alias_method :on, :add_event_listener

  def remove_event_listener(*id_args)
    (@event_listeners ||= {}).each do |event_name, listeners|
      id_args.each do |id|
        listeners.delete(id)
      end
    end
  end

  def observe_first(event_name, &block)
    listener_id = add_event_listener(event_name) do |*args, **kwargs|
      if kwargs.empty?
        block.call(*args)
      else
        block.call(*args, **kwargs)
      end
      remove_event_listener(listener_id)
    end
  end

  alias_method :once, :observe_first

  def on_event(event_name, &block)
    @event_callbackable_handlers ||= {}
    @event_callbackable_handlers[event_name] = block
  end

  def emit_event(event_name, *args, **kwargs)
    @event_callbackable_handlers ||= {}
    @event_listeners ||= {}

    if kwargs.empty?
      # In Ruby's specification (version < 2.7),
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
      @event_listeners[event_name]&.each do |proc|
        proc.call(*args)
      end
    else
      @event_callbackable_handlers[event_name]&.call(*args, **kwargs)
      @event_listeners[event_name]&.each do |proc|
        proc.call(*args, **kwargs)
      end
    end

    event_name
  end
end
