require 'spec_helper'

RSpec.describe Puppeteer::CDPSession do
  it 'should work' do
    client = page.target.create_cdp_session

    client.send_message('Runtime.enable')
    client.send_message('Runtime.evaluate', expression: 'window.foo = "bar"')

    foo = page.evaluate('() => globalThis.foo')
    expect(foo).to eq('bar')
  end

  context 'with empty page', sinatra: true do
    before {
      sinatra.get('/') { 'Hello' }
    }

    it 'should send events' do
      client = page.target.create_cdp_session

      client.send_message('Network.enable')

      events = []
      client.on('Network.requestWillBeSent') do |event|
        events << event
      end
      page.goto("#{server_prefix}/")
      expect(events.size).to eq(1)
    end
  end

  # it('should enable and disable domains independently', async () => {
  #   const { page } = getTestState();

  #   const client = await page.target().createCDPSession();
  #   await client.send('Runtime.enable');
  #   await client.send('Debugger.enable');
  #   // JS coverage enables and then disables Debugger domain.
  #   await page.coverage.startJSCoverage();
  #   await page.coverage.stopJSCoverage();
  #   // generate a script in page and wait for the event.
  #   const [event] = await Promise.all([
  #     waitEvent(client, 'Debugger.scriptParsed'),
  #     page.evaluate('//# sourceURL=foo.js'),
  #   ]);
  #   // expect events to be dispatched.
  #   expect(event.url).toBe('foo.js');
  # });

  it_fails_firefox 'should be able to detach session' do
    client = page.target.create_cdp_session

    client.send_message('Runtime.enable')
    eval_response = client.send_message('Runtime.evaluate', expression: '1 + 2', returnByValue: true)
    expect(eval_response['result']['value']).to eq(3)

    # Target.detachFromTarget seems not to be implemented in Firefox.
    # Only Chrome can pass this spec.
    client.detach

    expect {
      client.send_message('Runtime.evaluate', expression: '3 + 1', returnByValue: true)
    }.to raise_error(/Session closed./)
  end

  it 'should throw nice errors' do
    client = page.target.create_cdp_session

    expect {
      client.send_message('ThisCommand.DoesNotExist')
    }.to raise_error(/ThisCommand.DoesNotExist/)
  end
end
