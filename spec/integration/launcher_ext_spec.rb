require 'spec_helper'

# Ruby-specific coverage for the experimental custom logger (upstream
# puppeteer/puppeteer#15324): protocol traffic reaches user-supplied sinks.
RSpec.describe 'Launcher custom logger', sinatra: true do
  include_context 'with test state'
  it 'should support a custom logger for protocol traffic', sinatra: true do
    sends = []
    receives = []
    mutex = Mutex.new
    logger = lambda do |prefix|
      # Disabled channels return nil; logging must not crash for them.
      case prefix
      when Puppeteer::DebugPrefixes::CDP_SEND
        lambda do |*args|
          mutex.synchronize { sends << args }
        end
      when Puppeteer::DebugPrefixes::CDP_RECEIVE
        lambda do |*args|
          mutex.synchronize { receives << args }
        end
      end
    end

    options = default_launch_options.merge(logger: logger)
    Puppeteer.launch(**options) do |browser|
      page = browser.new_page
      page.goto(server_empty_page)
      expect(page.evaluate('() => 1 + 1')).to eq(2)
    end

    expect(sends).not_to be_empty
    expect(sends.flatten.join).to include('Page.navigate')
    # Like upstream, protocol messages are logged as JSON strings.
    expect(receives).not_to be_empty
    expect(receives.flatten.map(&:class).uniq).to eq([String])
    expect(sends.flatten.map(&:class).uniq).to eq([String])
  end

  it 'forwards handle disposal failures to the error logger' do
    errors = []
    mutex = Mutex.new
    logger = lambda do |prefix|
      if prefix == Puppeteer::DebugPrefixes::ERROR
        lambda { |error| mutex.synchronize { errors << error } }
      end
    end

    options = default_launch_options.merge(logger: logger)
    Puppeteer.launch(**options) do |browser|
      page = browser.new_page
      handle = page.evaluate_handle('() => ({foo: 42})')
      page.close
      mutex.synchronize { errors.clear }
      handle.dispose
      expect(errors.map(&:message).join).to include('Runtime.releaseObject')
    end
  end

  it 'logs exposed-function delivery failures to the error logger' do
    errors = []
    mutex = Mutex.new
    logger = lambda do |prefix|
      if prefix == Puppeteer::DebugPrefixes::ERROR
        lambda { |error| mutex.synchronize { errors << error } }
      end
    end

    options = default_launch_options.merge(logger: logger)
    Puppeteer.launch(**options) do |browser|
      page = browser.new_page
      page.expose_function('callback_for_delivery_failure', ->(*_args) { 'ok' })
      # The page clears the pending callbacks, so the delivery expression
      # throws a TypeError inside Runtime.evaluate (exceptionDetails, not a
      # protocol rejection). Like upstream, that delivery failure is logged.
      page.evaluate('callback_for_delivery_failure(); callback_for_delivery_failure.callbacks.clear(); 42')
      Timeout.timeout(15) do
        sleep 0.05 while mutex.synchronize { errors.empty? }
      end
      sleep 0.3
      logged = mutex.synchronize { errors.dup }
      expect(logged.length).to eq(1)
      expect(logged.first.message).to include('Evaluation failed')
      # The logged failure must be the *reject* delivery: the resolve
      # delivery failure is recovered by attempting reject (upstream
      # Binding.run), and only a failed reject is logged. Pre-fix code logged
      # the resolve failure ("reading 'resolve'") instead.
      expect(logged.first.message).to include("'reject'")
      expect(logged.first.message).not_to include('resolve')
    end
  end
end
