module Puppeteer::AsyncAwaitBehavior
  refine Class do
    # wrap with Concurrent::Promises.future
    def async(method_name)
      if respond_to?(method_name)
        original_method = singleton_method(method_name)

        define_singleton_method(method_name) do |*args|
          Concurrent::Promises.future {
            original_method.call(*args)
          }
        end
      else
        original_method = instance_method(method_name)

        define_method(method_name) do |*args|
          Concurrent::Promises.future {
            original_method.bind(self).call(*args)
          }
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
