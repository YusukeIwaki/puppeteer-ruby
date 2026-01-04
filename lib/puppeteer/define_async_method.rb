module Puppeteer::DefineAsyncMethod
  refine Class do
    def define_async_method(async_method_name)
      unless async_method_name.to_s.start_with?('async_')
        raise ArgumentError.new('async method name should start with "async_"')
      end

      if method_defined?(async_method_name) || private_method_defined?(async_method_name)
        raise ArgumentError.new("#{async_method_name} is already defined")
      end

      original_method_name = async_method_name[6..-1]
      original_method = instance_method(original_method_name)

      # - Modify only wait_for_xxx
      # - Do not modify private methods.
      if method_defined?(original_method_name) && original_method_name.start_with?('wait_for_')
        # def wait_for_xxx(xx, yy, &block)
        #
        # -> AsyncUtils.await_promise_all(
        #      -> { wait_for_xxx(xx, yy) },
        #      -> { block.call },
        #    ).first
        define_method(original_method_name) do |*args, **kwargs, &block|
          if block
            async_method_call = Puppeteer::AsyncUtils.future_with_logging do
              if kwargs.empty?
                original_method.bind(self).call(*args)
              else
                original_method.bind(self).call(*args, **kwargs)
              end
            end

            async_block_call = Puppeteer::AsyncUtils.future_with_logging do
              block.call
            end

            Puppeteer::AsyncUtils.await_promise_all(
              async_method_call,
              async_block_call,
            ).first
          else
            if kwargs.empty? # for Ruby 2.6
              original_method.bind(self).call(*args)
            else
              original_method.bind(self).call(*args, **kwargs)
            end
          end
        end
      end

      define_method(async_method_name) do |*args, **kwargs|
        Async do
          if kwargs.empty? # for Ruby 2.6
            original_method.bind(self).call(*args)
          else
            original_method.bind(self).call(*args, **kwargs)
          end
        end
      end
    end
  end
end
