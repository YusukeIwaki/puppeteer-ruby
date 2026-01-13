class Puppeteer::FrameManager
  include Puppeteer::DebugPrint
  include Puppeteer::IfPresent
  include Puppeteer::EventCallbackable
  using Puppeteer::DefineAsyncMethod

  UTILITY_WORLD_NAME = '__puppeteer_utility_world__'

  # @param {!Puppeteer.CDPSession} client
  # @param {!Puppeteer.Page} page
  # @param {boolean} ignoreHTTPSErrors
  # @param {!Puppeteer.TimeoutSettings} timeoutSettings
  def initialize(client, page, ignore_https_errors, timeout_settings)
    @client = client
    @page = page
    @network_manager = Puppeteer::NetworkManager.new(client, ignore_https_errors, self)
    @timeout_settings = timeout_settings

    # @type {!Map<string, !Frame>}
    @frames = {}

    @frame_naviigated_received = Set.new

    # @type {!Map<number, !ExecutionContext>}
    @context_id_to_context = {}

    # @type {!Set<string>}
    @isolated_worlds = Set.new

    # Keeps track of OOPIF targets/frames (target ID == frame ID for OOPIFs)
    # that are being initialized.
    @frames_pending_target_init = {}

    # Keeps track of frames that are in the process of being attached in #onFrameAttached.
    @frames_pending_attachment = {}

    setup_listeners(@client)
  end

  private def setup_listeners(client)
    client.on_event('Page.frameAttached') do |event|
      handle_frame_attached(client, event['frameId'], event['parentFrameId'])
    end
    client.on_event('Page.frameNavigated') do |event|
      @frame_naviigated_received << event['frame']['id']
      handle_frame_navigated(event['frame'])
    end
    client.on_event('Page.navigatedWithinDocument') do |event|
      handle_frame_navigated_within_document(event['frameId'], event['url'])
    end
    client.on_event('Page.frameDetached') do |event|
      handle_frame_detached(event['frameId'], event['reason'])
    end
    client.on_event('Page.frameStartedLoading') do |event|
      handle_frame_started_loading(event['frameId'])
    end
    client.on_event('Page.frameStoppedLoading') do |event|
      handle_frame_stopped_loading(event['frameId'])
    end
    client.on_event('Runtime.executionContextCreated') do |event|
      handle_execution_context_created(event['context'], client)
    end
    client.on_event('Runtime.executionContextDestroyed') do |event|
      handle_execution_context_destroyed(event['executionContextId'], client)
    end
    client.on_event('Runtime.executionContextsCleared') do |event|
      handle_execution_contexts_cleared(client)
    end
    client.on_event('Page.lifecycleEvent') do |event|
      handle_lifecycle_event(event)
    end
  end

  attr_reader :client, :timeout_settings

  private def init(target_id, cdp_session = nil)
    @frames_pending_target_init[target_id] ||= Async::Promise.new
    client = cdp_session || @client

    promises = [
      client.async_send_message('Page.enable'),
      client.async_send_message('Page.getFrameTree'),
    ].compact
    results = Puppeteer::AsyncUtils.await_promise_all(*promises)
    frame_tree = results[1]['frameTree']
    handle_frame_tree(client, frame_tree)
    Puppeteer::AsyncUtils.await_promise_all(
      client.async_send_message('Page.setLifecycleEventsEnabled', enabled: true),
      client.async_send_message('Runtime.enable'),
    )
    ensure_isolated_world(client, UTILITY_WORLD_NAME)
    @network_manager.init unless cdp_session
  rescue => err
    # The target might have been closed before the initialization finished.
    return if err.message.include?('Target closed') || err.message.include?('Session closed')

    raise
  ensure
    @frames_pending_target_init.delete(target_id)&.resolve(nil)
  end

  define_async_method :async_init

  attr_reader :network_manager

  class NavigationError < Puppeteer::Error; end

  # @param frame [Puppeteer::Frame]
  # @param url [String]
  # @param {!{referer?: string, timeout?: number, waitUntil?: string|!Array<string>}=} options
  # @return [Puppeteer::HTTPResponse]
  def navigate_frame(frame, url, referer: nil, timeout: nil, wait_until: nil)
    assert_no_legacy_navigation_options(wait_until: wait_until)

    navigate_params = {
      url: url,
      referer: referer || @network_manager.extra_http_headers['referer'],
      frameId: frame.id,
    }.compact
    option_wait_until = wait_until || ['load']
    option_timeout = timeout || @timeout_settings.navigation_timeout

    watcher = Puppeteer::LifecycleWatcher.new(self, frame, option_wait_until, option_timeout)
    ensure_new_document_navigation = false

    begin
      navigate = Async do
        Puppeteer::AsyncUtils.future_with_logging do
          result = @client.send_message('Page.navigate', navigate_params)
          loader_id = result['loaderId']
          ensure_new_document_navigation = !!loader_id
          if result['errorText']
            raise NavigationError.new("#{result['errorText']} at #{url}")
          end
        end.call
      end
      Puppeteer::AsyncUtils.await_promise_race(
        navigate,
        watcher.timeout_or_termination_promise,
      )

      Puppeteer::AsyncUtils.await_promise_race(
        watcher.timeout_or_termination_promise,
        if ensure_new_document_navigation
          watcher.new_document_navigation_promise
        else
          watcher.same_document_navigation_promise
        end,
      )

      watcher.navigation_response
    rescue Puppeteer::TimeoutError => err
      raise NavigationError.new(err)
    ensure
      watcher.dispose
    end
  end

  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  # @return [Puppeteer::HTTPResponse]
  def wait_for_frame_navigation(frame, timeout: nil, wait_until: nil)
    assert_no_legacy_navigation_options(wait_until: wait_until)

    option_wait_until = wait_until || ['load']
    option_timeout = timeout || @timeout_settings.navigation_timeout
    watcher = Puppeteer::LifecycleWatcher.new(self, frame, option_wait_until, option_timeout)
    begin
      Puppeteer::AsyncUtils.await_promise_race(
        watcher.timeout_or_termination_promise,
        watcher.same_document_navigation_promise,
        watcher.new_document_navigation_promise,
      )

      watcher.navigation_response
    rescue Puppeteer::TimeoutError => err
      raise NavigationError.new(err)
    ensure
      watcher.dispose
    end
  end

  # @param event [Hash]
  def handle_attached_to_target(target)
    return if target.target_info.type != 'iframe'

    frame = @frames[target.target_info.target_id]
    session = target.session
    frame&.send(:update_client, session)
    setup_listeners(session)
    async_init(target.target_info.target_id, session)
  end

  # @param event [Hash]
  def handle_detached_from_target(target)
    frame = @frames[target.target_id]
    if frame && frame.oop_frame?
      # When an OOP iframe is removed from the page, it
      # will only get a Target.detachedFromTarget event.
      remove_frame_recursively(frame)
    end
  end

  # @param event [Hash]
  def handle_lifecycle_event(event)
    frame = @frames[event['frameId']]
    return if !frame
    frame.handle_lifecycle_event(event['loaderId'], event['name'])
    emit_event(FrameManagerEmittedEvents::LifecycleEvent, frame)
  end

  # @param frame_id [String]
  def handle_frame_started_loading(frame_id)
    frame = @frames[frame_id]
    return if !frame
    frame.handle_loading_started
  end

  # @param frame_id [String]
  def handle_frame_stopped_loading(frame_id)
    frame = @frames[frame_id]
    return if !frame
    frame.handle_loading_stopped
    emit_event(FrameManagerEmittedEvents::LifecycleEvent, frame)
  end

  # @param session [Puppeteer::CDPSession]
  # @param frame_tree [Hash]
  def handle_frame_tree(session, frame_tree)
    if frame_tree['frame']['parentId']
      handle_frame_attached(session, frame_tree['frame']['id'], frame_tree['frame']['parentId'])
    end
    unless @frame_naviigated_received.delete?(frame_tree['frame']['id'])
      handle_frame_navigated(frame_tree['frame'])
    end
    return if !frame_tree['childFrames']

    frame_tree['childFrames'].each do |child|
      handle_frame_tree(session, child)
    end
  end

  # @return {!Puppeteer.Page}
  def page
    @page
  end

  # @return {!Frame}
  def main_frame
    @main_frame
  end

  # @return {!Array<!Frame>}
  def frames
    @frames.values
  end

  # @param {!string} frameId
  # @return {?Frame}
  def frame(frame_id)
    @frames[frame_id]
  end

  # @param session [Puppeteer::CDPSession]
  # @param frameId [String]
  # @param parentFrameId [String]
  def handle_frame_attached(session, frame_id, parent_frame_id)
    if @frames.has_key?(frame_id)
      frame = @frames[frame_id]
      if session && frame.oop_frame?
        # If an OOP iframes becomes a normal iframe again
        # it is first attached to the parent page before
        # the target is removed.
        frame.send(:update_client, session)
      end
      return
    end
    parent_frame = @frames[parent_frame_id]
    if parent_frame
      attach_child_frame(parent_frame, parent_frame_id, frame_id, session)
      return
    end

    if @frames_pending_target_init[parent_frame_id]
      @frames_pending_attachment[frame_id] ||= Async::Promise.new
      Async do
        @frames_pending_target_init[parent_frame_id].wait
        attach_child_frame(@frames[parent_frame_id], parent_frame_id, frame_id, session)
        @frames_pending_attachment.delete(frame_id)&.resolve(nil)
      end
      return
    end

    raise FrameNotFoundError.new("Parent frame #{parent_frame_id} not found.")
  end

  class FrameNotFoundError < Puppeteer::Error ; end

  private def attach_child_frame(parent_frame, parent_frame_id, frame_id, session)
    unless parent_frame
      raise FrameNotFoundError.new("Parent frame #{parent_frame_id} not found.")
    end

    frame = Puppeteer::Frame.new(self, parent_frame, frame_id, session)
    @frames[frame.id] = frame
    emit_event(FrameManagerEmittedEvents::FrameAttached, frame)
    frame
  end

  # @param frame_payload [Hash]
  def handle_frame_navigated(frame_payload)
    frame_id = frame_payload['id']
    is_main_frame = !frame_payload['parentId']


    if @frames_pending_attachment[frame_id]
      Async do
        @frames_pending_attachment[frame_id].wait
        frame = is_main_frame ? @main_frame : @frames[frame_id]
        reattach_frame(frame, frame_id, is_main_frame, frame_payload)
      end
    else
      frame = is_main_frame ? @main_frame : @frames[frame_id]
      reattach_frame(frame, frame_id, is_main_frame, frame_payload)
    end
  end

  private def reattach_frame(frame, frame_id, is_main_frame, frame_payload)
    if !is_main_frame && !frame
      raise "Missing frame isMainFrame=#{is_main_frame}, frameId=#{frame_id}"
    end

    # Detach all child frames first.
    if frame
      frame.child_frames.each do |child|
        remove_frame_recursively(child)
      end
    end

    # Update or create main frame.
    if is_main_frame
      if frame
        # Update frame id to retain frame identity on cross-process navigation.
        @frames.delete(frame.id)
        frame.id = frame_id
      else
        # Initial main frame navigation.
        frame = Puppeteer::Frame.new(self, nil, frame_id, @client)
      end
      @frames[frame_id] = frame
      @main_frame = frame
    end

    # Update frame payload.
    frame.navigated(frame_payload)

    emit_event(FrameManagerEmittedEvents::FrameNavigated, frame)
  end

  # @param session [Puppeteer::CDPSession]
  # @param name [String]
  private def ensure_isolated_world(session, name)
    key = "#{session.id}:#{name}"
    return if @isolated_worlds.include?(key)

    session.send_message('Page.addScriptToEvaluateOnNewDocument',
      source: "//# sourceURL=#{Puppeteer::ExecutionContext::EVALUATION_SCRIPT_URL}",
      worldName: name,
    )
    create_isolated_worlds_promises = frames.
      select { |frame| frame._client == session }.
      map do |frame|
        Async do
          session.send_message('Page.createIsolatedWorld',
            frameId: frame.id,
            grantUniveralAccess: true,
            worldName: name,
          )
        rescue => err
          debug_puts(err)
        end
      end
    Puppeteer::AsyncUtils.await_promise_all(*create_isolated_worlds_promises)
    @isolated_worlds << key
  end

  # @param frame_id [String]
  # @param url [String]
  def handle_frame_navigated_within_document(frame_id, url)
    frame = @frames[frame_id]
    return unless frame
    frame.navigated_within_document(url)
    emit_event(FrameManagerEmittedEvents::FrameNavigatedWithinDocument, frame)
    emit_event(FrameManagerEmittedEvents::FrameNavigated, frame)
  end

  # @param frame_id [String]
  # @param reason [String]
  def handle_frame_detached(frame_id, reason)
    frame = @frames[frame_id]
    if reason == 'remove'
      # Only remove the frame if the reason for the detached event is
      # an actual removement of the frame.
      # For frames that become OOP iframes, the reason would be 'swap'.
      if frame
        remove_frame_recursively(frame)
      end
    elsif reason == 'swap'
      emit_event(FrameManagerEmittedEvents::FrameSwapped, frame)
    end
  end

  # @param context_payload [Hash]
  # @pram session [Puppeteer::CDPSession]
  def handle_execution_context_created(context_payload, session)
    frame = if_present(context_payload.dig('auxData', 'frameId')) { |frame_id| @frames[frame_id] }

    world = nil
    if frame
      # commented out the original implementation for allowing us to use Frame#evaluate on OOP iframe.
      #
      # # Only care about execution contexts created for the current session.
      # return if @client != session

      if context_payload.dig('auxData', 'isDefault')
        world = frame.main_world
      elsif context_payload['name'] == UTILITY_WORLD_NAME && !frame.puppeteer_world.has_context?
        # In case of multiple sessions to the same target, there's a race between
        # connections so we might end up creating multiple isolated worlds.
        # We can use either.
        world = frame.puppeteer_world
      end
    end

    if context_payload.dig('auxData', 'type') == 'isolated'
      @isolated_worlds << context_payload['name']
    end

    context = Puppeteer::ExecutionContext.new(frame&._client || @client, context_payload, world)
    if world
      world.context = context
    end
    key = "#{session.id}:#{context_payload['id']}"
    @context_id_to_context[key] = context
  end

  # @param execution_context_id [Integer]
  # @param session [Puppeteer::CDPSEssion]
  def handle_execution_context_destroyed(execution_context_id, session)
    key = "#{session.id}:#{execution_context_id}"
    context = @context_id_to_context[key]
    return unless context
    @context_id_to_context.delete(key)
    if context.world
      context.world.delete_context(execution_context_id)
    end
  end

  # @param session [Puppeteer::CDPSession]
  def handle_execution_contexts_cleared(session)
    @context_id_to_context.select! do |execution_context_id, context|
      # Make sure to only clear execution contexts that belong
      # to the current session.
      if context.client != session
        true # keep
      else
        if context.world
          context.world.delete_context(execution_context_id)
        end
        false # remove
      end
    end
  end

  def execution_context_by_id(context_id, session)
    key = "#{session.id}:#{context_id}"
    @context_id_to_context[key] or raise "INTERNAL ERROR: missing context with id = #{context_id}"
  end

  # @param {!Frame} frame
  private def remove_frame_recursively(frame)
    frame.child_frames.each do |child|
      remove_frame_recursively(child)
    end
    frame.detach
    @frames.delete(frame.id)
    emit_event(FrameManagerEmittedEvents::FrameDetached, frame)
  end

  private def assert_no_legacy_navigation_options(wait_until:)
    if wait_until == 'networkidle'
      raise ArgumentError.new('ERROR: "networkidle" option is no longer supported. Use "networkidle2" instead')
    end
  end
end
