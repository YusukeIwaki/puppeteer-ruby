# frozen_string_literal: true

class Puppeteer::AbortSignal
  def initialize
    @aborted = false
    @reason = nil
    @listeners = {}
    @next_listener_id = 0
    @mutex = Mutex.new
  end

  def aborted?
    @aborted
  end

  def reason
    @reason
  end

  def throw_if_aborted
    return unless @aborted

    raise(@reason || Puppeteer::AbortError.new)
  end

  def add_event_listener(event_name, &block)
    return nil unless event_name.to_s == 'abort'
    return nil unless block

    id = nil
    @mutex.synchronize do
      id = (@next_listener_id += 1)
      @listeners[id] = block
    end

    block.call(@reason) if @aborted

    id
  end

  def remove_event_listener(listener_id)
    @mutex.synchronize { @listeners.delete(listener_id) }
  end

  def abort(reason = nil)
    @mutex.synchronize do
      return if @aborted

      @aborted = true
      @reason = reason || Puppeteer::AbortError.new
    end

    @listeners.values.each do |listener|
      listener.call(@reason)
    end
  end
end

class Puppeteer::AbortController
  def initialize
    @signal = Puppeteer::AbortSignal.new
  end

  attr_reader :signal

  def abort(reason = nil)
    @signal.abort(reason)
  end
end
