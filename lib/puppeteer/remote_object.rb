# providing #valueFromRemoteObject, #releaseObject
class Puppeteer::RemoteObject
  include Puppeteer::DebugPrint
  using Puppeteer::DefineAsyncMethod

  UNSERIALIZABLE_SENTINEL_KEY = '__puppeteer_unserializable__'
  NUMBER_SENTINEL_KEY = '__puppeteer_number__'
  REGEXP_SENTINEL_KEY = '__puppeteer_regexp__'

  # @param payload [Hash]
  def initialize(payload)
    @object_id = payload['objectId']
    @type = payload['type']
    @sub_type = payload['subtype']
    @unserializable_value = payload['unserializableValue']
    @value = payload['value']
    @description = payload['description']
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
      if @type == 'bigint' || @unserializable_value.end_with?('n')
        return Integer(@unserializable_value.delete_suffix('n'))
      end

      case @unserializable_value
      when '-0'
        -0.0
      when 'NaN'
        Float::NAN
      when 'Infinity'
        Float::INFINITY
      when '-Infinity'
        -Float::INFINITY
      else
        raise NotImplementedError.new("Unsupported unserializable value: #{@unserializable_value}")
      end
    end

    if @sub_type == 'regexp' && @description
      source, flags = parse_regexp(@description)
      return Regexp.new(source, regexp_options(flags))
    end

    normalize_serialized_value(@value)
  end

  private def normalize_serialized_value(value)
    case value
    when Array
      value.map { |item| normalize_serialized_value(item) }
    when Hash
      if value.keys == [UNSERIALIZABLE_SENTINEL_KEY] && value[UNSERIALIZABLE_SENTINEL_KEY] == true
        nil
      elsif value.keys == [NUMBER_SENTINEL_KEY]
        unserializable_number(value[NUMBER_SENTINEL_KEY])
      elsif value.keys == [REGEXP_SENTINEL_KEY] && value[REGEXP_SENTINEL_KEY].is_a?(Hash)
        regexp_value = value[REGEXP_SENTINEL_KEY]
        source = regexp_value['source'].to_s
        flags = regexp_value['flags'].to_s
        Regexp.new(source, regexp_options(flags))
      else
        value.transform_values { |item| normalize_serialized_value(item) }
      end
    else
      value
    end
  end

  private def unserializable_number(value)
    case value
    when '-0'
      -0.0
    when 'NaN'
      Float::NAN
    when 'Infinity'
      Float::INFINITY
    when '-Infinity'
      -Float::INFINITY
    else
      value
    end
  end

  private def parse_regexp(description)
    return [description, ''] unless description.start_with?('/')

    last_slash = description.rindex('/')
    return [description, ''] unless last_slash && last_slash > 0

    source = description[1...last_slash]
    flags = description[(last_slash + 1)..]
    [source, flags || '']
  end

  private def regexp_options(flags)
    options = 0
    options |= Regexp::IGNORECASE if flags.include?('i')
    options |= Regexp::MULTILINE if flags.include?('m')
    options
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
