require 'timeout'

class Puppeteer::FrameManager
  include Puppeteer::DebugPrint
  include Puppeteer::IfPresent
  include Puppeteer::EventCallbackable
  using Puppeteer::AsyncAwaitBehavior

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
    @context_id_created = {}

    # @type {!Set<string>}
    @isolated_worlds = Set.new

    @client.on_event 'Page.frameAttached' do |event|
      handle_frame_attached(event['frameId'], event['parentFrameId'])
    end
    @client.on_event 'Page.frameNavigated' do |event|
      handle_frame_navigated(event['frame'])
    end
    @client.on_event 'Page.navigatedWithinDocument' do |event|
      handle_frame_navigated_within_document(event['frameId'], event['url'])
    end
    @client.on_event 'Page.frameDetached' do |event|
      handle_frame_detached(event['frameId'])
    end
    @client.on_event 'Page.frameStoppedLoading' do |event|
      handle_frame_stopped_loading(event['frameId'])
    end
    @client.on_event 'Runtime.executionContextCreated' do |event|
      handle_execution_context_created(event['context'])
    end
    @client.on_event 'Runtime.executionContextDestroyed' do |event|
      handle_execution_context_destroyed(event['executionContextId'])
    end
    @client.on_event 'Runtime.executionContextsCleared' do |event|
      handle_execution_contexts_cleared
    end
    @client.on_event 'Page.lifecycleEvent' do |event|
      handle_lifecycle_event(event)
    end
  end

  attr_reader :client, :timeout_settings

  private def init
    results = await_all(
      @client.async_send_message('Page.enable'),
      @client.async_send_message('Page.getFrameTree'),
    )
    frame_tree = results.last['frameTree']
    handle_frame_tree(frame_tree)
    await_all(
      @client.async_send_message('Page.setLifecycleEventsEnabled', enabled: true),
      @client.async_send_message('Runtime.enable'),
    )
    ensure_isolated_world(UTILITY_WORLD_NAME)
    @network_manager.init
  end

  async def async_init
    init
  end

  attr_reader :network_manager

  class NavigationError < StandardError; end

  # @param frame [Puppeteer::Frame]
  # @param url [String]
  # @param {!{referer?: string, timeout?: number, waitUntil?: string|!Array<string>}=} options
  # @return [Puppeteer::Response]
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
    ensure
      watcher.dispose
    end

    watcher.navigation_response
  end

  # @param timeout [number|nil]
  # @param wait_until [string|nil] 'load' | 'domcontentloaded' | 'networkidle0' | 'networkidle2'
  # @return [Puppeteer::Response]
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
    ensure
      watcher.dispose
    end

    watcher.navigation_response
  end

  # @param event [Hash]
  def handle_lifecycle_event(event)
    frame = @frames[event['frameId']]
    return if !frame
    frame.handle_lifecycle_event(event['loaderId'], event['name'])
    emit_event 'Events.FrameManager.LifecycleEvent', frame
  end

  # @param {string} frameId
  def handle_frame_stopped_loading(frame_id)
    frame = @frames[frame_id]
    return if !frame
    frame.handle_loading_stopped
    emit_event 'Events.FrameManager.LifecycleEvent', frame
  end

  # @param frame_tree [Hash]
  def handle_frame_tree(frame_tree)
    if frame_tree['frame']['parentId']
      handle_frame_attached(frame_tree['frame']['id'], frame_tree['frame']['parentId'])
    end
    handle_frame_navigated(frame_tree['frame'])
    return if !frame_tree['childFrames']

    frame_tree['childFrames'].each do |child|
      handle_frame_tree(child)
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

  # @param {string} frameId
  # @param {?string} parentFrameId
  def handle_frame_attached(frame_id, parent_frame_id)
    return if @frames.has_key?[frame_id]
    if !parent_frame_id
      raise ArgymentError.new('parent_frame_id must not be nil')
    end
    parent_frame = @frames[parent_frame_id]
    frame = Frame.new(self, @client, parent_frame, frame_id)
    @frames[frame_id] = frame

    emit_event 'Events.FrameManager.FrameAttached', frame
  end

  # @param frame_payload [Hash]
  def handle_frame_navigated(frame_payload)
    is_main_frame = !frame_payload['parent_id']
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
        frame = Puppeteer::Frame.new(self, @client, nil, frame_payload['id'])
      end
      @frames[frame_payload['id']] = frame
      @main_frame = frame
    end

    # Update frame payload.
    frame.navigated(frame_payload)

    emit_event 'Events.FrameManager.FrameNavigated', frame
  end

  # @param name [String]
  def ensure_isolated_world(name)
    return if @isolated_worlds.include?(name)
    @isolated_worlds << name

    @client.send_message('Page.addScriptToEvaluateOnNewDocument',
      source: "//# sourceURL=#{Puppeteer::ExecutionContext::EVALUATION_SCRIPT_URL}",
      worldName: name,
    )
    create_isolated_worlds_promises = frames.map do |frame|
      @client.async_send_message('Page.createIsolatedWorld',
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
    return if !frame
    frame.navigated_within_document(url)
    emit_event 'Events.FrameManager.FrameNavigatedWithinDocument', frame
    emit_event 'Events.FrameManager.FrameNavigated', frame
    handle_frame_manager_frame_navigated_within_document(frame)
    handle_frame_manager_frame_navigated(frame)
  end

  # @param frame_id [String]
  def handle_frame_detached(frame_id)
    frame = @frames[frame_id]
    if frame
      remove_frame_recursively(frame)
    end
  end

  # @param context_payload [Hash]
  def handle_execution_context_created(context_payload)
    frame = if_present(context_payload.dig('auxData', 'frameId')) { |frame_id| @frames[frame_id] }

    world = nil
    if frame
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

    context = Puppeteer::ExecutionContext.new(@client, context_payload, world)
    if world
      world.context = context
    end
    @context_id_to_context[context_payload['id']] = context
    @context_id_created[context_payload['id']] = Time.now
  end

  # @param {number} executionContextId
  def handle_execution_context_destroyed(execution_context_id)
    context = @context_id_to_context[execution_context_id]
    return if !context
    @context_id_to_context.delete(execution_context_id)
    @context_id_created.delete(execution_context_id)
    if context.world
      context.world.delete_context(execution_context_id)
    end
  end

  def handle_execution_contexts_cleared
    # executionContextCleared is often notified after executionContextCreated.
    #   D, [2020-04-06T01:47:03.101227 #13823] DEBUG -- : RECV << {"method"=>"Runtime.executionContextCreated", "params"=>{"context"=>{"id"=>5, "origin"=>"https://github.com", "name"=>"", "auxData"=>{"isDefault"=>true, "type"=>"default", "frameId"=>"71C347B70848B89DDDEFAA8AB5B0BC92"}}}, "sessionId"=>"53F088EED260C28001D26A019F95D9E3"}
    #   D, [2020-04-06T01:47:03.101439 #13823] DEBUG -- : RECV << {"method"=>"Page.frameNavigated", "params"=>{"frame"=>{"id"=>"71C347B70848B89DDDEFAA8AB5B0BC92", "loaderId"=>"80338225D035AC96BAE8F6D4E81C7D51", "url"=>"https://github.com/search?q=puppeteer", "securityOrigin"=>"https://github.com", "mimeType"=>"text/html"}}, "sessionId"=>"53F088EED260C28001D26A019F95D9E3"}
    #   D, [2020-04-06T01:47:03.101325 #13823] DEBUG -- : RECV << {"method"=>"Target.targetInfoChanged", "params"=>{"targetInfo"=>{"targetId"=>"71C347B70848B89DDDEFAA8AB5B0BC92", "type"=>"page", "title"=>"https://github.com/search?q=puppeteer", "url"=>"https://github.com/search?q=puppeteer", "attached"=>true, "browserContextId"=>"AF37BC660284CE1552B4ECB147BE9305"}}}
    #   D, [2020-04-06T01:47:03.101269 #13823] DEBUG -- : RECV << {"method"=>"Runtime.executionContextsCleared", "params"=>{}, "sessionId"=>"53F088EED260C28001D26A019F95D9E3"}
    # it unexpectedly clears the created execution context.
    # To avoid the problem, just skip recent created ids.
    now = Time.now
    context_ids_to_skip = @context_id_created.select { |k, v| now - v < 1 }.keys
    @context_id_to_context.reject { |k, v| context_ids_to_skip.include?(k) }.each_value do |context_id, context|
      if context.world
        context.world.delete_context(execution_context_id)
      end
    end
    @context_id_to_context.select! { |k, v| context_ids_to_skip.include?(k) }
  end

  def execution_context_by_id(context_id)
    context = @context_id_to_context[context_id]
    if !context
      raise "INTERNAL ERROR: missing context with id = #{context_id}"
    end
    context
  end

  # @param {!Frame} frame
  private def remove_frame_recursively(frame)
    frame.child_frames.each do |child|
      remove_frame_recursively(child)
    end
    frame.detach
    @frames.delete(frame.id)
    emit_event 'Events.FrameManager.FrameDetached', frame
  end

  private def assert_no_legacy_navigation_options(wait_until:)
    if wait_until == 'networkidle'
      raise ArgumentError.new('ERROR: "networkidle" option is no longer supported. Use "networkidle2" instead')
    end
  end
end
