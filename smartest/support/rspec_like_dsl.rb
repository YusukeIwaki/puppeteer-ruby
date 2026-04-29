# frozen_string_literal: true

module SmartestRSpecLikeDSL
  class << self
    attr_accessor :root

    def run(context, group, metadata, body, browser:, server:, https_server:)
      context.__send__(:__rspec_like_prepare, group, browser: browser, server: server, https_server: https_server)
      context.__send__(:__rspec_like_run, group, metadata, body)
    end
  end

  class Group
    attr_reader :parent, :description, :metadata, :helper_module, :before_each_hooks,
                :after_each_hooks, :before_all_hooks, :after_all_hooks

    def initialize(parent:, description:, metadata: {})
      @parent = parent
      @description = description
      @metadata = metadata.dup
      @helper_module = Module.new
      @before_each_hooks = []
      @after_each_hooks = []
      @before_all_hooks = []
      @after_all_hooks = []
      @shared_examples = {}
      @example_count = 0
      @remaining_examples = 0
      @before_all_ran = false
      @after_all_ran = false
      install_dsl
    end

    def root?
      parent.nil?
    end

    def describe(description = nil, **metadata, &block)
      child = Group.new(parent: self, description: description, metadata: metadata)
      child.evaluate(&block) if block
      child
    end
    alias context describe

    def evaluate(&block)
      helper_module.module_eval(&block)
    end

    def include_context(name, *args)
      raise ArgumentError, "unsupported include_context args: #{args.inspect}" unless args.empty?

      metadata[:auto_test_state] = true if name == 'with test state'
    end

    def before(scope = :each, &block)
      raise ArgumentError, 'before block is required' unless block

      case normalize_scope(scope)
      when :each
        before_each_hooks << block
      when :all
        before_all_hooks << block
      else
        raise ArgumentError, "unsupported before scope: #{scope.inspect}"
      end
    end

    def after(scope = :each, &block)
      raise ArgumentError, 'after block is required' unless block

      case normalize_scope(scope)
      when :each
        after_each_hooks << block
      when :all
        after_all_hooks << block
      else
        raise ArgumentError, "unsupported after scope: #{scope.inspect}"
      end
    end

    def let(name, &block)
      raise ArgumentError, 'let block is required' unless block

      helper_module.define_method(name) do
        __rspec_like_fetch_let__(name, &block)
      end
    end

    def subject(name = nil, &block)
      block ||= proc { described_class&.new }
      let(:subject, &block)
      let(name, &block) if name
    end

    def shared_examples(name, &block)
      raise ArgumentError, 'shared_examples block is required' unless block

      @shared_examples[name] = block
    end

    def it_behaves_like(name, *args, **kwargs, &customization)
      block = lookup_shared_examples(name)
      raise ArgumentError, "shared examples not found: #{name}" unless block

      helper_module.module_exec(*args, **kwargs, &block)
      helper_module.module_eval(&customization) if customization
    end
    alias include_examples it_behaves_like

    def it(name = nil, __smartest_location: nil, **metadata, &block)
      raise ArgumentError, 'it block is required' unless block

      location = __smartest_location || caller_locations(1, 1).first
      full_metadata = merged_metadata(metadata)
      test_name = full_name(name || 'is expected')
      register_example_for_ancestors
      current_group = self

      Smartest.suite.tests.add(
        Smartest::TestCase.new(
          name: test_name,
          metadata: full_metadata,
          block: proc do |browser:, server:, https_server:|
            SmartestRSpecLikeDSL.run(
              self,
              current_group,
              full_metadata,
              block,
              browser: browser,
              server: server,
              https_server: https_server,
            )
          end,
          location: location,
          around_test_hooks: Smartest.suite.around_test_hooks_for(location),
        ),
      )
    end

    def described_class
      ancestors.reverse_each do |group|
        description = group.description
        return description if description.is_a?(Module)
      end
      nil
    end

    def ancestors
      parent ? parent.ancestors + [self] : [self]
    end

    def full_name(example_name = nil)
      parts = ancestors.reject(&:root?).map(&:description).compact.map(&:to_s)
      parts << example_name.to_s if example_name
      parts.join(' ')
    end

    def merged_metadata(extra = {})
      ancestors.each_with_object({}) { |group, hash| hash.merge!(group.metadata) }.merge(extra)
    end

    def before_all_ran?
      @before_all_ran
    end

    def mark_before_all_ran
      @before_all_ran = true
    end

    def decrement_remaining_examples
      @remaining_examples -= 1 if @remaining_examples.positive?
    end

    def complete?
      @remaining_examples.zero?
    end

    def after_all_ran?
      @after_all_ran
    end

    def mark_after_all_ran
      @after_all_ran = true
    end

    private

    def install_dsl
      group = self
      helper_module.define_singleton_method(:describe) { |description = nil, **metadata, &block| group.describe(description, **metadata, &block) }
      helper_module.define_singleton_method(:context) { |description = nil, **metadata, &block| group.context(description, **metadata, &block) }
      helper_module.define_singleton_method(:it) do |name = nil, **metadata, &block|
        group.it(name, __smartest_location: caller_locations(1, 1).first, **metadata, &block)
      end
      helper_module.define_singleton_method(:before) { |scope = :each, &block| group.before(scope, &block) }
      helper_module.define_singleton_method(:after) { |scope = :each, &block| group.after(scope, &block) }
      helper_module.define_singleton_method(:let) { |name, &block| group.let(name, &block) }
      helper_module.define_singleton_method(:subject) { |name = nil, &block| group.subject(name, &block) }
      helper_module.define_singleton_method(:shared_examples) { |name, &block| group.shared_examples(name, &block) }
      helper_module.define_singleton_method(:it_behaves_like) { |name, *args, **kwargs, &block| group.it_behaves_like(name, *args, **kwargs, &block) }
      helper_module.define_singleton_method(:include_examples) { |name, *args, **kwargs, &block| group.include_examples(name, *args, **kwargs, &block) }
      helper_module.define_singleton_method(:include_context) { |name, *args| group.include_context(name, *args) }
      helper_module.define_singleton_method(:described_class) { group.described_class }
    end

    def lookup_shared_examples(name)
      return @shared_examples[name] if @shared_examples.key?(name)

      parent&.send(:lookup_shared_examples, name)
    end

    def normalize_scope(scope)
      case scope
      when :each, nil
        :each
      when :all, :context
        :all
      else
        scope
      end
    end

    def register_example_for_ancestors
      ancestors.each do |group|
        group.instance_variable_set(:@example_count, group.instance_variable_get(:@example_count) + 1)
        group.instance_variable_set(:@remaining_examples, group.instance_variable_get(:@remaining_examples) + 1)
      end
    end
  end

  module ExecutionHelpers
    def __rspec_like_prepare(group, browser:, server:, https_server:)
      @__rspec_like_group = group
      @__rspec_like_let_cache = {}
      @__rspec_like_cleanups = []
      @__rspec_like_browser = browser&.connected? ? browser : BrowserFixture.ensure_browser!
      @__rspec_like_server = server
      @__rspec_like_https_server = https_server

      group.ancestors.each do |ancestor|
        singleton_class.include(ancestor.helper_module)
      end
    end

    def __rspec_like_run(group, metadata, body)
      original_debug = ENV['DEBUG']
      ENV['DEBUG'] = '1' if metadata[:debug_cdp]
      start_ws_http2_server if metadata[:ws_http2]

      begin
        apply_metadata_state(metadata)
        run_body = proc { __rspec_like_run_body(group, body) }
        if auto_test_state?(group, metadata)
          with_metadata_test_state(metadata, &run_body)
        else
          __rspec_like_set_state(
            page: nil,
            server: @__rspec_like_server,
            https_server: @__rspec_like_https_server,
            browser: @__rspec_like_browser,
            context: @__rspec_like_browser.default_browser_context,
            &run_body
          )
        end
      ensure
        run_registered_cleanups
        stop_ws_http2_server if metadata[:ws_http2]
        restore_debug_env(original_debug)
        decrement_group_counters(group)
      end
    end

    def __rspec_like_fetch_let__(name)
      @__rspec_like_let_cache ||= {}
      return @__rspec_like_let_cache[name] if @__rspec_like_let_cache.key?(name)

      @__rspec_like_let_cache[name] = yield
    end

    def is_expected
      expect(subject)
    end

    def described_class
      @__rspec_like_group&.described_class
    end

    def page
      @page or raise NoMethodError.new('undefined method "page"')
    end

    def browser
      @browser || BrowserFixture.ensure_browser! || @__rspec_like_browser or raise NoMethodError.new('undefined method "browser"')
    end

    def browser_context
      @browser_context || @context or raise NoMethodError.new('undefined method "browser_context"')
    end

    def context
      @context or raise NoMethodError.new('undefined method "context"')
    end

    def server
      @server || @__rspec_like_server
    end

    def https_server
      @https_server || @__rspec_like_https_server
    end

    def sinatra
      TestServerSinatraAdapter.new(server)
    end

    def server_prefix
      server&.prefix
    end

    def server_cross_process_prefix
      server&.cross_process_prefix
    end

    def server_empty_page
      server&.empty_page
    end

    def server_port
      server&.port
    end

    def expect_any_instance_of(klass)
      AnyInstanceTarget.new(klass, self)
    end

    def aggregate_failures(*)
      yield
    end

    def receive(method_name)
      ReceiveMatcher.new(method_name)
    end

    def hash_including(expected)
      HashIncludingMatcher.new(expected)
    end

    def __rspec_like_register_cleanup(&block)
      @__rspec_like_cleanups << block
    end

    private

    def apply_metadata_state(metadata)
      skip(metadata[:skip].is_a?(String) ? metadata[:skip] : nil) if metadata[:skip]
      pending(metadata[:pending].is_a?(String) ? metadata[:pending] : 'pending') if metadata[:pending]
    end

    def auto_test_state?(group, metadata)
      metadata[:auto_test_state] || metadata.key?(:puppeteer) || metadata.key?(:browser_context) || metadata[:enable_site_per_process_flag]
    end

    def with_metadata_test_state(metadata, &block)
      create_page = metadata[:puppeteer].to_s != 'browser'
      incognito =
        case metadata[:browser_context].to_s
        when 'incognito'
          true
        when 'default'
          false
        else
          nil
        end

      run_example = proc do |page:, server:, https_server:, browser:, context:|
        __rspec_like_set_state(page: page, server: server, https_server: https_server, browser: browser, context: context, &block)
      end

      if metadata[:enable_site_per_process_flag]
        args = (default_launch_options[:args] || []) + [
          '--site-per-process',
          '--host-rules=MAP * 127.0.0.1',
        ]
        Puppeteer.launch(**default_launch_options.merge(args: args)) do |isolated_browser|
          with_test_state(
            incognito: incognito,
            create_page: create_page,
            browser: isolated_browser,
            &run_example
          )
        end
      else
        with_test_state(
          incognito: incognito,
          create_page: create_page,
          &run_example
        )
      end
    end

    def __rspec_like_set_state(page:, server:, https_server:, browser:, context:)
      @page = page
      @server = server
      @https_server = https_server
      @browser = browser
      @context = context
      @browser_context = context
      yield
    ensure
      @page = nil
      @server = nil
      @https_server = nil
      @browser = nil
      @context = nil
      @browser_context = nil
    end

    def __rspec_like_run_body(group, body)
      groups = group.ancestors.reject(&:root?)
      groups.each do |current_group|
        next if current_group.before_all_ran?

        current_group.mark_before_all_ran
        current_group.before_all_hooks.each { |hook| instance_exec(&hook) }
      end

      begin
        groups.each { |current_group| current_group.before_each_hooks.each { |hook| instance_exec(&hook) } }
        instance_exec(&body)
      ensure
        groups.reverse_each { |current_group| current_group.after_each_hooks.reverse_each { |hook| instance_exec(&hook) } }
      end
    end

    def decrement_group_counters(group)
      group.ancestors.reverse_each do |current_group|
        current_group.decrement_remaining_examples
        next unless current_group.complete?
        next if current_group.after_all_ran?

        current_group.mark_after_all_ran
        current_group.after_all_hooks.reverse_each { |hook| instance_exec(&hook) }
      end
    end

    def start_ws_http2_server
      $ws_http2_test_server ||= TestServer::WebSocketHTTP2Server.new
      $ws_http2_test_server.start
    end

    def stop_ws_http2_server
      $ws_http2_test_server&.stop
      $ws_http2_test_server = nil
    end

    def restore_debug_env(original_debug)
      if original_debug.nil?
        ENV.delete('DEBUG')
      else
        ENV['DEBUG'] = original_debug
      end
    end

    def run_registered_cleanups
      cleanups = @__rspec_like_cleanups || []
      errors = []
      cleanups.reverse_each do |cleanup|
        cleanup.call
      rescue StandardError => error
        errors << error
      end
      raise errors.first if errors.any?
    ensure
      @__rspec_like_cleanups = []
    end
  end

  class AnyInstanceTarget
    def initialize(klass, context)
      @klass = klass
      @context = context
    end

    def to(matcher)
      matcher.install(@klass)
      @context.__send__(:__rspec_like_register_cleanup) do
        begin
          matcher.verify!
        ensure
          matcher.restore!
        end
      end
    end
  end

  class ReceiveMatcher
    def initialize(method_name)
      @method_name = method_name
      @expected_arguments = nil
      @calls = []
    end

    def with(*expected_arguments)
      @expected_arguments = expected_arguments
      self
    end

    def install(klass)
      @klass = klass
      @original = klass.instance_method(@method_name)
      matcher = self
      method_name = @method_name
      original = @original
      klass.define_method(method_name) do |*args, **kwargs, &block|
        matcher.record(args, kwargs)
        if kwargs.empty?
          original.bind_call(self, *args, &block)
        else
          original.bind_call(self, *args, **kwargs, &block)
        end
      end
    end

    def record(args, kwargs)
      actual = kwargs.empty? ? args : args + [kwargs]
      @calls << actual
    end

    def verify!
      return if @expected_arguments.nil? && @calls.any?
      return if @calls.any? { |actual| arguments_match?(@expected_arguments, actual) }

      raise Smartest::AssertionFailed, "expected any instance of #{@klass} to receive #{@method_name} with #{expected_description}"
    end

    def restore!
      @klass.define_method(@method_name, @original) if @klass && @original
    end

    private

    def arguments_match?(expected, actual)
      expected.length == actual.length && expected.zip(actual).all? do |expected_value, actual_value|
        if expected_value.respond_to?(:matches?)
          expected_value.matches?(actual_value)
        else
          expected_value == actual_value
        end
      end
    end

    def expected_description
      @expected_arguments&.map(&:inspect)&.join(', ') || 'any arguments'
    end
  end

  class HashIncludingMatcher < Smartest::Matcher
    def initialize(expected)
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      return false unless actual.respond_to?(:key?)

      @expected.all? do |key, expected_value|
        actual.key?(key) && value_matches?(expected_value, actual[key])
      end
    end

    def failure_message
      "expected #{@actual.inspect} to include hash #{@expected.inspect}"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to include hash #{@expected.inspect}"
    end

    def description
      "hash including #{@expected.inspect}"
    end

    private

    def value_matches?(expected_value, actual_value)
      if expected_value.respond_to?(:matches?)
        expected_value.matches?(actual_value)
      else
        expected_value == actual_value
      end
    end
  end
end

SmartestRSpecLikeDSL.root = SmartestRSpecLikeDSL::Group.new(parent: nil, description: nil)

module Kernel
  private

  def describe(description = nil, **metadata, &block)
    SmartestRSpecLikeDSL.root.describe(description, **metadata, &block)
  end
  alias context describe
end
