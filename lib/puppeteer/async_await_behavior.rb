module Puppeteer::AsyncAwaitBehavior
  refine Class do
    # wrap with Concurrent::Promises.future
    def async(method_name)
      begin
        original_method = instance_method(method_name)

        unless method_name.to_s.start_with?("async_")
          puts "async method should start with 'async_': #{self.name}##{method_name}"
        end

        define_method(method_name) do |*args|
          Concurrent::Promises.future {
            original_method.bind(self).call(*args)
          }
        end
      rescue NameError
        if respond_to?(method_name)
          original_method = singleton_method(method_name)

          unless method_name.to_s.start_with?("async_")
            puts "async method should start with 'async_': #{method_name}"
          end

          define_singleton_method(method_name) do |*args|
            Concurrent::Promises.future {
              original_method.call(*args)
            }
          end
        end
      end
    end
  end

  refine Object do
    # blocking get value of Future.
    def await(future_or_value)
      if future_or_value.is_a?(Concurrent::Promises::Future)
        future_or_value.value!
      else
        future_or_value
      end
    end
  end
end
