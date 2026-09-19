require 'spec_helper'

class FakeMouseClient
  attr_reader :commands

  def initialize(fail_on: nil, failure: nil)
    @commands = []
    @fail_on = fail_on
    @failure = failure
  end

  def send_message(method, **params)
    @commands << { method: method, params: params }
    raise @failure if @fail_on && params[:type] == @fail_on
    {}
  end

  def once(_event, &block)
    block.call({ 'data' => { 'items' => [] } })
    1
  end
end

FakeMouseKeyboard = Struct.new(:modifiers)
FakeMousePoint = Struct.new(:x, :y)

RSpec.describe Puppeteer::Mouse do
  def build_mouse(client)
    described_class.new(client, FakeMouseKeyboard.new(0))
  end

  def released_commands(client)
    client.commands.select do |command|
      command[:method] == 'Input.dispatchMouseEvent' &&
        command[:params][:type] == 'mouseReleased'
    end
  end

  it 'releases the button when the drop fails without masking the error' do
    failure = Puppeteer::Error.new('Node is detached from document')
    client = FakeMouseClient.new(fail_on: 'drop', failure: failure)
    mouse = build_mouse(client)

    expect do
      mouse.drag_and_drop(FakeMousePoint.new(10, 10), FakeMousePoint.new(50, 50))
    end.to raise_error(failure)
    expect(released_commands(client).length).to eq(1)
  end

  it 'releases the button when drag_and_drop succeeds exactly once' do
    client = FakeMouseClient.new
    mouse = build_mouse(client)

    mouse.drag_and_drop(FakeMousePoint.new(10, 10), FakeMousePoint.new(50, 50))

    expect(released_commands(client).length).to eq(1)
  end
end
