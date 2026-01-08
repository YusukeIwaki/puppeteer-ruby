# rbs_inline: enabled

class Puppeteer::ExecutionContext
  include Puppeteer::IfPresent
  using Puppeteer::DefineAsyncMethod

  EVALUATION_SCRIPT_URL = 'pprt://__puppeteer_evaluation_script__'
  SOURCE_URL_REGEX = /^[\040\t]*\/\/[@#] sourceURL=\s*(\S*?)\s*$/m

  # @param client [Puppeteer::CDPSession]
  # @param context_payload [Hash]
  # @param world [Puppeteer::IsolaatedWorld?]
  def initialize(client, context_payload, world)
    @client = client
    @world = world
    @context_id = context_payload['id']
    @context_name = context_payload['name']
  end

  attr_reader :client, :world

  # only used in IsolaatedWorld
  private def _context_id
    @context_id
  end

  # only used in IsolaatedWorld::BindingFunction#add_binding_to_context
  private def _context_name
    @context_name
  end

  # @param page_function [String]
  # @return [Object]
  def evaluate(page_function, *args)
    evaluate_internal(true, page_function, *args)
  end

  # @param page_function [String]
  # @return [Puppeteer::JSHandle]
  def evaluate_handle(page_function, *args)
    evaluate_internal(false, page_function, *args)
  end

  class JavaScriptExpression
    def initialize(execution_context, expression, return_by_value)
      @execution_context = execution_context
      @expression = expression
      @return_by_value = return_by_value
    end

    # @param client [Puppeteer::CDPSession]
    # @param context_id [String]
    # @return [Object|JSHandle]
    def evaluate_with(client:, context_id:)
      result = client.send_message('Runtime.evaluate',
        expression: expression_with_source_url,
        contextId: context_id,
        returnByValue: @return_by_value,
        awaitPromise: true,
        userGesture: true,
      )
      # }).catch(rewriteError);

      exception_details = result['exceptionDetails']
      if exception_details
        raise EvaluationError.new("Evaluation failed: #{exception_details}")
      end

      remote_object = Puppeteer::RemoteObject.new(result['result'])
      if @return_by_value
        remote_object.value
      else
        Puppeteer::JSHandle.create(
          context: @execution_context,
          remote_object: remote_object,
        )
      end
    end

    private def suffix
      "//# sourceURL=#{EVALUATION_SCRIPT_URL}"
    end

    private def expression_with_source_url
      if SOURCE_URL_REGEX.match?(@expression)
        @expression
      else
        "#{@expression}\n#{suffix}"
      end
    end
  end

  class JavaScriptFunction
    include Puppeteer::IfPresent

    def initialize(execution_context, expression, args, return_by_value)
      @execution_context = execution_context
      @expression = expression
      @return_by_value = return_by_value
      @args = args
    end

    # @param client [Puppeteer::CDPSession]
    # @param context_id [String]
    # @return [Object|JSHandle]
    def evaluate_with(client:, context_id:)
      # `function` can be omitted in JS after ES2015.
      # https://developer.mozilla.org/ja/docs/Web/JavaScript/Reference/Operators/Object_initializer
      #
      # Original puppeteer implementation take it into consideration.
      # But we don't support the syntax here.

      result = client.send_message('Runtime.callFunctionOn',
        functionDeclaration: function_declaration,
        executionContextId: context_id,
        arguments: converted_args,
        returnByValue: @return_by_value,
        awaitPromise: true,
        userGesture: true,
      ) # .catch(rewriteError);

      exception_details = result['exceptionDetails']
      if exception_details
        raise EvaluationError.new("Evaluation failed: #{exception_details}")
      end

      remote_object = Puppeteer::RemoteObject.new(result['result'])

      if @return_by_value
        remote_object.value
      else
        Puppeteer::JSHandle.create(
          context: @execution_context,
          remote_object: remote_object,
        )
      end
    end

    private def converted_args
      #     if (typeof arg === 'bigint') // eslint-disable-line valid-typeof
      #       return { unserializableValue: `${arg.toString()}n` };
      #     if (Object.is(arg, -0))
      #       return { unserializableValue: '-0' };
      #     if (Object.is(arg, Infinity))
      #       return { unserializableValue: 'Infinity' };
      #     if (Object.is(arg, -Infinity))
      #       return { unserializableValue: '-Infinity' };
      #     if (Object.is(arg, NaN))
      #       return { unserializableValue: 'NaN' };
      @args.map do |arg|
        if arg && arg.is_a?(Puppeteer::JSHandle)
          if arg.context != @execution_context
            raise EvaluationError.new('JSHandles can be evaluated only in the context they were created!')
          elsif arg.disposed?
            raise EvaluationError.new('JSHandles is disposed!')
          end

          arg.remote_object.converted_arg
        elsif arg.is_a?(Regexp)
          { value: arg.source }
        else
          { value: arg }
        end
      end
    end

    # @rbs return: String -- JavaScript function declaration
    private def function_declaration
      expression = @return_by_value ? serialized_function_declaration : @expression
      "#{expression}\n#{suffix}\n"
    end

    # @rbs return: String -- Wrapped function with serialization
    private def serialized_function_declaration
      <<~JAVASCRIPT
      async function(...__args) {
        const fn = #{@expression};
        const result = await fn.apply(globalThis, __args);
        #{serialized_value_source}
      }
      JAVASCRIPT
    end

    # @rbs return: String -- JavaScript serialization helper source
    private def serialized_value_source
      <<~JAVASCRIPT
      const OMIT = Symbol('omit');
      const UNDEFINED_SENTINEL = { __puppeteer_unserializable__: true };
      const NUMBER_SENTINEL = (value) => ({ __puppeteer_number__: value });
      const REGEXP_SENTINEL = (source, flags) => ({ __puppeteer_regexp__: { source, flags } });
      const seen = new WeakSet();
      const isPlainObject = (value) => {
        if (!value || typeof value !== 'object') {
          return false;
        }
        const proto = Object.getPrototypeOf(value);
        return proto === Object.prototype || proto === null;
      };
      const serialize = (value, allowOmit) => {
        if (value === undefined) {
          return allowOmit ? OMIT : UNDEFINED_SENTINEL;
        }
        if (typeof value === 'symbol' || typeof value === 'function') {
          return UNDEFINED_SENTINEL;
        }
        if (typeof value === 'number') {
          if (Number.isNaN(value)) {
            return NUMBER_SENTINEL('NaN');
          }
          if (Object.is(value, -0)) {
            return NUMBER_SENTINEL('-0');
          }
          if (value === Infinity) {
            return NUMBER_SENTINEL('Infinity');
          }
          if (value === -Infinity) {
            return NUMBER_SENTINEL('-Infinity');
          }
        }
        if (typeof value === 'bigint') {
          return value;
        }
        if (value === null || typeof value !== 'object') {
          return value;
        }
        if (typeof Window !== 'undefined' && value === window) {
          return UNDEFINED_SENTINEL;
        }
        if (typeof ImageBitmap !== 'undefined' && value instanceof ImageBitmap) {
          return UNDEFINED_SENTINEL;
        }
        if (value instanceof RegExp) {
          return REGEXP_SENTINEL(value.source, value.flags || '');
        }
        if (value instanceof Promise) {
          return {};
        }
        if (seen.has(value)) {
          return UNDEFINED_SENTINEL;
        }
        seen.add(value);
        if (Array.isArray(value)) {
          return value.map((item) => {
            const serialized = serialize(item, false);
            return serialized === OMIT ? UNDEFINED_SENTINEL : serialized;
          });
        }
        if (!isPlainObject(value)) {
          return UNDEFINED_SENTINEL;
        }
        const result = {};
        for (const [key, val] of Object.entries(value)) {
          const serialized = serialize(val, true);
          if (serialized === OMIT) {
            continue;
          }
          result[key] = serialized;
        }
        return result;
      };
      return serialize(result, false);
      JAVASCRIPT
    end

    #   /**
    #    * @param {!Error} error
    #    * @return {!Protocol.Runtime.evaluateReturnValue}
    #    */
    #   function rewriteError(error) {
    #     if (error.message.includes('Object reference chain is too long'))
    #       return {result: {type: 'undefined'}};
    #     if (error.message.includes('Object couldn\'t be returned by value'))
    #       return {result: {type: 'undefined'}};

    #     if (error.message.endsWith('Cannot find context with specified id') || error.message.endsWith('Inspected target navigated or closed'))
    #       throw new Error('Execution context was destroyed, most likely because of a navigation.');
    #     throw error;
    #   }

    private def suffix
      "//# sourceURL=#{EVALUATION_SCRIPT_URL}"
    end
  end

  class EvaluationError < Puppeteer::Error; end

  # @param return_by_value [Boolean]
  # @param page_function [String]
  # @return [Object|Puppeteer::JSHandle]
  private def evaluate_internal(return_by_value, page_function, *args)
    # `function` can be omitted in JS after ES2015.
    # https://developer.mozilla.org/ja/docs/Web/JavaScript/Reference/Operators/Object_initializer
    # But we don't support the syntax here.
    js_object =
      if ['=>', 'async', 'function'].any? { |keyword| page_function.include?(keyword) }
        JavaScriptFunction.new(self, page_function, args, return_by_value)
      else
        JavaScriptExpression.new(self, page_function, return_by_value)
      end

    js_object.evaluate_with(
      client: @client,
      context_id: @context_id,
    )
  end
end
