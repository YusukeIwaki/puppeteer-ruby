require_relative './coverage'

class Puppeteer::JSCoverage
  include Puppeteer::Coverage::UtilFunctions

  class Item
    def initialize(url:, ranges:, text:)
      @url = url
      @ranges = ranges
      @text = text
    end
    attr_reader :url, :ranges, :text
  end

  class ItemWithRawScriptCoverage < Item
    def initialize(url:, ranges:, text:, raw_script_coverage:)
      super(url: url, ranges: ranges, text: text)
      @raw_script_coverage = raw_script_coverage
    end
    attr_reader :raw_script_coverage
  end

  # @param client [Puppeteer::CDPSession]
  def initialize(client)
    @client = client
    @enabled = false
    @script_urls = {}
    @script_sources = {}
  end

  def start(
        reset_on_navigation: nil,
        report_anonymous_scripts: nil,
        include_raw_script_coverage: nil,
        use_block_coverage: nil)
    raise 'JSCoverage is already enabled' if @enabled

    @reset_on_navigation =
      if [true, false].include?(reset_on_navigation)
        reset_on_navigation
      else
        true
      end
    @use_block_coverage =
      if [true, false].include?(use_block_coverage)
        use_block_coverage
      else
        true
      end
    @report_anonymous_scripts = report_anonymous_scripts || false
    @include_raw_script_coverage = include_raw_script_coverage || false
    @enabled = true
    @script_urls.clear
    @script_sources.clear
    @event_listeners = []
    @event_listeners << @client.add_event_listener('Debugger.scriptParsed') do |event|
      future { on_script_parsed(event) }
    end
    @event_listeners << @client.add_event_listener('Runtime.executionContextsCleared') do
      on_execution_contexts_cleared
    end
    await_all(
      @client.async_send_message('Profiler.enable'),
      @client.async_send_message('Profiler.startPreciseCoverage',
        callCount: @include_raw_script_coverage,
        detailed: @use_block_coverage,
      ),
      @client.async_send_message('Debugger.enable'),
      @client.async_send_message('Debugger.setSkipAllPauses', skip: true),
    )
  end

  private def on_execution_contexts_cleared
    return unless @reset_on_navigation
    @script_urls.clear
    @script_sources.clear
  end

  private def on_script_parsed(event)
    url =
      if event['url'] == ""
        nil
      else
        event['url']
      end

    # Ignore puppeteer-injected scripts
    return if url == Puppeteer::ExecutionContext::EVALUATION_SCRIPT_URL

    # Ignore other anonymous scripts unless the reportAnonymousScripts option is true.
    return if !url && !@report_anonymous_scripts

    response = @client.send_message('Debugger.getScriptSource', scriptId: event['scriptId'])
    @script_urls[event['scriptId']] = url
    @script_sources[event['scriptId']] = response['scriptSource']
  end

  def stop
    raise 'JSCoverage is not enabled' unless @enabled
    @enabled = false

    results = await_all(
      @client.async_send_message('Profiler.takePreciseCoverage'),
      @client.async_send_message('Profiler.stopPreciseCoverage'),
      @client.async_send_message('Profiler.disable'),
      @client.async_send_message('Debugger.disable'),
    )
    @client.remove_event_listener(*@event_listeners)

    coverage = []
    profile_response = results.first
    profile_response['result'].each do |entry|
      url = @script_urls[entry['scriptId']]

      if @report_anonymous_scripts
        url ||= "debugger://VM#{entry['scriptId']}"
      end

      text = @script_sources[entry['scriptId']]
      next if !text || !url

      flatten_ranges = []
      entry['functions'].each do |func|
        func['ranges'].each do |range|
          flatten_ranges << range
        end
      end

      if @include_raw_script_coverage
        coverage << ItemWithRawScriptCoverage.new(
          url: url,
          ranges: convert_to_disjoint_ranges(flatten_ranges),
          text: text,
          raw_script_coverage: entry,
        )
      else
        coverage << Item.new(
          url: url,
          ranges: convert_to_disjoint_ranges(flatten_ranges),
          text: text,
        )
      end
    end

    coverage
  end
end
