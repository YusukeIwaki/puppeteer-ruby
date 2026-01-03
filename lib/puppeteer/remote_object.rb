# providing #valueFromRemoteObject, #releaseObject
class Puppeteer::RemoteObject
  include Puppeteer::DebugPrint
  using Puppeteer::DefineAsyncMethod

  # @param payload [Hash]
  def initialize(payload)
    @object_id = payload['objectId']
    @type = payload['type']
    @sub_type = payload['subtype']
    @unserializable_value = payload['unserializableValue']
    @value = payload['value']
  end

  attr_reader :sub_type

  # @return [Future<Puppeteer::RemoteObject|nil>]
  def evaluate_self(client)
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
      response = client.send_message('Runtime.callFunctionOn', params)
      Puppeteer::RemoteObject.new(response['result'])
    else
      nil
    end
  end

  # @return [String]
  def type_str
    # used in JSHandle#to_s
    # original logic:
    #   if (this._remoteObject.objectId) {
    #     const type =  this._remoteObject.subtype || this._remoteObject.type;
    #     return 'JSHandle@' + type;
    #   }
    if @object_id
      @sub_type || @type
    else
      nil
    end
  end

  # used in JSHandle#properties
  def properties(client)
    # original logic:
    #   const response = await this._client.send('Runtime.getProperties', {
    #     objectId: this._remoteObject.objectId,
    #     ownProperties: true
    #   });
    client.send_message('Runtime.getProperties', objectId: @object_id, ownProperties: true)
  end

  # used in ElementHandle#content_frame, ElementHandle#upload_file
  def node_info(client)
    client.send_message('DOM.describeNode', objectId: @object_id)
  end

  # used in ElementHandle#clickable_point
  def content_quads(client)
    client.send_message('DOM.getContentQuads', objectId: @object_id)
  end

  # used in ElementHandle#_box_model
  def box_model(client)
    result = client.send_message('DOM.getBoxModel', objectId: @object_id)

    # Some browsers return zeroed box model data instead of throwing errors.
    model = result['model']
    if model['width'] == 0 && model['height'] == 0 &&
      %w(content padding border margin).all? { |key| model[key].all?(&:nil?) }

      debug_puts('Could not compute box model.')
      return nil
    end
    result
  rescue => err
    debug_puts(err)
    nil
  end

  # used in ElementHandle#query_ax_tree
  def query_ax_tree(client, accessible_name: nil, role: nil)
    result = client.send_message('Accessibility.queryAXTree', {
      objectId: @object_id,
      accessibleName: accessible_name,
      role: role,
    }.compact)

    result['nodes'].select do |node|
      node['role'] && node['role']['value'] != 'StaticText'
    end
  end

  # helper#valueFromRemoteObject
  def value
    if @unserializable_value
      # if (remoteObject.type === 'bigint' && typeof BigInt !== 'undefined')
      #   return BigInt(remoteObject.unserializableValue.replace('n', ''));
      # switch (remoteObject.unserializableValue) {
      #   case '-0':
      #     return -0;
      #   case 'NaN':
      #     return NaN;
      #   case 'Infinity':
      #     return Infinity;
      #   case '-Infinity':
      #     return -Infinity;
      #   default:
      #     throw new Error('Unsupported unserializable value: ' + remoteObject.unserializableValue);
      # }
      raise NotImplementedError.new('unserializable_value is not implemented yet')
    else
      @value
    end
  end

  # @param client [Puppeteer::CDPSession]
  def release(client)
    return unless @object_id

    begin
      client.send_message('Runtime.releaseObject',
        objectId: @object_id,
      )
    rescue => err
      # Exceptions might happen in case of a page been navigated or closed.
      # Swallow these since they are harmless and we don't leak anything in this case.
      debug_puts(err)
    end

    nil
  end

  define_async_method :async_release

  def converted_arg
    # ported logic from ExecutionContext#convertArgument
    # https://github.com/puppeteer/puppeteer/blob/master/lib/ExecutionContext.js
    #
    # Original logic:
    # if (objectHandle._remoteObject.unserializableValue)
    #   return { unserializableValue: objectHandle._remoteObject.unserializableValue };
    # if (!objectHandle._remoteObject.objectId)
    #   return { value: objectHandle._remoteObject.value };
    # return { objectId: objectHandle._remoteObject.objectId };

    if @unserializable_value
      { unserializableValue: @unserializable_value }
    elsif @object_id
      { objectId: @object_id }
    else
      { value: value }
    end
  end

  # used in ElementHandle#upload_file
  def set_file_input_files(client, files, backend_node_id)
    client.send_message('DOM.setFileInputFiles', objectId: @object_id, files: files, backendNodeId: backend_node_id)
  end

  def scroll_into_view_if_needed(client)
    client.send_message('DOM.scrollIntoViewIfNeeded', objectId: @object_id)
  end
end
