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
        # -> await_all(
        #      async_wait_for_xxx(xx, yy),
        #      future { block.call },
        #    ).first
        define_method(original_method_name) do |*args, **kwargs, &block|
          if block
            async_method_call =
              if kwargs.empty? # for Ruby 2.6
                Concurrent::Promises.future do
                  original_method.bind(self).call(*args)
                rescue => err
                  Logger.new($stderr).warn(err)
                  raise err
                end
              else
                Concurrent::Promises.future do
                  original_method.bind(self).call(*args, **kwargs)
                rescue => err
                  Logger.new($stderr).warn(err)
                  raise err
                end
              end

            async_block_call = Concurrent::Promises.future do
              block.call
            rescue => err
              Logger.new($stderr).warn(err)
              raise err
            end

            Concurrent::Promises.zip(
              async_method_call,
              async_block_call,
            ).value!.first
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
        if kwargs.empty? # for Ruby 2.6
          Concurrent::Promises.future do
            original_method.bind(self).call(*args)
          rescue => err
            Logger.new($stderr).warn(err)
            raise err
          end.extend(Puppeteer::ConcurrentRubyUtils::ConcurrentPromisesFutureExtension)
        else
          Concurrent::Promises.future do
            original_method.bind(self).call(*args, **kwargs)
          rescue => err
            Logger.new($stderr).warn(err)
            raise err
          end.extend(Puppeteer::ConcurrentRubyUtils::ConcurrentPromisesFutureExtension)
        end
      end
    end
  end
end
