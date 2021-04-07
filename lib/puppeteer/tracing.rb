class Puppeteer::Tracing
  # @param client [Puppeteer::CDPSession]
  def initialize(client)
    @client = client
    @recording = false
  end

  DEFAULT_CATEGORIES = [
    '-*',
    'devtools.timeline',
    'v8.execute',
    'disabled-by-default-devtools.timeline',
    'disabled-by-default-devtools.timeline.frame',
    'toplevel',
    'blink.console',
    'blink.user_timing',
    'latencyInfo',
    'disabled-by-default-devtools.timeline.stack',
    'disabled-by-default-v8.cpu_profiler',
    'disabled-by-default-v8.cpu_profiler.hires',
  ].freeze

  def start(path: nil, screenshots: nil, categories: nil)
    option_categories = categories || DEFAULT_CATEGORIES.dup

    if screenshots
      option_categories << 'disabled-by-default-devtools.screenshot'
    end

    @path = path
    @recording = true
    @client.send_message('Tracing.start',
      transferMode: 'ReturnAsStream',
      categories: option_categories.join(','),
    )
  end

  def stop
    stream_promise = resolvable_future do |f|
      @client.once('Tracing.tracingComplete') do |event|
        f.fulfill(event['stream'])
      end
    end
    @client.send_message('Tracing.end')
    @recording = false

    stream = await stream_promise
    Puppeteer::ProtocolStreamReader.new(client: @client, handle: stream, path: @path).read
  end
end
