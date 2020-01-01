class Puppeteer::FrameManager
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

  def init
    @client.send_message('Page.enable')
    result = @client.send_message('Page.getFrameTree')
    frame_tree = result['frameTree']
    handle_frame_tree(frame_tree)
    @client.send_message('Page.setLifecycleEventsEnabled', enabled: true)
    @client.send_message('Runtime.enable')
    ensure_isolated_world(UTILITY_WORLD_NAME)
    @network_manager.init
  end

  # @return {!NetworkManager}
  def network_manager
    @network_manager
  end

  #   /**
  #   * @param {!Puppeteer.Frame} frame
  #   * @param {string} url
  #   * @param {!{referer?: string, timeout?: number, waitUntil?: string|!Array<string>}=} options
  #   * @return {!Promise<?Puppeteer.Response>}
  #   */
  #  async navigateFrame(frame, url, options = {}) {
  #    assertNoLegacyNavigationOptions(options);
  #    const {
  #      referer = this._networkManager.extraHTTPHeaders()['referer'],
  #      waitUntil = ['load'],
  #      timeout = this._timeoutSettings.navigationTimeout(),
  #    } = options;

  #    const watcher = new LifecycleWatcher(this, frame, waitUntil, timeout);
  #    let ensureNewDocumentNavigation = false;
  #    let error = await Promise.race([
  #      navigate(this._client, url, referer, frame._id),
  #      watcher.timeoutOrTerminationPromise(),
  #    ]);
  #    if (!error) {
  #      error = await Promise.race([
  #        watcher.timeoutOrTerminationPromise(),
  #        ensureNewDocumentNavigation ? watcher.newDocumentNavigationPromise() : watcher.sameDocumentNavigationPromise(),
  #      ]);
  #    }
  #    watcher.dispose();
  #    if (error)
  #      throw error;
  #    return watcher.navigationResponse();

  #    /**
  #     * @param {!Puppeteer.CDPSession} client
  #     * @param {string} url
  #     * @param {string} referrer
  #     * @param {string} frameId
  #     * @return {!Promise<?Error>}
  #     */
  #    async function navigate(client, url, referrer, frameId) {
  #      try {
  #        const response = await client.send('Page.navigate', {url, referrer, frameId});
  #        ensureNewDocumentNavigation = !!response.loaderId;
  #        return response.errorText ? new Error(`${response.errorText} at ${url}`) : null;
  #      } catch (error) {
  #        return error;
  #      }
  #    }
  #  }

  #  /**
  #   * @param {!Puppeteer.Frame} frame
  #   * @param {!{timeout?: number, waitUntil?: string|!Array<string>}=} options
  #   * @return {!Promise<?Puppeteer.Response>}
  #   */
  #  async waitForFrameNavigation(frame, options = {}) {
  #    assertNoLegacyNavigationOptions(options);
  #    const {
  #      waitUntil = ['load'],
  #      timeout = this._timeoutSettings.navigationTimeout(),
  #    } = options;
  #    const watcher = new LifecycleWatcher(this, frame, waitUntil, timeout);
  #    const error = await Promise.race([
  #      watcher.timeoutOrTerminationPromise(),
  #      watcher.sameDocumentNavigationPromise(),
  #      watcher.newDocumentNavigationPromise()
  #    ]);
  #    watcher.dispose();
  #    if (error)
  #      throw error;
  #    return watcher.navigationResponse();
  #  }

  #  /**
  #   * @param {!Protocol.Page.lifecycleEventPayload} event
  #   */
  #  _onLifecycleEvent(event) {
  #    const frame = this._frames.get(event.frameId);
  #    if (!frame)
  #      return;
  #    frame._onLifecycleEvent(event.loaderId, event.name);
  #    this.emit(Events.FrameManager.LifecycleEvent, frame);
  #  }

  #  /**
  #   * @param {string} frameId
  #   */
  #  _onFrameStoppedLoading(frameId) {
  #    const frame = this._frames.get(frameId);
  #    if (!frame)
  #      return;
  #    frame._onLoadingStopped();
  #    this.emit(Events.FrameManager.LifecycleEvent, frame);
  #  }

  # @param {!Protocol.Page.FrameTree} frameTree
  def handle_frame_tree(frame_tree)
    if frame_tree.frame.parent_id
      handle_frame_attached(frame_tree.frame.id, frame_tree.frame.parent_id)
    end
    handle_frame_navigated(frame_tree.frame)
    return if frame_tree.child_frames.empty?

    frame_tree.child_frames.each do |child|
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

  # /**
  #  * @param {string} name
  #  */
  # async _ensureIsolatedWorld(name) {
  #   if (this._isolatedWorlds.has(name))
  #     return;
  #   this._isolatedWorlds.add(name);
  #   await this._client.send('Page.addScriptToEvaluateOnNewDocument', {
  #     source: `//# sourceURL=${EVALUATION_SCRIPT_URL}`,
  #     worldName: name,
  #   }),
  #   await Promise.all(this.frames().map(frame => this._client.send('Page.createIsolatedWorld', {
  #     frameId: frame._id,
  #     grantUniveralAccess: true,
  #     worldName: name,
  #   }).catch(debugError))); // frames might be removed before we send this
  # }

  # @param frame_id [String]
  # @param url [String]
  def handle_frame_navigated_within_document(frame_id, url)
    frame = @frames[frame_id]
    return if !frame
    frame.navigated_within_document(url)
    handle_frame_manager_frame_navigated_within_document(frame)
    handle_frame_manager_frame_navigated(frame)
  end

  private def handle_frame_manager_frame_navigated_within_document(frame)
  end

  private def handle_frame_manager_frame_navigated(frame)
  end

  # @param frame_id [String]
  def handle_frame_detached(frame_id)
    frame = @frames[frame_id]
    if frame
      remove_frame_recursively(frame)
    end
  end

  # _onExecutionContextCreated(contextPayload) {
  #   const frameId = contextPayload.auxData ? contextPayload.auxData.frameId : null;
  #   const frame = this._frames.get(frameId) || null;
  #   let world = null;
  #   if (frame) {
  #     if (contextPayload.auxData && !!contextPayload.auxData['isDefault']) {
  #       world = frame._mainWorld;
  #     } else if (contextPayload.name === UTILITY_WORLD_NAME && !frame._secondaryWorld._hasContext()) {
  #       // In case of multiple sessions to the same target, there's a race between
  #       // connections so we might end up creating multiple isolated worlds.
  #       // We can use either.
  #       world = frame._secondaryWorld;
  #     }
  #   }
  #   if (contextPayload.auxData && contextPayload.auxData['type'] === 'isolated')
  #     this._isolatedWorlds.add(contextPayload.name);
  #   /** @type {!ExecutionContext} */
  #   const context = new ExecutionContext(this._client, contextPayload, world);
  #   if (world)
  #     world._setContext(context);
  #   this._contextIdToContext.set(contextPayload.id, context);
  # }

  # @param {number} executionContextId
  def handle_execution_context_destroyed(execution_context_id)
    context = @context_id_to_context[execution_context_id]
    return if !context
    @context_id_to_context.delete(execution_context_id)
    if context.world
      context.world.context = nil
    end
  end

  def handle_execution_contexts_cleared
    @context_id_to_context.values.each do |context|
      if context.world
        context.world.context = nil
      end
    end
    @context_id_to_context.clear
  end

  def execution_context_by_id(context_id)
    context = @context_id_to_context[context_id]
    if !context
      raise "INTERNAL ERROR: missing context with id = #{context_id}"
    end
    return context
  end

  # @param {!Frame} frame
  private def remove_frame_recursively(frame)
    frame.child_frames.each do |child|
      remove_frame_recursively(child)
    end
    frame.detach
    @frames.delete(frame.id)
    handle_frame_manager_frame_detached(frame)
  end

  private def handle_frame_manager_frame_detached(frame)
  end
end
