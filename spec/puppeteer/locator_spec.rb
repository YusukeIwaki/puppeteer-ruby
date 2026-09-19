require 'spec_helper'

FakeLocatorOwner = Struct.new(:logger, :default_timeout)

class FakeLocatorWaitHandle
  def dispose
    nil
  end
end

class FakeLocatorFrame
  def wait_for_function(*)
    FakeLocatorWaitHandle.new
  end
end

class FakeLocatorHandle
  STABLE_RECT = { 'x' => 0, 'y' => 0, 'width' => 10, 'height' => 10 }.freeze

  def initialize(action_error, dispose_error)
    @action_error = action_error
    @dispose_error = dispose_error
  end

  # Readiness conditions pass so the only failure is the intended one.
  def evaluate(*)
    [STABLE_RECT, STABLE_RECT]
  end

  def frame
    @frame ||= FakeLocatorFrame.new
  end

  def intersecting_viewport?(*)
    true
  end

  def click(**)
    raise @action_error
  end

  def dispose
    raise @dispose_error
  end
end

class FakeLocatorOwnerWithHandle
  def initialize(owner, handle)
    @owner = owner
    @handle = handle
  end

  def logger
    @owner.logger
  end

  def default_timeout
    @owner.default_timeout
  end

  def wait_for_selector(*)
    @handle
  end
end

RSpec.describe Puppeteer::Locator do
  let(:logger) { ->(_prefix) { } }

  it 'forwards the owner logger to node locators' do
    owner = FakeLocatorOwner.new(logger, 1000)
    locator = Puppeteer::NodeLocator.create(owner, 'div')
    expect(locator.logger).to be(logger)
  end

  it 'forwards the owner logger to function locators' do
    owner = FakeLocatorOwner.new(logger, 1000)
    locator = Puppeteer::FunctionLocator.create(owner, '() => true')
    expect(locator.logger).to be(logger)
  end

  it 'keeps the logger through race and clones' do
    owner = FakeLocatorOwner.new(logger, 1000)
    first = Puppeteer::NodeLocator.create(owner, 'div')
    second = Puppeteer::NodeLocator.create(owner, 'span')
    race = Puppeteer::Locator.race([first, second])
    expect(race.logger).to be(logger)
    expect(first.set_timeout(500).logger).to be(logger)
  end

  it 'constructs an empty race with a disabled logger like upstream' do
    race = nil
    expect { race = Puppeteer::Locator.race([]) }.not_to raise_error
    expect(race.logger.call(Puppeteer::DebugPrefixes::ERROR)).to be_nil
  end

  it 'forwards handle disposal errors to the error logger' do
    errors = []
    error_logger = lambda do |prefix|
      if prefix == Puppeteer::DebugPrefixes::ERROR
        lambda { |error| errors << error }
      end
    end
    owner = FakeLocatorOwner.new(error_logger, 1000)
    action_error = Puppeteer::Error.new('action failed')
    dispose_error = Puppeteer::Error.new('dispose failed')
    handle = FakeLocatorHandle.new(action_error, dispose_error)
    frame = FakeLocatorOwnerWithHandle.new(owner, handle)
    locator = Puppeteer::NodeLocator.create(frame, 'div')

    expect { locator.click }.to raise_error(Puppeteer::TimeoutError)
    expect(errors).to include(dispose_error)
  end
end
