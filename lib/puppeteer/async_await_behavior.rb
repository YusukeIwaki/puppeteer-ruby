module Puppeteer::AsyncAwaitBehavior
  refine Class do
    def define_async_method_for(method_name)
      original_method = instance_method(method_name)
      async_method_name = "async_#{method_name}"

      if method_defined?(async_method_name) || private_method_defined?(async_method_name)
        raise ArgumentError.new("#{async_method_name} is already defined")
      end

      define_method(async_method_name) do |*args|
        Concurrent::Promises.future do
          original_method.bind(self).call(*args)
        rescue => err
          Logger.new(STDERR).warn(err)
          raise err
        end
      end
    end

    # wrap with Concurrent::Promises.future
    def async(method_name)
      original_method = instance_method(method_name)

      unless method_name.to_s.start_with?('async_')
        puts "async method should start with 'async_': #{self.name}##{method_name}"
      end

      define_method(method_name) do |*args|
        Concurrent::Promises.future do
          original_method.bind(self).call(*args)
        rescue => err
          Logger.new(STDERR).warn(err)
          raise err
        end
      end
    rescue NameError
      if respond_to?(method_name)
        original_method = singleton_method(method_name)

        unless method_name.to_s.start_with?('async_')
          puts "async method should start with 'async_': #{method_name}"
        end

        define_singleton_method(method_name) do |*args|
          Concurrent::Promises.future do
            original_method.call(*args)
          rescue => err
            Logger.new(STDERR).warn(err)
            raise err
          end
        end
      end
    end
  end
end
