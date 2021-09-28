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

    ex_cat = option_categories.select { |cat| cat.start_with?('-') }.map { |cat| cat[1..-1] }
    in_cat = option_categories.reject { |cat| cat.start_with?('-') }
    @path = path
    @recording = true
    @client.send_message('Tracing.start',
      transferMode: 'ReturnAsStream',
      traceConfig: {
        excludedCategories: ex_cat,
        includedCategories: in_cat,
      },
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
    chunks = Puppeteer::ProtocolStreamReader.new(client: @client, handle: stream).read_as_chunks

    StringIO.open do |stringio|
      if @path
        File.open(@path, 'wb') do |f|
          chunks.each do |chunk|
            f.write(chunk)
            stringio.write(chunk)
          end
        end
      else
        chunks.each do |chunk|
          stringio.write(chunk)
        end
      end

      stringio.string
    end
  end
end
