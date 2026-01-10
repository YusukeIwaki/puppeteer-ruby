# rbs_inline: enabled

require 'time'

class Puppeteer::JSHandle
  using Puppeteer::DefineAsyncMethod
  include Puppeteer::IfPresent

  # @param context [Puppeteer::ExecutionContext]
  # @param remote_object [Puppeteer::RemoteObject]
  def self.create(context:, remote_object:)
    if remote_object.sub_type == 'node' && context.world
      Puppeteer::ElementHandle.new(
        context: context,
        client: context.client,
        remote_object: remote_object,
        frame: context.world.frame,
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
    @moved = false
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
      next unless prop['enumerable'] && prop['value']
      h[prop['name']] = Puppeteer::JSHandle.create(
        context: @context,
        remote_object: Puppeteer::RemoteObject.new(prop['value']),
      )
    end
  end

  def json_value
    if @remote_object.sub_type == 'date'
      iso_value = evaluate('(object) => object.toISOString()')
      return Time.iso8601(iso_value) if iso_value
    end

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

  # @rbs return: void
  def dispose_symbol
    if @moved
      @moved = false
      return
    end

    dispose
  end

  define_async_method :async_dispose_symbol

  # @rbs return: self
  def move
    @moved = true
    self
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
    if_present(@remote_object.type_str) { |type_str| "JSHandle@#{type_str}" } || "JSHandle:#{stringify_remote_value}"
  end

  # @rbs return: String
  private def stringify_remote_value
    value = @remote_object.value
    return value unless value.nil?

    return 'undefined' if @remote_object.type == 'undefined'
    return 'null' if @remote_object.sub_type == 'null'

    'undefined'
  end
end
