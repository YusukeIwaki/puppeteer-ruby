require 'bundler/setup'

# fetch raw api.md text from github.com/puppeteer/puppeteer
class RawApiMdReader
  def initialize(git_tag)
    @url = "https://raw.githubusercontent.com/puppeteer/puppeteer/#{git_tag}/docs/api.md"
  end

  # @returns [String]
  def read
    require 'net/http'
    require 'uri'

    uri = URI.parse(@url)
    Net::HTTP.get_response(uri).tap(&:value).body
  end
end

class ApiMdParser
  def initialize(raw_doc)
    @raw = raw_doc.split("\n")
  end

  def parse
    skip_until_class_docs
    class_doc_chunks.map do |chunk|
      ClassDocParser.new(chunk).parse
    end
  end

  private def skip_until_class_docs
    @raw.shift until @raw.first =~ /^### class:/
  end

  private def class_doc_chunks
    Enumerator.new do |docs|
      loop do
        buf = []
        buf << @raw.shift
        buf << @raw.shift until @raw.first =~ /^### /

        docs << buf
        break unless @raw.first.start_with?('### class:')
      end
    end
  end
end

class ClassDoc
  def initialize(name, methods, events)
    @name = name
    @methods = methods
    @events = events
  end
  attr_reader :name, :methods, :events
end

class MethodDoc
  def initialize(name)
    @name = name
  end
  attr_reader :name
end

class EventDoc
  def initialize(name)
    @name = name
  end
  attr_reader :name
end

class ClassDocParser
  def initialize(md_lines)
    @raw = md_lines
  end

  def parse
    title = @raw.shift[11..-1]
    skip_until_method_or_event_docs
    methods = []
    events = []
    method_or_event_doc_chunks.each do |chunk|
      if chunk.first.include?('event:')
        events << EventDocParser.new(chunk).parse
      elsif chunk.first.match(/#### [a-zA-Z]+\.([^(]+)/)
        methods << MethodDocParser.new(chunk).parse
      end
    end

    ClassDoc.new(title, methods, events)
  end

  private def skip_until_method_or_event_docs
    @raw.shift until @raw.first.nil? || @raw.first =~ /^#### [a-zA-Z]/
  end

  private def method_or_event_doc_chunks
    Enumerator.new do |docs|
      loop do
        break if @raw.first.nil?
        buf = []
        buf << @raw.shift
        buf << @raw.shift until @raw.first.nil? || @raw.first =~ /^#### /

        docs << buf
      end
    end
  end
end

class MethodDocParser
  def initialize(md_lines)
    @raw = md_lines
  end

  def parse
    MethodDoc.new(@raw.first.match(/#### [a-zA-Z]+\.([^(]+)/)[1])
  end
end

class EventDocParser
  def initialize(md_lines)
    @raw = md_lines
  end

  def parse
    EventDoc.new(@raw.first[13...-1])
  end
end

require 'dry/inflector'

class RubyMethodName
  def initialize(js_name)
    @js_name = js_name
    @inflector = Dry::Inflector.new do |inflection|
      inflection.acronym('JavaScript', 'XPath')
    end
  end

  NAME_MAP = {
    '$' => :query_selector,
    '$$' => :query_selector_all,
    '$eval' => :eval_on_selector,
    '$$eval' => :eval_on_selector_all,
    '$x' => :Sx,
    'type' => :type_text,
    'getProperty' => :[],
  }.freeze

  def candidates
    Enumerator.new do |result|
      if NAME_MAP[@js_name]
        result << NAME_MAP[@js_name]
      end

      if snake_cased_name.start_with?("set_") # FIXME: check if with single arg.
        result << "#{snake_cased_name[4..-1]}=".to_sym
      elsif snake_cased_name.start_with?("get_")
        result << snake_cased_name[4..-1].to_sym
      elsif snake_cased_name.start_with?("is_") # FIXME: check if returns boolean
        result << "#{snake_cased_name[3..-1]}?".to_sym
      end

      result << snake_cased_name.to_sym
      result << "async_#{snake_cased_name}".to_sym
    end
  end

  private def snake_cased_name
    @snake_cased_name ||= @inflector.underscore(@js_name)
  end
end

class ImplementedClassPresenter
  def initialize(impl, doc)
    @class = impl
    @doc = doc
  end

  def api_coverages
    Enumerator.new do |data|
      data << ''
      data << "## #{class_name}"
      data << ''
      methods.each do |presenter|
        presenter.api_coverages.each(&data)
      end
    end
  end

  private def class_name
    @doc.name
  end

  private def methods
    @doc.methods.map do |method_doc|
      ruby_method_name = RubyMethodName.new(method_doc.name).candidates.find do |candidate|
        @class.public_instance_methods.include?(candidate)
      end

      if ruby_method_name
        impl = @class.public_instance_method(ruby_method_name)
        ImplementedMethodPresenter.new(impl, method_doc)
      else
        UnimplementedMethodPresenter.new(method_doc)
      end
    end
  end
end

class UnimplementedClassPresenter
  def initialize(doc)
    @doc = doc
  end

  def api_coverages
    Enumerator.new do |data|
      data << ''
      data << "## ~~#{class_name}~~"
      data << ''
      methods.each do |presenter|
        presenter.api_coverages.each(&data)
      end
    end
  end

  private def class_name
    @doc.name
  end

  private def methods
    @doc.methods.map do |method_doc|
      UnimplementedMethodPresenter.new(method_doc)
    end
  end
end

class ImplementedMethodPresenter
  def initialize(impl, doc)
    @method = impl
    @doc = doc
  end

  def api_coverages
    Enumerator.new do |data|
      data << method_line
    end
  end

  private def method_line
    if @doc.name == @method.name.to_s
      "* #{@doc.name}"
    else
      "* #{@doc.name} => `##{@method.name}`"
    end
  end
end

class UnimplementedMethodPresenter
  def initialize(doc)
    @doc = doc
  end

  def api_coverages
    Enumerator.new do |data|
      data << "* ~~#{@doc.name}~~"
    end
  end
end

raw_md = RawApiMdReader.new('v10.4.0').read
class_docs = ApiMdParser.new(raw_md).parse


File.open(File.join('.', 'docs', 'api_coverage.md'), 'w') do |f|
  f.write("# API coverages\n")
  f.write("- Puppeteer version: v10.4.0\n")
  f.write("- puppeteer-ruby version: #{Puppeteer::VERSION}\n")
end

require 'puppeteer'
class_docs.each do |class_doc|
  klass =
    if Puppeteer.const_defined?(class_doc.name)
      impl = Puppeteer.const_get(class_doc.name)
      ImplementedClassPresenter.new(impl, class_doc)
    else
      UnimplementedClassPresenter.new(class_doc)
    end

  File.open(File.join('.', 'docs', 'api_coverage.md'), 'a') do |f|
    klass.api_coverages.each do |line|
      f.write(line)
      f.write("\n")
    end
  end
end
