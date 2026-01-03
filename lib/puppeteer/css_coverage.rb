require_relative './coverage'

class Puppeteer::CSSCoverage
  include Puppeteer::Coverage::UtilFunctions

  class Item
    def initialize(url:, ranges:, text:)
      @url = url
      @ranges = ranges
      @text = text
    end
    attr_reader :url, :ranges, :text
  end

  # @param client [Puppeteer::CDPSession]
  def initialize(client)
    @client = client
    @enabled = false
    @stylesheet_urls = {}
    @stylesheet_sources = {}
  end

  def start(reset_on_navigation: nil)
    raise 'CSSCoverage is already enabled' if @enabled

    @reset_on_navigation =
      if [true, false].include?(reset_on_navigation)
        reset_on_navigation
      else
        true
      end

    @enabled = true
    @stylesheet_urls.clear
    @stylesheet_sources.clear
    @event_listeners = []
    @event_listeners << @client.add_event_listener('CSS.styleSheetAdded') do |event|
      Async do
        Puppeteer::AsyncUtils.future_with_logging { on_stylesheet(event) }.call
      end
    end
    @event_listeners << @client.add_event_listener('Runtime.executionContextsCleared') do
      on_execution_contexts_cleared
    end
    Puppeteer::AsyncUtils.await_promise_all(
      @client.async_send_message('DOM.enable'),
      @client.async_send_message('CSS.enable'),
      @client.async_send_message('CSS.startRuleUsageTracking'),
    )
  end

  private def on_execution_contexts_cleared
    return unless @reset_on_navigation
    @stylesheet_urls.clear
    @stylesheet_sources.clear
  end

  private def on_stylesheet(event)
    header = event['header']
    source_url =
      if header['sourceURL'] == ""
        nil
      else
        header['sourceURL']
      end

    # Ignore anonymous scripts
    return if !source_url

    response = @client.send_message('CSS.getStyleSheetText', styleSheetId: header['styleSheetId'])
    @stylesheet_urls[header['styleSheetId']] = source_url
    @stylesheet_sources[header['styleSheetId']] = response['text']
  end


  def stop
    raise 'CSSCoverage is not enabled' unless @enabled
    @enabled = false

    rule_tracking_response = @client.send_message('CSS.stopRuleUsageTracking')
    Puppeteer::AsyncUtils.await_promise_all(
      @client.async_send_message('CSS.disable'),
      @client.async_send_message('DOM.disable'),
    )
    @client.remove_event_listener(*@event_listeners)

    # aggregate by styleSheetId
    stylesheet_id_to_coverage = {}
    rule_tracking_response['ruleUsage'].each do |entry|
      ranges = stylesheet_id_to_coverage[entry['styleSheetId']]
      unless ranges
        ranges = []
        stylesheet_id_to_coverage[entry['styleSheetId']] = ranges
      end

      ranges << {
        'startOffset' => entry['startOffset'],
        'endOffset' => entry['endOffset'],
        'count' => entry['used'] ? 1 : 0,
      }
    end

    coverage = []
    @stylesheet_urls.each do |stylesheet_id, url|
      text = @stylesheet_sources[stylesheet_id]
      ranges = convert_to_disjoint_ranges(stylesheet_id_to_coverage[stylesheet_id] || [])
      coverage << Item.new(url: url, ranges: ranges, text: text)
    end

    coverage
  end
end
