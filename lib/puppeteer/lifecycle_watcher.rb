# https://github.com/puppeteer/puppeteer/blob/master/lib/LifecycleWatcher.js
class Puppeteer::LifecycleWatcher
  class ExpectedLifecycle
    PUPPETEER_TO_PROTOCOL_LIFECYCLE = {
      'load' => 'load',
      'domcontentloaded' => 'DOMContentLoaded',
      'networkidle0' => 'networkIdle',
      'networkidle2' => 'networkAlmostIdle'
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
        [wait_until]
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
      # for (const event of expectedLifecycle) {
      #   if (!frame._lifecycleEvents.has(event))
      #     return false;
      # }
      # for (const child of frame.childFrames()) {
      #   if (!checkLifecycle(child, expectedLifecycle))
      #     return false;
      # }
      true
    end
  end

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

    # this._eventListeners = [
    #   helper.addEventListener(frameManager._client, Events.CDPSession.Disconnected, () => this._terminate(new Error('Navigation failed because browser has disconnected!'))),
    #   helper.addEventListener(this._frameManager, Events.FrameManager.LifecycleEvent, this._checkLifecycleComplete.bind(this)),
    #   helper.addEventListener(this._frameManager, Events.FrameManager.FrameNavigatedWithinDocument, this._navigatedWithinDocument.bind(this)),
    #   helper.addEventListener(this._frameManager, Events.FrameManager.FrameDetached, this._onFrameDetached.bind(this)),
    #   helper.addEventListener(this._frameManager.networkManager(), Events.NetworkManager.Request, this._onRequest.bind(this)),
    # ];

    # this._sameDocumentNavigationPromise = new Promise(fulfill => {
    #   this._sameDocumentNavigationCompleteCallback = fulfill;
    # });

    # this._lifecyclePromise = new Promise(fulfill => {
    #   this._lifecycleCallback = fulfill;
    # });

    # this._newDocumentNavigationPromise = new Promise(fulfill => {
    #   this._newDocumentNavigationCompleteCallback = fulfill;
    # });

    # this._timeoutPromise = this._createTimeoutPromise();
    # this._terminationPromise = new Promise(fulfill => {
    #   this._terminationCallback = fulfill;
    # });
    # this._checkLifecycleComplete();
  end

  # /**
  #  * @param {!Puppeteer.Request} request
  #  */
  # _onRequest(request) {
  #   if (request.frame() !== this._frame || !request.isNavigationRequest())
  #     return;
  #   this._navigationRequest = request;
  # }

  # /**
  #  * @param {!Puppeteer.Frame} frame
  #  */
  # _onFrameDetached(frame) {
  #   if (this._frame === frame) {
  #     this._terminationCallback.call(null, new Error('Navigating frame was detached'));
  #     return;
  #   }
  #   this._checkLifecycleComplete();
  # }

  # /**
  #  * @return {?Puppeteer.Response}
  #  */
  # navigationResponse() {
  #   return this._navigationRequest ? this._navigationRequest.response() : null;
  # }

  # /**
  #  * @param {!Error} error
  #  */
  # _terminate(error) {
  #   this._terminationCallback.call(null, error);
  # }

  # /**
  #  * @return {!Promise<?Error>}
  #  */
  # sameDocumentNavigationPromise() {
  #   return this._sameDocumentNavigationPromise;
  # }

  # /**
  #  * @return {!Promise<?Error>}
  #  */
  # newDocumentNavigationPromise() {
  #   return this._newDocumentNavigationPromise;
  # }

  # /**
  #  * @return {!Promise}
  #  */
  # lifecyclePromise() {
  #   return this._lifecyclePromise;
  # }

  # /**
  #  * @return {!Promise<?Error>}
  #  */
  # timeoutOrTerminationPromise() {
  #   return Promise.race([this._timeoutPromise, this._terminationPromise]);
  # }

  # /**
  #  * @return {!Promise<?Error>}
  #  */
  # _createTimeoutPromise() {
  #   if (!this._timeout)
  #     return new Promise(() => {});
  #   const errorMessage = 'Navigation timeout of ' + this._timeout + ' ms exceeded';
  #   return new Promise(fulfill => this._maximumTimer = setTimeout(fulfill, this._timeout))
  #       .then(() => new TimeoutError(errorMessage));
  # }

  # /**
  #  * @param {!Puppeteer.Frame} frame
  #  */
  # _navigatedWithinDocument(frame) {
  #   if (frame !== this._frame)
  #     return;
  #   this._hasSameDocumentNavigation = true;
  #   this._checkLifecycleComplete();
  # }

  # _checkLifecycleComplete() {
  #   // We expect navigation to commit.
  #   if (!checkLifecycle(this._frame, this._expectedLifecycle))
  #     return;
  #   this._lifecycleCallback();
  #   if (this._frame._loaderId === this._initialLoaderId && !this._hasSameDocumentNavigation)
  #     return;
  #   if (this._hasSameDocumentNavigation)
  #     this._sameDocumentNavigationCompleteCallback();
  #   if (this._frame._loaderId !== this._initialLoaderId)
  #     this._newDocumentNavigationCompleteCallback();

  #   /**
  #    * @param {!Puppeteer.Frame} frame
  #    * @param {!Array<string>} expectedLifecycle
  #    * @return {boolean}
  #    */
  #   function checkLifecycle(frame, expectedLifecycle) {
  #     for (const event of expectedLifecycle) {
  #       if (!frame._lifecycleEvents.has(event))
  #         return false;
  #     }
  #     for (const child of frame.childFrames()) {
  #       if (!checkLifecycle(child, expectedLifecycle))
  #         return false;
  #     }
  #     return true;
  #   }
  # }

  # dispose() {
  #   helper.removeEventListeners(this._eventListeners);
  #   clearTimeout(this._maximumTimer);
  # }
end
