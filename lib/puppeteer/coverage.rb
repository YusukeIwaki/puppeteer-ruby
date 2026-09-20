class Puppeteer::Coverage
  # @param client [Puppeteer::CDPSession]
  def initialize(client, logger: nil)
    @js = Puppeteer::JSCoverage.new(client, logger: logger)
    @css = Puppeteer::CSSCoverage.new(client, logger: logger)
  end

  def update_client(client)
    @js.update_client(client)
    @css.update_client(client)
  end

  # Note: setting reset_on_navigation to false does not guarantee that coverage
  # survives a navigation. Chrome may discard the previous page's JavaScript
  # execution environment, including its coverage data, when navigating.
  # To preserve coverage, call stop_js_coverage before navigating away, then
  # start a new collection for the next page and merge the reports.
  def start_js_coverage(
        reset_on_navigation: nil,
        report_anonymous_scripts: nil,
        include_raw_script_coverage: nil,
        use_block_coverage: nil)
    @js.start(
      reset_on_navigation: reset_on_navigation,
      report_anonymous_scripts: report_anonymous_scripts,
      include_raw_script_coverage: include_raw_script_coverage,
      use_block_coverage: use_block_coverage,
    )
  end

  def stop_js_coverage
    @js.stop
  end

  # See start_js_coverage for a caveat on reset_on_navigation: false not
  # guaranteeing coverage preservation across navigations.
  def js_coverage(
        reset_on_navigation: nil,
        report_anonymous_scripts: nil,
        include_raw_script_coverage: nil,
        use_block_coverage: nil,
        &block)
    unless block
      raise ArgumentError.new('Block must be given')
    end

    start_js_coverage(
      reset_on_navigation: reset_on_navigation,
      report_anonymous_scripts: report_anonymous_scripts,
      include_raw_script_coverage: include_raw_script_coverage,
      use_block_coverage: use_block_coverage,
    )
    block.call
    stop_js_coverage
  end

  def start_css_coverage(reset_on_navigation: nil)
    @css.start(reset_on_navigation: reset_on_navigation)
  end

  def stop_css_coverage
    @css.stop
  end

  def css_coverage(reset_on_navigation: nil, &block)
    unless block
      raise ArgumentError.new('Block must be given')
    end

    start_css_coverage(reset_on_navigation: reset_on_navigation)
    block.call
    stop_css_coverage
  end

  module UtilFunctions
    private def convert_to_disjoint_ranges(nested_ranges)
      points = []
      nested_ranges.each do |range|
        points << { offset: range['startOffset'], type: 0, range: range }
        points << { offset: range['endOffset'], type: 1, range: range }
      end

      # Sort points to form a valid parenthesis sequence.
      points.sort! do |a, b|
        if a[:offset] != b[:offset]
          # Sort with increasing offsets.
          a[:offset] <=> b[:offset]
        elsif a[:type] != b[:type]
          # All "end" points should go before "start" points.
          b[:type] <=> a[:type]
        else
          alength = a[:range]['endOffset'] - a[:range]['startOffset']
          blength = b[:range]['endOffset'] - b[:range]['startOffset']
          if a[:type] == 0
            # For two "start" points, the one with longer range goes first.
            blength <=> alength
          else
            # For two "end" points, the one with shorter range goes first.
            alength <=> blength
          end
        end
      end

      hit_count_stack = []
      results = []
      last_offset = 0
      # Run scanning line to intersect all ranges.
      points.each do |point|
        if !hit_count_stack.empty? && last_offset < point[:offset] && hit_count_stack.last > 0
          last_result = results.last
          if last_result && last_result[:end] == last_offset
            last_result[:end] = point[:offset]
          else
            results << { start: last_offset, end: point[:offset] }
          end
        end
        last_offset = point[:offset]
        if point[:type] == 0
          hit_count_stack << point[:range]['count']
        else
          hit_count_stack.pop
        end
      end

      # Filter out empty ranges.
      results.select do |range|
        range[:end] - range[:start] > 0
      end
    end
  end
end
