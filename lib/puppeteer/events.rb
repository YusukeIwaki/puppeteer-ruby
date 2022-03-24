require 'digest/md5'

module EventsDefinitionUtils
  # symbol is used to prevent external parties listening to these events
  module_function def symbol(str)
    Digest::MD5.hexdigest(str)
  end

  refine Hash do
    def define_const_into(target_module)
      each do |key, value|
        target_module.const_set(key, value)
        target_module.define_singleton_method(key) { value }
      end
      keyset = Set.new(keys)
      valueset = Set.new(values)
      target_module.define_singleton_method(:keys) { keyset }
      target_module.define_singleton_method(:values) { valueset }
    end
  end
end

using EventsDefinitionUtils

# Internal events that the Connection class emits.
module ConnectionEmittedEvents ; end

{
  Disconnected: EventsDefinitionUtils.symbol('Connection.Disconnected'),
}.define_const_into(ConnectionEmittedEvents)

# Internal events that the CDPSession class emits.
module CDPSessionEmittedEvents ; end

{
  Disconnected: EventsDefinitionUtils.symbol('CDPSession.Disconnected'),
}.define_const_into(CDPSessionEmittedEvents)

# All the events a Browser may emit.
module BrowserEmittedEvents ; end

{
  # Emitted when Puppeteer gets disconnected from the Chromium instance. This might happen because of one of the following:
  # - Chromium is closed or crashed
  # - The Browser#disconnect method was called.
  Disconnected: 'disconnected',

  # Emitted when the url of a target changes. Contains a {@link Target} instance.
  TargetChanged: 'targetchanged',

  # Emitted when a target is created, for example when a new page is opened by
  # window.open or by Browser#newPage
  # Contains a Target instance.
  TargetCreated: 'targetcreated',

  # Emitted when a target is destroyed, for example when a page is closed.
  # Contains a Target instance.
  TargetDestroyed: 'targetdestroyed',
}.define_const_into(BrowserEmittedEvents)

module BrowserContextEmittedEvents ; end

{
  # Emitted when the url of a target inside the browser context changes.
  # Contains a Target instance.
  TargetChanged: 'targetchanged',

  # Emitted when a target is created, for example when a new page is opened by
  # window.open or by BrowserContext#newPage
  # Contains a Target instance.
  TargetCreated: 'targetcreated',

  # Emitted when a target is destroyed within the browser context, for example when a page is closed.
  # Contains a Target instance.
  TargetDestroyed: 'targetdestroyed',
}.define_const_into(BrowserContextEmittedEvents)

# We use symbols to prevent any external parties listening to these events.
# They are internal to Puppeteer.
module NetworkManagerEmittedEvents ; end

{
  Request: EventsDefinitionUtils.symbol('NetworkManager.Request'),
  RequestServedFromCache: EventsDefinitionUtils.symbol('NetworkManager.RequestServedFromCache'),
  Response: EventsDefinitionUtils.symbol('NetworkManager.Response'),
  RequestFailed: EventsDefinitionUtils.symbol('NetworkManager.RequestFailed'),
  RequestFinished: EventsDefinitionUtils.symbol('NetworkManager.RequestFinished'),
}.define_const_into(NetworkManagerEmittedEvents)


# We use symbols to prevent external parties listening to these events.
# They are internal to Puppeteer.
module FrameManagerEmittedEvents ; end

{
  FrameAttached: EventsDefinitionUtils.symbol('FrameManager.FrameAttached'),
  FrameNavigated: EventsDefinitionUtils.symbol('FrameManager.FrameNavigated'),
  FrameDetached: EventsDefinitionUtils.symbol('FrameManager.FrameDetached'),
  FrameSwapped: EventsDefinitionUtils.symbol('FrameManager.FrameSwapped'),
  LifecycleEvent: EventsDefinitionUtils.symbol('FrameManager.LifecycleEvent'),
  FrameNavigatedWithinDocument: EventsDefinitionUtils.symbol('FrameManager.FrameNavigatedWithinDocument'),
  ExecutionContextCreated: EventsDefinitionUtils.symbol('FrameManager.ExecutionContextCreated'),
  ExecutionContextDestroyed: EventsDefinitionUtils.symbol('FrameManager.ExecutionContextDestroyed'),
}.define_const_into(FrameManagerEmittedEvents)

# All the events that a page instance may emit.
module PageEmittedEvents ; end

{
  # Emitted when the page closes.
  Close: 'close',

  # Emitted when JavaScript within the page calls one of console API methods,
  # e.g. `console.log` or `console.dir`. Also emitted if the page throws an
  # error or a warning.
  Console: 'console',

  # Emitted when a JavaScript dialog appears, such as `alert`, `prompt`,
  # `confirm` or `beforeunload`. Puppeteer can respond to the dialog via
  # Dialog#accept or Dialog#dismiss.
  Dialog: 'dialog',

  # Emitted when the JavaScript
  # {https://developer.mozilla.org/en-US/docs/Web/Events/DOMContentLoaded DOMContentLoaded} event is dispatched.
  DOMContentLoaded: 'domcontentloaded',

  # Emitted when the page crashes. Will contain an `Error`.
  Error: 'error',

  # Emitted when a frame is attached. Will contain a Frame.
  FrameAttached: 'frameattached',
  # Emitted when a frame is detached. Will contain a Frame.
  FrameDetached: 'framedetached',
  # Emitted when a frame is navigated to a new URL. Will contain a {@link Frame}.
  FrameNavigated: 'framenavigated',

  # Emitted when the JavaScript
  # {https://developer.mozilla.org/en-US/docs/Web/Events/load | load} event is dispatched.
  Load: 'load',

  # Emitted when the JavaScript code makes a call to `console.timeStamp`. For
  # the list of metrics see {@link Page.metrics | page.metrics}.
  #
  # Contains an object with two properties:
  # - `title`: the title passed to `console.timeStamp`
  # - `metrics`: objec containing metrics as key/value pairs. The values will be `number`s.
  Metrics: 'metrics',

  # Emitted when an uncaught exception happens within the page.
  # Contains an `Error`.
  PageError: 'pageerror',

  # Emitted when the page opens a new tab or window.
  # Contains a Page corresponding to the popup window.
  Popup: 'popup',

  # Emitted when a page issues a request and contains a HTTPRequest.
  #
  # The object is readonly. See Page#setRequestInterception for intercepting and mutating requests.
  Request: 'request',

  # Emitted when a request fails, for example by timing out.
  #
  # Contains a HTTPRequest.
  #
  # NOTE: HTTP Error responses, such as 404 or 503, are still successful
  # responses from HTTP standpoint, so request will complete with
  # `requestfinished` event and not with `requestfailed`.
  RequestFailed: 'requestfailed',

  # Emitted when a request finishes successfully. Contains a HTTPRequest.
  RequestFinished: 'requestfinished',

  # Emitted when a response is received. Contains a HTTPResponse.
  Response: 'response',

  # Emitted when a dedicated
  # {https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API WebWorker} is spawned by the page.
  WorkerCreated: 'workercreated',

  # Emitted when a dedicated
  # {https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API WebWorker} is destroyed by the page.
  WorkerDestroyed: 'workerdestroyed',
}.define_const_into(PageEmittedEvents)
