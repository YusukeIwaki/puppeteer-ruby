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
        # -> start wait_for_xxx in a child task
        # -> run block (awaiting its result if needed)
        # -> wait for wait_for_xxx task, cancel on block errors
        define_method(original_method_name) do |*args, **kwargs, &block|
          if block
            runner = lambda do
              parent_task = Async::Task.current
              wait_task = parent_task.async do
                if kwargs.empty?
                  original_method.bind(self).call(*args)
                else
                  original_method.bind(self).call(*args, **kwargs)
                end
              end

              begin
                block_result = block.call
                Puppeteer::AsyncUtils.await(block_result)
              rescue Exception => err
                begin
                  wait_task.stop
                  Puppeteer::AsyncUtils.async_timeout(1000, -> { wait_task.wait }).wait
                rescue Exception
                  # Swallow cancellation errors/timeouts; original error takes priority.
                end
                raise err
              end

              wait_task.wait
            end

            if Async::Task.current?
              runner.call
            else
              Sync { runner.call }
            end
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
