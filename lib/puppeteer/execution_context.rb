class Puppeteer::ExecutionContext
  include Puppeteer::IfPresent
  using Puppeteer::AsyncAwaitBehavior

  EVALUATION_SCRIPT_URL = '__puppeteer_evaluation_script__'
  SOURCE_URL_REGEX = /^[\040\t]*\/\/[@#] sourceURL=\s*(\S*?)\s*$/m

  # @param client [Puppeteer::CDPSession]
  # @param context_payload [Hash]
  # @param world [Puppeteer::DOMWorld?]
  def initialize(client, context_payload, world)
    @client = client
    @world = world
    @context_id = context_payload['id']
  end

  attr_reader :client, :world

  # @return [Puppeteer::Frame]
  def frame
    if_present(@world) do |world|
      world.frame
    end
  end

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<*>}
  def evaluate(page_function, *args)
    evaluate_internal(true, page_function, *args)
  end


  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<!Puppeteer.JSHandle>}
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
    def evaluate_with(client:, context_id:)
      result = await client.send_message('Runtime.evaluate',
        expression: expression_with_source_url,
        contextId: context_id,
        returnByValue: @return_by_value,
        awaitPromise: true,
        userGesture: true,
      )
      # }).catch(rewriteError);

      exception_details = result["exceptionDetails"]
      remote_object = result['result']

      if exception_details
        raise EvaluationError.new("Evaluation failed: #{exception_details}")
      end

      if @return_by_value
        remote_object
      else
        Puppeteer::JSHandle.create(
          context: @execution_context,
          remote_object: Puppeteer::RemoteObject.new(remote_object),
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

    def evaluate_with(client:, context_id:)
      # `function` can be omitted in JS after ES2015.
      # https://developer.mozilla.org/ja/docs/Web/JavaScript/Reference/Operators/Object_initializer
      #
      # Original puppeteer implementation take it into consideration.
      # But we don't support the syntax here.

      result = await client.send_message('Runtime.callFunctionOn',
        functionDeclaration: "#{@expression}\n#{suffix}\n",
        executionContextId: context_id,
        arguments: converted_args,
        returnByValue: @return_by_value,
        awaitPromise: true,
        userGesture: true,
      ) #.catch(rewriteError);

      exception_details = result["exceptionDetails"]
      remote_object = result["result"]

      if exception_details
        raise EvaluationError.new("Evaluation failed: #{exceptionDetails}")
      end

      if @return_by_value
        remote_object
      else
        Puppeteer::JSHandle.create(
          context: @execution_context,
          remote_object: Puppeteer::RemoteObject.new(remote_object),
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
        else
          { value: arg }
        end
      end
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

  class EvaluationError < StandardError ; end

  # @param {boolean} returnByValue
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<!Puppeteer.JSHandle>}
  private def evaluate_internal(return_by_value, page_function, *args)
    # `function` can be omitted in JS after ES2015.
    # https://developer.mozilla.org/ja/docs/Web/JavaScript/Reference/Operators/Object_initializer
    # But we don't support the syntax here.
    js_object =
      if ["=>", "async", "function"].any? { |keyword| page_function.include?(keyword) }
        JavaScriptFunction.new(self, page_function, args, return_by_value)
      else
        JavaScriptExpression.new(self, page_function, return_by_value)
      end

    js_object.evaluate_with(
      client: @client,
      context_id: @context_id,
    )
  end

  # /**
  #  * @param {!JSHandle} prototypeHandle
  #  * @return {!Promise<!JSHandle>}
  #  */
  # async queryObjects(prototypeHandle) {
  #   assert(!prototypeHandle._disposed, 'Prototype JSHandle is disposed!');
  #   assert(prototypeHandle._remoteObject.objectId, 'Prototype JSHandle must not be referencing primitive value');
  #   const response = await this._client.send('Runtime.queryObjects', {
  #     prototypeObjectId: prototypeHandle._remoteObject.objectId
  #   });
  #   return createJSHandle(this, response.objects);
  # }

  # /**
  #  * @param {Puppeteer.ElementHandle} elementHandle
  #  * @return {Promise<Puppeteer.ElementHandle>}
  #  */
  # async _adoptElementHandle(elementHandle) {
  #   assert(elementHandle.executionContext() !== this, 'Cannot adopt handle that already belongs to this execution context');
  #   assert(this._world, 'Cannot adopt handle without DOMWorld');
  #   const nodeInfo = await this._client.send('DOM.describeNode', {
  #     objectId: elementHandle._remoteObject.objectId,
  #   });
  #   const {object} = await this._client.send('DOM.resolveNode', {
  #     backendNodeId: nodeInfo.node.backendNodeId,
  #     executionContextId: this._contextId,
  #   });
  #   return /** @type {Puppeteer.ElementHandle}*/(createJSHandle(this, object));
  # }
end
