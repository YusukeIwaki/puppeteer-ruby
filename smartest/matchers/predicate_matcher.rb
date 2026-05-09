# frozen_string_literal: true

module PredicateMatcher
  def method_missing(name, *arguments, &block)
    matcher_name = name.to_s
    return super unless matcher_name.match?(/\Abe_.+\z/)

    Matcher.new(matcher_name.delete_prefix('be_'), arguments, block)
  end

  def respond_to_missing?(name, include_private = false)
    name.to_s.match?(/\Abe_.+\z/) || super
  end

  class Matcher < Smartest::Matcher
    def initialize(predicate_name, arguments, block)
      super()
      @predicate_name = predicate_name
      @predicate = "#{predicate_name}?"
      @arguments = arguments
      @block = block
    end

    def matches?(actual)
      @actual = actual
      return false unless actual.respond_to?(@predicate)

      !!actual.public_send(@predicate, *@arguments, &@block)
    end

    def failure_message
      return "expected #{@actual.inspect} to respond to #{@predicate}" unless @actual.respond_to?(@predicate)

      "expected #{@actual.inspect} to be #{description}"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be #{description}"
    end

    def description
      return @predicate_name if @arguments.empty?

      "#{@predicate_name} #{argument_description}"
    end

    private

    def argument_description
      @arguments.map(&:inspect).join(', ')
    end
  end
end
