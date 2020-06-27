module Puppeteer::DefineAsyncMethod
  refine Class do
    def define_async_method(async_method_name)
      unless async_method_name.to_s.start_with?('async_')
        raise ArgumentError.new('async method name should start with "async_"')
      end

      if method_defined?(async_method_name) || private_method_defined?(async_method_name)
        raise ArgumentError.new("#{async_method_name} is already defined")
      end

      original_method = instance_method(async_method_name[6..-1])
      define_method(async_method_name) do |*args|
        Concurrent::Promises.future do
          original_method.bind(self).call(*args)
        rescue => err
          Logger.new(STDERR).warn(err)
          raise err
        end
      end
    end
  end
end
