class Puppeteer::JSHandle
  using Puppeteer::AsyncAwaitBehavior

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

  # @return [Puppeteer::ExecutionContext]
  def execution_context
    @context
  end

  # @param page_function [String]
  # @return [Object]
  def evaluate(page_function, *args)
    execution_context.evaluate(page_function, self, *args)
  end

  # @param page_function [String]
  # @return [Future<Object>]
  async def async_evaluate(page_function, *args)
    evaluate(page_function, *args)
  end

  # @param page_function [String]
  # @param args {Array<*>}
  # @return [Puppeteer::JSHandle]
  def evaluate_handle(page_function, *args)
    execution_context.evaluate_handle(page_function, self, *args)
  end

  # @param page_function [String]
  # @param args {Array<*>}
  # @return [Future<Puppeteer::JSHandle>]
  async def async_evaluate_handle(page_function, *args)
    evaluate_handle(page_function, *args)
  end

  # /**
  #  * @param {string} propertyName
  #  * @return {!Promise<?JSHandle>}
  #  */
  # async getProperty(propertyName) {
  #   const objectHandle = await this.evaluateHandle((object, propertyName) => {
  #     const result = {__proto__: null};
  #     result[propertyName] = object[propertyName];
  #     return result;
  #   }, propertyName);
  #   const properties = await objectHandle.getProperties();
  #   const result = properties.get(propertyName) || null;
  #   await objectHandle.dispose();
  #   return result;
  # }

  # getProperties in JavaScript.
  # @return [Hash<String, JSHandle>]
  def properties
    response = @remote_object.properties(@client)
    response['result'].each_with_object({}) do |prop, h|
      next unless prop['enumerable']
      h[prop['name']] = Puppeteer::JSHandle.create(
                          context: @context,
                          remote_object: Puppeteer::RemoteObject.new(prop['value']))
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
    @remote_object.evaluate_self(@client) || @remote_object.value
  end

  def as_element
    nil
  end

  # @return [Future]
  def dispose
    return if @disposed

    @disposed = true
    @remote_object.release(@client)
  end

  def disposed?
    @disposed
  end

  # /**
  #  * @override
  #  * @return {string}
  #  */
  # toString() {
  #   if (this._remoteObject.objectId) {
  #     const type =  this._remoteObject.subtype || this._remoteObject.type;
  #     return 'JSHandle@' + type;
  #   }
  #   return 'JSHandle:' + helper.valueFromRemoteObject(this._remoteObject);
  # }
end
