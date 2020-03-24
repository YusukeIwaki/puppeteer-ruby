# providing #valueFromRemoteObject, #releaseObject
class Puppeteer::RemoteObject
  include Puppeteer::DebugPrint

  # @param payload [Hash]
  def initialize(payload)
    @object_id = payload["objectId"]
  end

  # @param client [Puppeteer::CDPSession]
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
