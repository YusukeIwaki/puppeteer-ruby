# providing #valueFromRemoteObject, #releaseObject
class Puppeteer::RemoteObject
  include Puppeteer::DebugPrint
  using Puppeteer::AsyncAwaitBehavior

  # @param payload [Hash]
  def initialize(payload)
    @object_id = payload["objectId"]
    @sub_type = payload["subtype"]
  end

  attr_reader :sub_type

  # @return [Future<Puppeteer::RemoteObject|nil>]
  async def evaluate_self(client)
    # ported logic from JSHandle#json_value.

    # original logic:
    #   if (this._remoteObject.objectId) {
    #     const response = await this._client.send('Runtime.callFunctionOn', {
    #       functionDeclaration: 'function() { return this; }',
    #       objectId: this._remoteObject.objectId,
    #       returnByValue: true,
    #       awaitPromise: true,
    #     });
    #     return helper.valueFromRemoteObject(response.result);
    #   }

    if @object_id
      params = {
        'functionDeclaration': 'function() { return this; }',
        'objectId': @object_id,
        'returnByValue': true,
        'awaitPromise': true,
      }
      response = await client.send_message("Runtime.callFunctionOn", params)
      Puppeteer::RemoteObject.new(response["result"])
    else
      nil
    end
  end

  # helper#valueFromRemoteObject
  def value

  end

  # @param client [Puppeteer::CDPSession]
  # @return [Future]
  def release(client)
    return unless @object_id

    client.send_message('Runtime.releaseObject',
      objectId: @object_id,
    ).rescue do |err|
      # Exceptions might happen in case of a page been navigated or closed.
      # Swallow these since they are harmless and we don't leak anything in this case.
      debug_print(err)
      nil
    end
  end
end
