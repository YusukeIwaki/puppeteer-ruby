class Puppeteer::JSHandle
  using Puppeteer::DefineAsyncMethod
  include Puppeteer::IfPresent

  # @param context [Puppeteer::ExecutionContext]
  # @param remote_object [Puppeteer::RemoteObject]
  def self.create(context:, remote_object:)
    frame = context.frame
    if remote_object.sub_type == 'node' && frame
      frame_manager = frame.frame_manager
      Puppeteer::ElementHandle.new(
        context: context,
        client: context.client,
        remote_object: remote_object,
        frame: frame,
        page: frame_manager.page,
        frame_manager: frame_manager,
      )
    else
      Puppeteer::JSHandle.new(
        context: context,
        client: context.client,
        remote_object: remote_object,
      )
    end
  end

  # @param context [Puppeteer::ExecutionContext]
  # @param client [Puppeteer::CDPSession]
  # @param remote_object [Puppeteer::RemoteObject]
  def initialize(context:, client:, remote_object:)
    @context = context
    @client = client
    @remote_object = remote_object
    @disposed = false
  end

  attr_reader :context, :remote_object

  def inspect
    values = %i[context remote_object disposed].map do |sym|
      value = instance_variable_get(:"@#{sym}")
      "@#{sym}=#{value}"
    end
    "#<Puppeteer::JSHandle #{values.join(' ')}>"
  end

  # @return [Puppeteer::ExecutionContext]
  def execution_context
    @context
  end

  # @param page_function [String]
  # @return [Object]
  def evaluate(page_function, *args)
    execution_context.evaluate(page_function, self, *args)
  end

  define_async_method :async_evaluate

  # @param page_function [String]
  # @param args {Array<*>}
  # @return [Puppeteer::JSHandle]
  def evaluate_handle(page_function, *args)
    execution_context.evaluate_handle(page_function, self, *args)
  end

  define_async_method :async_evaluate_handle

  # getProperty(propertyName) in JavaScript
  # @param name [String]
  # @return [Puppeteer::JSHandle]
  def property(name)
    js = <<~JAVASCRIPT
    (object, propertyName) => {
      const result = {__proto__: null};
      result[propertyName] = object[propertyName];
      return result;
    }
    JAVASCRIPT
    object_handle = evaluate_handle(js, name)
    properties = object_handle.properties
    result = properties[name]
    object_handle.dispose
    result
  end

  # @param name [String]
  # @return [Puppeteer::JSHandle]
  def [](name)
    property(name)
  end

  # getProperties in JavaScript.
  # @return [Hash<String, JSHandle>]
  def properties
    response = @remote_object.properties(@client)
    response['result'].each_with_object({}) do |prop, h|
      next unless prop['enumerable']
      h[prop['name']] = Puppeteer::JSHandle.create(
        context: @context,
        remote_object: Puppeteer::RemoteObject.new(prop['value']),
      )
    end
  end

  def json_value
    # original logic was:
    #   if (this._remoteObject.objectId) {
    #     const response = await this._client.send('Runtime.callFunctionOn', {
    #       functionDeclaration: 'function() { return this; }',
    #       objectId: this._remoteObject.objectId,
    #       returnByValue: true,
    #       awaitPromise: true,
    #     });
    #     return helper.valueFromRemoteObject(response.result);
    #   }
    #   return helper.valueFromRemoteObject(this._remoteObject);
    #
    # However it would be better that RemoteObject is responsible for
    # the logic `if (this._remoteObject.objectId) { ... }`.
    @remote_object.evaluate_self(@client)&.value || @remote_object.value
  end

  def as_element
    nil
  end

  def dispose
    return if @disposed

    @disposed = true
    @remote_object.release(@client)
  end

  def disposed?
    @disposed
  end

  def to_s
    # original logic was:
    #   if (this._remoteObject.objectId) {
    #     const type =  this._remoteObject.subtype || this._remoteObject.type;
    #     return 'JSHandle@' + type;
    #   }
    #   return 'JSHandle:' + helper.valueFromRemoteObject(this._remoteObject);
    #
    # However it would be better that RemoteObject is responsible for
    # the logic `if (this._remoteObject.objectId) { ... }`.
    if_present(@remote_object.type_str) { |type_str| "JSHandle@#{type_str}" } || "JSHandle:#{@remote_object.value || 'undefined'}"
  end
end
