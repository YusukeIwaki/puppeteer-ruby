class Puppeteer::Page
  class Metrics
    SUPPORTED_KEYS = Set.new([
      'Timestamp',
      'Documents',
      'Frames',
      'JSEventListeners',
      'Nodes',
      'LayoutCount',
      'RecalcStyleCount',
      'LayoutDuration',
      'RecalcStyleDuration',
      'ScriptDuration',
      'TaskDuration',
      'JSHeapUsedSize',
      'JSHeapTotalSize',
    ]).freeze

    SUPPORTED_KEYS.each do |key|
      attr_reader key
    end

    # @param metrics_result [Hash] response for Performance.getMetrics
    def initialize(metrics_response)
      metrics_response.each do |metric|
        if SUPPORTED_KEYS.include?(metric['name'])
          instance_variable_set(:"@#{metric['name']}", metric['value'])
        end
      end
    end

    def [](key)
      if SUPPORTED_KEYS.include?(key.to_s)
        instance_variable_get(:"@#{key}")
      else
        raise ArgumentError.new("invalid metric key specified: #{key}")
      end
    end
  end

  class MetricsEvent
    def initialize(metrics_event)
      @title = metrics_event['title']
      @metrics = Metrics.new(metrics_event['metrics'])
    end

    attr_reader :title, :metrics
  end
end
