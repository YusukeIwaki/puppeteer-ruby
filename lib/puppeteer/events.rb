require 'digest/md5'

module EventsDefinitionUtils
  refine Kernel do
    # Symbol is used to prevent external parties listening to these events
    def Symbol(str)
      Digest::MD5.hexdigest(str)
    end
  end

  refine Hash do
    def define_const_into(target_module)
      self.each do |key, value|
        target_module.const_set(key, value)
        target_module.define_singleton_method(key) { value }
      end
    end
  end
end

using EventsDefinitionUtils

module Events ; end

# @see https://github.com/puppeteer/puppeteer/blob/main/src/common/Events.ts
{
  Page: {
    Close: 'close',
    Console: 'console',
    Dialog: 'dialog',
    DOMContentLoaded: 'domcontentloaded',
    Error: 'error',
    PageError: 'pageerror',
    Request: 'request',
    Response: 'response',
    RequestFailed: 'requestfailed',
    RequestFinished: 'requestfinished',
    FrameAttached: 'frameattached',
    FrameDetached: 'framedetached',
    FrameNavigated: 'framenavigated',
    Load: 'load',
    Metrics: 'metrics',
    Popup: 'popup',
    WorkerCreated: 'workercreated',
    WorkerDestroyed: 'workerdestroyed',
  },

  Browser: {
    TargetCreated: 'targetcreated',
    TargetDestroyed: 'targetdestroyed',
    TargetChanged: 'targetchanged',
    Disconnected: 'disconnected',
  },

  BrowserContext: {
    TargetCreated: 'targetcreated',
    TargetDestroyed: 'targetdestroyed',
    TargetChanged: 'targetchanged',
  },

}.each do |subtree, values|
  new_module = Module.new
  values.define_const_into(new_module)
  Events.const_set(subtree, new_module)
  Events.define_singleton_method(subtree) { new_module }
end


# Internal events that the Connection class emits.
module ConnectionEmittedEvents ; end

{
  Disconnected: Symbol('Connection.Disconnected'),
}.define_const_into(ConnectionEmittedEvents)

# Internal events that the CDPSession class emits.
module CDPSessionEmittedEvents ; end

{
  Disconnected: Symbol('CDPSession.Disconnected'),
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
  Request: Symbol('NetworkManager.Request'),
  Response: Symbol('NetworkManager.Response'),
  RequestFailed: Symbol('NetworkManager.RequestFailed'),
  RequestFinished: Symbol('NetworkManager.RequestFinished'),
}.define_const_into(NetworkManagerEmittedEvents)


# We use symbols to prevent external parties listening to these events.
# They are internal to Puppeteer.
module FrameManagerEmittedEvents ; end

{
  FrameAttached: Symbol('FrameManager.FrameAttached'),
  FrameNavigated: Symbol('FrameManager.FrameNavigated'),
  FrameDetached: Symbol('FrameManager.FrameDetached'),
  LifecycleEvent: Symbol('FrameManager.LifecycleEvent'),
  FrameNavigatedWithinDocument: Symbol(
    'FrameManager.FrameNavigatedWithinDocument'
  ),
  ExecutionContextCreated: Symbol('FrameManager.ExecutionContextCreated'),
  ExecutionContextDestroyed: Symbol('FrameManager.ExecutionContextDestroyed'),
}.define_const_into(FrameManagerEmittedEvents)
