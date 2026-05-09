# frozen_string_literal: true

module RSpecCompatMatchers
  UNSET = Object.new

  def be(expected = UNSET)
    return EqualMatcher.new(expected) unless expected.equal?(UNSET)

    BeComparatorBuilder.new
  end

  def be_truthy
    TruthyMatcher.new
  end

  def be_falsey
    FalseyMatcher.new
  end

  def be_empty
    EmptyMatcher.new
  end

  def all(matcher)
    AllMatcher.new(matcher)
  end

  def satisfy(&block)
    SatisfyMatcher.new(block)
  end

  def respond_to(method_name)
    RespondToMatcher.new(method_name)
  end

  def include(*expected)
    IncludeMatcher.new(expected)
  end

  def a_hash_including(expected)
    SmartestRSpecLikeDSL::HashIncludingMatcher.new(expected)
  end
  alias hash_including a_hash_including

  def a_string_including(expected)
    IncludeMatcher.new([expected])
  end

  def equal(expected)
    EqualMatcher.new(expected)
  end

  def raise_error(*expected_error)
    RaiseErrorMatcher.new(*expected_error)
  end

  class BeComparatorBuilder
    def >(expected)
      ComparisonMatcher.new(:>, expected)
    end

    def >=(expected)
      ComparisonMatcher.new(:>=, expected)
    end

    def <(expected)
      ComparisonMatcher.new(:<, expected)
    end

    def <=(expected)
      ComparisonMatcher.new(:<=, expected)
    end

    def ==(expected)
      EqualMatcher.new(expected)
    end
  end

  class ComparisonMatcher < Smartest::Matcher
    def initialize(operator, expected)
      @operator = operator
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      actual.public_send(@operator, @expected)
    rescue NoMethodError, ArgumentError
      false
    end

    def failure_message
      "expected #{@actual.inspect} to be #{@operator} #{@expected.inspect}"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be #{@operator} #{@expected.inspect}"
    end

    def description
      "be #{@operator} #{@expected.inspect}"
    end
  end

  class EqualMatcher < Smartest::Matcher
    def initialize(expected)
      @expected = expected
    end

    def matches?(actual)
      @actual = actual
      actual.equal?(@expected)
    end

    def failure_message
      "expected #{@actual.inspect} to be #{@expected.inspect}"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be #{@expected.inspect}"
    end
  end

  class TruthyMatcher < Smartest::Matcher
    def matches?(actual)
      @actual = actual
      !!actual
    end

    def failure_message
      "expected #{@actual.inspect} to be truthy"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be truthy"
    end
  end

  class FalseyMatcher < Smartest::Matcher
    def matches?(actual)
      @actual = actual
      !actual
    end

    def failure_message
      "expected #{@actual.inspect} to be falsey"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be falsey"
    end
  end

  class EmptyMatcher < Smartest::Matcher
    def matches?(actual)
      @actual = actual
      actual.respond_to?(:empty?) && actual.empty?
    end

    def failure_message
      "expected #{@actual.inspect} to be empty"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to be empty"
    end
  end

  class AllMatcher < Smartest::Matcher
    def initialize(matcher)
      @matcher = matcher
    end

    def matches?(actual)
      @actual = actual
      return false unless actual.respond_to?(:all?)

      actual.all? { |item| @matcher.matches?(item) }
    end

    def failure_message
      "expected all items in #{@actual.inspect} to match #{description}"
    end

    def negated_failure_message
      "expected not all items in #{@actual.inspect} to match #{description}"
    end

    def description
      @matcher.respond_to?(:description) ? @matcher.description : @matcher.inspect
    end
  end

  class SatisfyMatcher < Smartest::Matcher
    def initialize(block)
      raise ArgumentError, 'satisfy requires a block' unless block

      @block = block
    end

    def matches?(actual)
      @actual = actual
      !!@block.call(actual)
    end

    def failure_message
      "expected #{@actual.inspect} to satisfy block"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to satisfy block"
    end
  end

  class RespondToMatcher < Smartest::Matcher
    def initialize(method_name)
      @method_name = method_name
    end

    def matches?(actual)
      @actual = actual
      actual.respond_to?(@method_name)
    end

    def failure_message
      "expected #{@actual.inspect} to respond to #{@method_name}"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to respond to #{@method_name}"
    end
  end

  class IncludeMatcher < Smartest::Matcher
    def initialize(expected_items)
      @expected_items = expected_items
    end

    def matches?(actual)
      @actual = actual
      @expected_items.all? { |expected| includes_expected?(actual, expected) }
    end

    def failure_message
      "expected #{@actual.inspect} to include #{expected_description}"
    end

    def negated_failure_message
      "expected #{@actual.inspect} not to include #{expected_description}"
    end

    def description
      "include #{expected_description}"
    end

    private

    def includes_expected?(actual, expected)
      if actual.is_a?(Hash) && expected.is_a?(Hash)
        expected.all? { |key, value| actual.key?(key) && value_matches?(value, actual[key]) }
      elsif expected.respond_to?(:matches?) && actual.respond_to?(:any?)
        actual.any? { |item| expected.matches?(item) }
      elsif actual.respond_to?(:include?)
        actual.include?(expected)
      else
        false
      end
    end

    def value_matches?(expected, actual)
      expected.respond_to?(:matches?) ? expected.matches?(actual) : expected == actual
    end

    def expected_description
      @expected_items.map { |item| item.respond_to?(:description) ? item.description : item.inspect }.join(', ')
    end
  end

  class RaiseErrorMatcher < Smartest::Matcher
    def initialize(*expected_error)
      @expected_error = expected_error
      @actual_error = nil
      @callable = true
    end

    def matches?(actual)
      @actual_error = nil
      @callable = actual.respond_to?(:call)
      return false unless @callable

      actual.call
      false
    rescue Exception => error
      raise if Smartest.fatal_exception?(error)

      @actual_error = error
      expected_error_matches?(error)
    end

    def does_not_match?(actual)
      @actual_error = nil
      @callable = actual.respond_to?(:call)
      return false unless @callable

      actual.call
      true
    rescue Exception => error
      raise if Smartest.fatal_exception?(error)

      @actual_error = error
      false
    end

    def failure_message
      return "expected a block to raise #{expected_description}" unless @callable
      return "expected block to raise #{expected_description}, but nothing was raised" unless @actual_error

      "expected block to raise #{expected_description}, but raised #{@actual_error.class}: #{@actual_error.message}"
    end

    def negated_failure_message
      "expected block not to raise #{expected_description}, but raised #{@actual_error.class}: #{@actual_error.message}"
    end

    private

    def expected_error_matches?(error)
      return true if @expected_error.empty?

      expected_class = @expected_error.find { |item| item.is_a?(Class) && item <= Exception }
      expected_message = @expected_error.find { |item| item.is_a?(Regexp) || item.is_a?(String) }

      class_matches = expected_class.nil? || error.is_a?(expected_class)
      message_matches =
        case expected_message
        when nil
          true
        when Regexp
          expected_message.match?(error.message)
        else
          error.message == expected_message
        end

      class_matches && message_matches
    end

    def expected_description
      return 'an error' if @expected_error.empty?

      @expected_error.map(&:inspect).join(', ')
    end
  end
end
