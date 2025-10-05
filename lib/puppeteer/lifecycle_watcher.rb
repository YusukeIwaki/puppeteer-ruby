require 'thread'

# https://github.com/puppeteer/puppeteer/blob/master/lib/LifecycleWatcher.js
class Puppeteer::LifecycleWatcher
  include Puppeteer::IfPresent

  class ExpectedLifecycle
    PUPPETEER_TO_PROTOCOL_LIFECYCLE = {
      'load' => 'load',
      'domcontentloaded' => 'DOMContentLoaded',
      'networkidle0' => 'networkIdle',
      'networkidle2' => 'networkAlmostIdle',
    }

    def initialize(wait_until)
      if wait_until.is_a?(Enumerable)
        @wait_until = wait_until.map do |value|
          unless PUPPETEER_TO_PROTOCOL_LIFECYCLE.has_key?(value.to_s)
            raise ArgumentError.new("Unknown value for options.waitUntil: #{value}")
          end
          value.to_s
        end
      elsif wait_until.is_a?(String)
        unless PUPPETEER_TO_PROTOCOL_LIFECYCLE.has_key?(wait_until)
          raise ArgumentError.new("Unknown value for options.waitUntil: #{wait_until}")
        end
        @wait_until = [wait_until]
      else
        raise ArgumentError.new('wait_until should be a Array<String> or String')
      end
    end

    private def expected_lifecycle
      @expected_lifecycle ||= @wait_until.map do |value|
        PUPPETEER_TO_PROTOCOL_LIFECYCLE[value]
      end
    end

    # Check if navigation lifecycle has experienced the expected_lifecycle events.
    #
    # @param frame [Puppeteer::Frame]
    def completed?(frame)
      if expected_lifecycle.any? { |event| !frame.lifecycle_events.include?(event) }
        return false
      end
      if frame.child_frames.any? { |child| child.has_started_loading? && !completed?(child) }
        return false
      end
      true
    end
  end

  class FrameDetachedError < StandardError
    def initialize
      super('Navigating frame was detached')
    end
  end
  class TerminatedError < StandardError; end

  #  * @param {!Puppeteer.FrameManager} frameManager
  #  * @param {!Puppeteer.Frame} frame
  #  * @param {string|!Array<string>} waitUntil
  #  * @param {number} timeout
  def initialize(frame_manager, frame, wait_until, timeout)
    @expected_lifecycle = ExpectedLifecycle.new(wait_until)
    @frame_manager = frame_manager
    @frame = frame
    @initial_loader_id = frame.loader_id
    @timeout = timeout

    @listener_ids = {}
    @listener_ids['client'] = @frame_manager.client.add_event_listener(CDPSessionEmittedEvents::Disconnected) do
      terminate(TerminatedError.new('Navigation failed because browser has disconnected!'))
    end
    @listener_ids['frame_manager'] = [
      @frame_manager.add_event_listener(FrameManagerEmittedEvents::LifecycleEvent) do |_|
        check_lifecycle_complete
      end,
      @frame_manager.add_event_listener(FrameManagerEmittedEvents::FrameNavigatedWithinDocument, &method(:navigated_within_document)),
      @frame_manager.add_event_listener(FrameManagerEmittedEvents::FrameNavigated, &method(:navigated)),
      @frame_manager.add_event_listener(FrameManagerEmittedEvents::FrameSwapped, &method(:handle_frame_swapped)),
      @frame_manager.add_event_listener(FrameManagerEmittedEvents::FrameDetached, &method(:handle_frame_detached)),
    ]
    @listener_ids['network_manager'] = [
      @frame_manager.network_manager.add_event_listener(NetworkManagerEmittedEvents::Request, &method(:handle_request)),
      @frame_manager.network_manager.add_event_listener(NetworkManagerEmittedEvents::Response, &method(:handle_response)),
      @frame_manager.network_manager.add_event_listener(NetworkManagerEmittedEvents::RequestFailed, &method(:handle_request_failed)),
    ]

    @same_document_navigation_promise = Concurrent::Promises.resolvable_future
    @lifecycle_promise = Concurrent::Promises.resolvable_future
    @new_document_navigation_promise = Concurrent::Promises.resolvable_future
    @termination_promise = Concurrent::Promises.resolvable_future
    check_lifecycle_complete
  end

  # @param [Puppeteer::HTTPRequest] request
  def handle_request(request)
    return if request.frame != @frame || !request.navigation_request?
    @navigation_request = request
    # Resolve previous navigation response in case there are multiple
    # navigation requests reported by the backend. This generally should not
    # happen by it looks like it's possible.
    @navigation_response_received.fulfill(nil) if @navigation_response_received && !@navigation_response_received.resolved?
    @navigation_response_received = Concurrent::Promises.resolvable_future
    if request.response && !@navigation_response_received.resolved?
      @navigation_response_received.fulfill(nil)
    end
  end

  # @param [Puppeteer::HTTPRequest] request
  def handle_request_failed(request)
    return if @navigation_request&.internal&.request_id != request.internal.request_id

    @navigation_response_received.fulfill(nil) unless @navigation_response_received.resolved?
  end

  # @param [Puppeteer::HTTPResponse] response
  def handle_response(response)
    return if @navigation_request&.internal&.request_id != response.request.internal.request_id

    @navigation_response_received.fulfill(nil) unless @navigation_response_received.resolved?
  end

  # @param frame [Puppeteer::Frame]
  def handle_frame_detached(frame)
    if @frame == frame
      @termination_promise.reject(FrameDetachedError.new)
      return
    end
    check_lifecycle_complete
  end

  # @return [Puppeteer::HTTPResponse]
  def navigation_response
    # Continue with a possibly null response.
    @navigation_response_received.value! rescue nil
    if_present(@navigation_request) do |request|
      request.response
    end
  end

  # @param error [TerminatedError]
  private def terminate(error)
    @termination_promise.reject(error)
  end

  attr_reader(
    :same_document_navigation_promise,
    :new_document_navigation_promise,
    :lifecycle_promise,
  )

  def timeout_or_termination_promise
    if @timeout > 0
      Concurrent::Promises.future(
        &Puppeteer::ConcurrentRubyUtils.future_with_logging do
          Timeout.timeout(@timeout / 1000.0) do
            @termination_promise.value!
          end
        rescue Timeout::Error
          raise Puppeteer::TimeoutError.new("Navigation timeout of #{@timeout}ms exceeded")
        end
      )
    else
      @termination_promise
    end
  end

  # @param frame [Puppeteer::Frame]
  private def navigated_within_document(frame)
    return if frame != @frame
    @has_same_document_navigation = true
    check_lifecycle_complete
  end

  private def navigated(frame)
    return if frame != @frame
    @new_document_navigation = true
    check_lifecycle_complete
  end

  private def handle_frame_swapped(frame)
    return if frame != @frame
    @swapped = true
    check_lifecycle_complete
  end

  private def check_lifecycle_complete
    # We expect navigation to commit.
    return unless @expected_lifecycle.completed?(@frame)
    @lifecycle_promise.fulfill(true) if @lifecycle_promise.pending?
    if @has_same_document_navigation && @same_document_navigation_promise.pending?
      @same_document_navigation_promise.fulfill(true)
    end
    if (@swapped || @frame.loader_id != @initial_loader_id) && @new_document_navigation_promise.pending?
      @new_document_navigation_promise.fulfill(true)
    end
  end

  def dispose
    if_present(@listener_ids['client']) do |id|
      @frame_manager.client.remove_event_listener(id)
    end
    if_present(@listener_ids['frame_manager']) do |ids|
      @frame_manager.remove_event_listener(*ids)
    end
    if_present(@listener_ids['network_manager']) do |ids|
      @frame_manager.network_manager.remove_event_listener(*ids)
    end
  end
end
