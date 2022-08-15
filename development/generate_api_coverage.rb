require 'bundler/setup'
require 'json'

class Member
  def initialize(json)
    @kind = json['kind']
    @name = json['name']
    @canonical_reference = json['canonicalReference']
    @members = json['members']
  end

  attr_reader :kind, :name, :canonical_reference

  INSPECT_ALLOW_LIST = ['kind', 'canonicalReference', 'name']
  def inspect
    {
      kind: @kind,
      name: @name,
      canonical_reference: @canonical_reference,
      members: @members&.map { |member| member.select { |key, _| INSPECT_ALLOW_LIST.include?(key) } },
    }.compact.inspect
  end

  def class?
    @kind == 'Class'
  end

  def method?
    @kind == 'Method' || @kind == 'Function'
  end

  def property?
    @kind == 'Variable' && @name =~ /^[a-z]/
  end

  def members
    @__members ||= @members.map do |json|
      Member.new(json)
    end
  end
end

class ApiDocJsonParser
  def initialize(raw_doc)
    json = JSON.parse(raw_doc)
    @root = Member.new(json)
  end

  def puppeteer_doc
    ClassDoc.new('Puppeteer', method_docs_for(puppeteer_entrypoint))
  end

  def class_docs
    puppeteer_entrypoint.members.filter_map do |member|
      ClassDoc.new(member.name, method_docs_for(member)) if member.class?
    end
  end

  private def puppeteer_entrypoint
    @root.members.first
  end

  private def method_docs_for(member)
    member.members.filter_map do |m|
      MethodDoc.new(m.name) if m.method? || m.property?
    end
  end
end

class ClassDoc
  def initialize(name, methods)
    @name = name
    @methods = methods
  end
  attr_reader :name, :methods
end

class MethodDoc
  def initialize(name)
    @name = name
  end
  attr_reader :name
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

apiversion_content = File.read(File.join(__dir__, 'DOCS_VERSION')).strip
apidoc_content = File.read(File.join(__dir__, 'puppeteer.api.json'))
parser = ApiDocJsonParser.new(apidoc_content)
class_docs = parser.class_docs
class_docs.delete_if { |doc| doc.name.start_with?('Puppeteer') }
class_docs.unshift(parser.puppeteer_doc)

File.open(File.join('.', 'docs', 'api_coverage.md'), 'w') do |f|
  f.write("# API coverages\n")
  f.write("- Puppeteer version: v#{apiversion_content}\n")
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
