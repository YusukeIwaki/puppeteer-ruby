class Puppeteer::ExecutionContext
  include Puppeteer::IfPresent

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

  attr_reader :world

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

  class EvaluationError < StandardError ; end

  # @param {boolean} returnByValue
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<!Puppeteer.JSHandle>}
  private def evaluate_internal(return_by_value, page_function, *args)
    suffix = "//# sourceURL=#{EVALUATION_SCRIPT_URL}"
    if page_function.is_a?(String)
      context_id = @context_id
      expression = page_function
      expression_with_source_url =
        if SOURCE_URL_REGEX.match?(expression)
          expression
        else
          "#{expression}\n#{suffix}"
        end
      result = @client.send_message('Runtime.evaluate',
                 expression: expression_with_source_url,
                 contextId: context_id,
                 returnByValue: return_by_value,
                 awaitPromise: true,
                 userGesture: true)
      # }).catch(rewriteError);
      if result['exceptionDetails']
        raise EvaluationError.new("Evaluation failed: #{result['exceptionDetails']}")
      end

      remote_object = result['result']

      if return_by_value
        return remote_object
      else
        return create_js_handle(self, remote_object)
      end
    end

  #   if (typeof pageFunction !== 'function')
  #     throw new Error(`Expected to get |string| or |function| as the first argument, but got "${pageFunction}" instead.`);

  #   let functionText = pageFunction.toString();
  #   try {
  #     new Function('(' + functionText + ')');
  #   } catch (e1) {
  #     // This means we might have a function shorthand. Try another
  #     // time prefixing 'function '.
  #     if (functionText.startsWith('async '))
  #       functionText = 'async function ' + functionText.substring('async '.length);
  #     else
  #       functionText = 'function ' + functionText;
  #     try {
  #       new Function('(' + functionText  + ')');
  #     } catch (e2) {
  #       // We tried hard to serialize, but there's a weird beast here.
  #       throw new Error('Passed function is not well-serializable!');
  #     }
  #   }
  #   let callFunctionOnPromise;
  #   try {
  #     callFunctionOnPromise = this._client.send('Runtime.callFunctionOn', {
  #       functionDeclaration: functionText + '\n' + suffix + '\n',
  #       executionContextId: this._contextId,
  #       arguments: args.map(convertArgument.bind(this)),
  #       returnByValue,
  #       awaitPromise: true,
  #       userGesture: true
  #     });
  #   } catch (err) {
  #     if (err instanceof TypeError && err.message.startsWith('Converting circular structure to JSON'))
  #       err.message += ' Are you passing a nested JSHandle?';
  #     throw err;
  #   }
  #   const { exceptionDetails, result: remoteObject } = await callFunctionOnPromise.catch(rewriteError);
  #   if (exceptionDetails)
  #     throw new Error('Evaluation failed: ' + helper.getExceptionMessage(exceptionDetails));
  #   return returnByValue ? helper.valueFromRemoteObject(remoteObject) : createJSHandle(this, remoteObject);

  #   /**
  #    * @param {*} arg
  #    * @return {*}
  #    * @this {ExecutionContext}
  #    */
  #   function convertArgument(arg) {
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
  #     const objectHandle = arg && (arg instanceof JSHandle) ? arg : null;
  #     if (objectHandle) {
  #       if (objectHandle._context !== this)
  #         throw new Error('JSHandles can be evaluated only in the context they were created!');
  #       if (objectHandle._disposed)
  #         throw new Error('JSHandle is disposed!');
  #       if (objectHandle._remoteObject.unserializableValue)
  #         return { unserializableValue: objectHandle._remoteObject.unserializableValue };
  #       if (!objectHandle._remoteObject.objectId)
  #         return { value: objectHandle._remoteObject.value };
  #       return { objectId: objectHandle._remoteObject.objectId };
  #     }
  #     return { value: arg };
  #   }

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
