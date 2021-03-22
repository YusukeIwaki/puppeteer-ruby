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
      puts "==>#{chunk}"
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

raw_md = RawApiMdReader.new('v8.0.0').read
class_docs = ApiMdParser.new(raw_md).parse

# require 'pry'
# Pry.start
