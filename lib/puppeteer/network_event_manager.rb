# Helper class to track network events by request ID
class Puppeteer::NetworkEventManager
  def initialize
    #
    # There are four possible orders of events:
    #  A. `_onRequestWillBeSent`
    #  B. `_onRequestWillBeSent`, `_onRequestPaused`
    #  C. `_onRequestPaused`, `_onRequestWillBeSent`
    #  D. `_onRequestPaused`, `_onRequestWillBeSent`, `_onRequestPaused`,
    #     `_onRequestWillBeSent`, `_onRequestPaused`, `_onRequestPaused`
    #     (see crbug.com/1196004)
    #
    # For `_onRequest` we need the event from `_onRequestWillBeSent` and
    # optionally the `interceptionId` from `_onRequestPaused`.
    #
    # If request interception is disabled, call `_onRequest` once per call to
    # `_onRequestWillBeSent`.
    # If request interception is enabled, call `_onRequest` once per call to
    # `_onRequestPaused` (once per `interceptionId`).
    #
    # Events are stored to allow for subsequent events to call `_onRequest`.
    #
    # Note that (chains of) redirect requests have the same `requestId` (!) as
    # the original request. We have to anticipate series of events like these:
    #  A. `_onRequestWillBeSent`,
    #     `_onRequestWillBeSent`, ...
    #  B. `_onRequestWillBeSent`, `_onRequestPaused`,
    #     `_onRequestWillBeSent`, `_onRequestPaused`, ...
    #  C. `_onRequestWillBeSent`, `_onRequestPaused`,
    #     `_onRequestPaused`, `_onRequestWillBeSent`, ...
    #  D. `_onRequestPaused`, `_onRequestWillBeSent`,
    #     `_onRequestPaused`, `_onRequestWillBeSent`, `_onRequestPaused`,
    #     `_onRequestWillBeSent`, `_onRequestPaused`, `_onRequestPaused`, ...
    #     (see crbug.com/1196004)
    @request_will_be_sent_map = {}
    @request_paused_map = {}
    @http_requests_map = {}
    #
    # The below maps are used to reconcile Network.responseReceivedExtraInfo
    # events with their corresponding request. Each response and redirect
    # response gets an ExtraInfo event, and we don't know which will come first.
    # This means that we have to store a Response or an ExtraInfo for each
    # response, and emit the event when we get both of them. In addition, to
    # handle redirects, we have to make them Arrays to represent the chain of
    # events.
    @response_received_extra_info_map = {}
    @request_will_be_sent_extra_info_map = {}
    @queued_redirect_info_map = {}
    @queued_event_group_map = {}
  end

  def forget(network_request_id)
    @request_will_be_sent_map.delete(network_request_id)
    @request_paused_map.delete(network_request_id)
    @request_will_be_sent_extra_info_map.delete(network_request_id)
    @queued_event_group_map.delete(network_request_id)
    @queued_redirect_info_map.delete(network_request_id)
    @response_received_extra_info_map.delete(network_request_id)
  end

  def request_extra_info(network_request_id)
    @request_will_be_sent_extra_info_map[network_request_id] ||= []
  end

  def response_extra_info(network_request_id)
    @response_received_extra_info_map[network_request_id] ||= []
  end

  private def queued_redirect_info(fetch_request_id)
    @queued_redirect_info_map[fetch_request_id] ||= []
  end

  def enqueue_redirect_info(fetch_request_id, redirect_info)
    queued_redirect_info(fetch_request_id) << redirect_info
  end

  def take_queued_redirect_info(fetch_request_id)
    queued_redirect_info(fetch_request_id).shift
  end

  def num_requests_in_progress
    @http_requests_map.count { |_, request| !request.response }
  end

  def store_request_will_be_sent(network_request_id, event)
    @request_will_be_sent_map[network_request_id] = event
  end

  def get_request_will_be_sent(network_request_id)
    @request_will_be_sent_map[network_request_id]
  end

  def forget_request_will_be_sent(network_request_id)
    @request_will_be_sent_map.delete(network_request_id)
  end

  def store_request_paused(network_request_id, event)
    @request_paused_map[network_request_id] = event
  end

  def get_request_paused(network_request_id)
    @request_paused_map[network_request_id]
  end

  def forget_request_paused(network_request_id)
    @request_paused_map.delete(network_request_id)
  end

  def store_request(network_request_id, request)
    @http_requests_map[network_request_id] = request
  end

  def get_request(network_request_id)
    @http_requests_map[network_request_id]
  end


  def forget_request(network_request_id)
    @http_requests_map.delete(network_request_id)
  end

  def enqueue_event_group(network_request_id, queued_event_group)
    @queued_event_group_map[network_request_id] = queued_event_group
  end

  def get_queued_event_group(network_request_id)
    @queued_event_group_map[network_request_id]
  end

  def forget_queued_event_group(network_request_id)
    @queued_event_group_map.delete(network_request_id)
  end
end
