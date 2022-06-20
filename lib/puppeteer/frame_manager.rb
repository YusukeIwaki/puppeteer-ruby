require 'timeout'

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

    # @type {!Map<number, !ExecutionContext>}
    @context_id_to_context = {}

    # @type {!Set<string>}
    @isolated_worlds = Set.new

    setup_listeners(@client)
  end

  private def setup_listeners(client)
    client.on_event('Page.frameAttached') do |event|
      handle_frame_attached(client, event['frameId'], event['parentFrameId'])
    end
    client.on_event('Page.frameNavigated') do |event|
      handle_frame_navigated(event['frame'])
    end
    client.on_event('Page.navigatedWithinDocument') do |event|
      handle_frame_navigated_within_document(event['frameId'], event['url'])
    end
    client.on_event('Page.frameDetached') do |event|
      handle_frame_detached(event['frameId'], event['reason'])
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
    client.on_event('Target.attachedToTarget') do |event|
      handle_attached_to_target(event)
    end
    client.on_event('Target.detachedFromTarget') do |event|
      handle_detached_from_target(event)
    end
  end

  attr_reader :client, :timeout_settings

  private def init(cdp_session = nil)
    client = cdp_session || @client

    promises = [
      client.async_send_message('Page.enable'),
      client.async_send_message('Page.getFrameTree'),
      cdp_session&.async_send_message('Target.setAutoAttach', {
        autoAttach: true,
        waitForDebuggerOnStart: false,
        flatten: true,
      })
    ].compact
    results = await_all(*promises)
    frame_tree = results[1]['frameTree']
    handle_frame_tree(client, frame_tree)
    await_all(
      client.async_send_message('Page.setLifecycleEventsEnabled', enabled: true),
      client.async_send_message('Runtime.enable'),
    )
    ensure_isolated_world(client, UTILITY_WORLD_NAME)
    @network_manager.init unless cdp_session
  rescue => err
    # The target might have been closed before the initialization finished.
    return if err.message.include?('Target closed') || err.message.include?('Session closed')

    raise
  end

  define_async_method :async_init

  attr_reader :network_manager

  class NavigationError < StandardError; end

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
      navigate = future do
        result = @client.send_message('Page.navigate', navigate_params)
        loader_id = result['loaderId']
        ensure_new_document_navigation = !!loader_id
        if result['errorText']
          raise NavigationError.new("#{result['errorText']} at #{url}")
        end
      end
      await_any(
        navigate,
        watcher.timeout_or_termination_promise,
      )

      document_navigation_promise =
        if ensure_new_document_navigation
          watcher.new_document_navigation_promise
        else
          watcher.same_document_navigation_promise
        end
      await_any(
        document_navigation_promise,
        watcher.timeout_or_termination_promise,
      )
    rescue Puppeteer::TimeoutError => err
      raise NavigationError.new(err)
    ensure
      watcher.dispose
    end

    watcher.navigation_response
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
      await_any(
        watcher.timeout_or_termination_promise,
        watcher.same_document_navigation_promise,
        watcher.new_document_navigation_promise,
      )
    rescue Puppeteer::TimeoutError => err
      raise NavigationError.new(err)
    ensure
      watcher.dispose
    end

    watcher.navigation_response
  end

  # @param event [Hash]
  def handle_attached_to_target(event)
    return if event['targetInfo']['type'] != 'iframe'

    frame = @frames[event['targetInfo']['targetId']]
    session = Puppeteer::Connection.from_session(@client).session(event['sessionId'])

    frame&.send(:update_client, session)
    setup_listeners(session)
    async_init(session)
  end

  # @param event [Hash]
  def handle_detached_from_target(event)
    frame = @frames[event['targetId']]
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

  # @param {string} frameId
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
    handle_frame_navigated(frame_tree['frame'])
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
  # @param parentFrameId [String|nil]
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
    if !parent_frame_id
      raise ArgymentError.new('parent_frame_id must not be nil')
    end
    parent_frame = @frames[parent_frame_id]
    frame = Puppeteer::Frame.new(self, parent_frame, frame_id, session)
    @frames[frame_id] = frame

    emit_event(FrameManagerEmittedEvents::FrameAttached, frame)
  end

  # @param frame_payload [Hash]
  def handle_frame_navigated(frame_payload)
    is_main_frame = !frame_payload['parentId']
    frame =
      if is_main_frame
        @main_frame
      else
        @frames[frame_payload['id']]
      end

    if !is_main_frame && !frame
      raise ArgumentError.new('We either navigate top level or have old version of the navigated frame')
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
        frame.id = frame_payload['id']
      else
        # Initial main frame navigation.
        frame = Puppeteer::Frame.new(self, nil, frame_payload['id'], @client)
      end
      @frames[frame_payload['id']] = frame
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
    @isolated_worlds << key

    session.send_message('Page.addScriptToEvaluateOnNewDocument',
      source: "//# sourceURL=#{Puppeteer::ExecutionContext::EVALUATION_SCRIPT_URL}",
      worldName: name,
    )
    create_isolated_worlds_promises = frames.
      select { |frame| frame._client == session }.
      map do |frame|
        session.async_send_message('Page.createIsolatedWorld',
          frameId: frame.id,
          grantUniveralAccess: true,
          worldName: name,
        )
      end
    await_all(*create_isolated_worlds_promises)
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
      elsif context_payload['name'] == UTILITY_WORLD_NAME && !frame.secondary_world.has_context?
        # In case of multiple sessions to the same target, there's a race between
        # connections so we might end up creating multiple isolated worlds.
        # We can use either.
        world = frame.secondary_world
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
