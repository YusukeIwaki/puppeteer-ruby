class FrameManager
  # @param {!Puppeteer.CDPSession} client
  # @param {!Puppeteer.Page} page
  # @param {boolean} ignoreHTTPSErrors
  # @param {!Puppeteer.TimeoutSettings} timeoutSettings
  def initialize(client, page, ignore_https_errors, timeout_settings)
    @client = client
    @page = page
    @network_manager = NetworkManager.new(client, ignore_https_errors, self)
    @timeout_settings = timeout_settings

    # @type {!Map<string, !Frame>}
    @frames = {}

    # @type {!Map<number, !ExecutionContext>}
    @context_id_to_context = {}

    # @type {!Set<string>}
    @isolated_worlds = Set.new

    # this._client.on('Page.frameAttached', event => this._onFrameAttached(event.frameId, event.parentFrameId));
    # this._client.on('Page.frameNavigated', event => this._onFrameNavigated(event.frame));
    # this._client.on('Page.navigatedWithinDocument', event => this._onFrameNavigatedWithinDocument(event.frameId, event.url));
    # this._client.on('Page.frameDetached', event => this._onFrameDetached(event.frameId));
    # this._client.on('Page.frameStoppedLoading', event => this._onFrameStoppedLoading(event.frameId));
    # this._client.on('Runtime.executionContextCreated', event => this._onExecutionContextCreated(event.context));
    # this._client.on('Runtime.executionContextDestroyed', event => this._onExecutionContextDestroyed(event.executionContextId));
    # this._client.on('Runtime.executionContextsCleared', event => this._onExecutionContextsCleared());
    # this._client.on('Page.lifecycleEvent', event => this._onLifecycleEvent(event));
  end

  # async initialize() {
  #   const [,{frameTree}] = await Promise.all([
  #     this._client.send('Page.enable'),
  #     this._client.send('Page.getFrameTree'),
  #   ]);
  #   this._handleFrameTree(frameTree);
  #   await Promise.all([
  #     this._client.send('Page.setLifecycleEventsEnabled', { enabled: true }),
  #     this._client.send('Runtime.enable', {}).then(() => this._ensureIsolatedWorld(UTILITY_WORLD_NAME)),
  #     this._networkManager.initialize(),
  #   ]);
  # }

  def network_manager
    @network_manager
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
end
