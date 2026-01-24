# rbs_inline: enabled

module Puppeteer
  module PSelectorParser
    class PseudoSelector
      attr_reader :name, :value

      def initialize(name:, value:)
        @name = name
        @value = value
      end
    end

    PSEUDO_PREFIX = '::-p-'

    # @rbs selector: String -- Selector to parse
    # @rbs return: [Array[untyped], bool, bool, bool] -- Parsed selectors and flags
    def self.parse(selector)
      is_pure_css = true
      has_pseudo_classes = false
      has_aria = false

      selectors = []
      compound = []
      complex = [compound]
      storage = +''

      i = 0
      length = selector.length
      in_quote = nil
      escaped = false
      paren_depth = 0

      while i < length
        char = selector[i]

        if escaped
          storage << char
          escaped = false
          i += 1
          next
        end

        if char == '\\'
          storage << char
          escaped = true
          i += 1
          next
        end

        if in_quote
          if char == in_quote
            in_quote = nil
          end
          storage << char
          i += 1
          next
        end

        if char == '"' || char == "'"
          in_quote = char
          storage << char
          i += 1
          next
        end

        if char == '('
          paren_depth += 1
          storage << char
          i += 1
          next
        end

        if char == ')'
          paren_depth = [paren_depth - 1, 0].max
          storage << char
          i += 1
          next
        end

        if paren_depth == 0
          if starts_with_at?(selector, i, '>>>>')
            flush_storage(storage, compound)
            complex << '>>>>'
            compound = []
            complex << compound
            is_pure_css = false
            i += 4
            next
          end

          if starts_with_at?(selector, i, '>>>')
            flush_storage(storage, compound)
            complex << '>>>'
            compound = []
            complex << compound
            is_pure_css = false
            i += 3
            next
          end

          if starts_with_at?(selector, i, PSEUDO_PREFIX)
            flush_storage(storage, compound)
            i += PSEUDO_PREFIX.length
            name, i = parse_name(selector, i)
            raise ArgumentError.new('Invalid PSelector name') if name.empty?

            i = skip_spaces(selector, i)
            value = ''
            if selector[i] == '('
              value, i = parse_argument(selector, i)
            end
            value = unquote(value.strip)

            compound << PseudoSelector.new(name: name, value: value)
            is_pure_css = false
            has_aria = true if name == 'aria'
            next
          end

          if char == ','
            flush_storage(storage, compound)
            selectors << complex
            compound = []
            complex = [compound]
            i += 1
            next
          end

          if char == ':' && selector[i, PSEUDO_PREFIX.length] != PSEUDO_PREFIX
            if selector[i + 1] != ':'
              has_pseudo_classes = true
            end
          end
        end

        storage << char
        i += 1
      end

      raise ArgumentError.new('Unterminated string in PSelector') if in_quote
      raise ArgumentError.new('Unterminated parentheses in PSelector') if paren_depth != 0

      flush_storage(storage, compound)
      selectors << complex if complex.any?

      [selectors, is_pure_css, has_pseudo_classes, has_aria]
    end

    def self.flush_storage(storage, compound)
      css = storage.strip
      compound << css unless css.empty?
      storage.clear
    end
    private_class_method :flush_storage

    def self.parse_name(selector, index)
      name = +''
      while index < selector.length && selector[index] =~ /[A-Za-z0-9_-]/
        name << selector[index]
        index += 1
      end
      [name, index]
    end
    private_class_method :parse_name

    def self.skip_spaces(selector, index)
      index += 1 while index < selector.length && selector[index] =~ /\s/
      index
    end
    private_class_method :skip_spaces

    def self.parse_argument(selector, index)
      raise ArgumentError.new('Expected opening parenthesis') unless selector[index] == '('

      index += 1
      start = index
      depth = 1
      in_quote = nil
      escaped = false

      while index < selector.length
        char = selector[index]

        if escaped
          escaped = false
          index += 1
          next
        end

        if char == '\\'
          escaped = true
          index += 1
          next
        end

        if in_quote
          if char == in_quote
            in_quote = nil
          end
          index += 1
          next
        end

        if char == '"' || char == "'"
          in_quote = char
          index += 1
          next
        end

        if char == '('
          depth += 1
        elsif char == ')'
          depth -= 1
          if depth == 0
            value = selector[start...index]
            return [value, index + 1]
          end
        end

        index += 1
      end

      raise ArgumentError.new('Unterminated PSelector argument')
    end
    private_class_method :parse_argument

    def self.starts_with_at?(selector, index, token)
      selector[index, token.length] == token
    end
    private_class_method :starts_with_at?

    def self.unquote(text)
      if text.length > 1 && (text.start_with?('"') || text.start_with?("'")) && text.end_with?(text[0])
        text = text[1...-1]
      end
      text.gsub(/\\([\s\S])/m, '\\1')
    end
    private_class_method :unquote
  end
end
