require 'spec_helper'

RSpec.describe 'BrowserContext#override_permissions' do
  def get_permission_for(page, name)
    page.evaluate(
      "(name) => navigator.permissions.query({ name }).then((result) => result.state)",
      name,
    )
  end

  def with_incognito_page(&block)
    with_test_state(incognito: true) do |page:, server:, context:, browser:, **|
      page.goto(server.empty_page)
      block.call(page: page, server: server, context: context, browser: browser)
    end
  end

  it 'should be prompt by default', sinatra: true do
    with_incognito_page do |page:, **|
      expect(get_permission_for(page, 'geolocation')).to eq('prompt')
    end
  end

  it 'should deny permission when not listed', sinatra: true do
    with_incognito_page do |page:, server:, context:, **|
      context.override_permissions(server.empty_page, [])
      expect(get_permission_for(page, 'geolocation')).to eq('denied')
    end
  end

  it 'should fail when bad permission is given', sinatra: true do
    with_incognito_page do |server:, context:, **|
      expect { context.override_permissions(server.empty_page, ['foo']) }.
        to raise_error(/Unknown permission: foo/)
    end
  end

  it 'should grant permission when listed', sinatra: true do
    with_incognito_page do |page:, server:, context:, **|
      context.override_permissions(server.empty_page, ['geolocation'])
      expect(get_permission_for(page, 'geolocation')).to eq('granted')
    end
  end

  it 'should reset permissions', sinatra: true do
    with_incognito_page do |page:, server:, context:, **|
      context.override_permissions(server.empty_page, ['geolocation'])

      expect {
        context.clear_permission_overrides
      }.to change { get_permission_for(page, 'geolocation') }.from('granted').to('prompt')
    end
  end

  it 'should trigger permission onchange', sinatra: true do
    with_incognito_page do |page:, server:, context:, **|
      js = <<~JAVASCRIPT
      () => {
        globalThis.events = [];
        return navigator.permissions
          .query({ name: 'geolocation' })
          .then(function (result) {
            globalThis.events.push(result.state);
            result.onchange = function () {
              globalThis.events.push(result.state);
            };
          });
      }
      JAVASCRIPT
      page.evaluate(js)
      expect(page.evaluate('() => globalThis.events')).to eq(%w[prompt])
      context.override_permissions(server.empty_page, [])
      expect(page.evaluate('() => globalThis.events')).to eq(%w[prompt denied])
      context.override_permissions(server.empty_page, ['geolocation'])
      expect(page.evaluate('() => globalThis.events')).to eq(%w[prompt denied granted])
      context.clear_permission_overrides
      expect(page.evaluate('() => globalThis.events')).to eq(%w[prompt denied granted prompt])
    end
  end

  it 'should isolate permissions between browser contexs', sinatra: true do
    with_incognito_page do |page:, server:, browser:, context:, **|
      other_context = browser.create_incognito_browser_context
      other_page = other_context.new_page
      other_page.goto(server.empty_page)

      expect(get_permission_for(page, 'geolocation')).to eq('prompt')
      expect(get_permission_for(other_page, 'geolocation')).to eq('prompt')

      context.override_permissions(server.empty_page, [])
      other_context.override_permissions(server.empty_page, ['geolocation'])

      expect(get_permission_for(page, 'geolocation')).to eq('denied')
      expect(get_permission_for(other_page, 'geolocation')).to eq('granted')

      context.clear_permission_overrides

      expect(get_permission_for(page, 'geolocation')).to eq('prompt')
      expect(get_permission_for(other_page, 'geolocation')).to eq('granted')
    ensure
      other_context&.close
    end
  end

  it 'should grant persistent-storage', sinatra: true do
    with_incognito_page do |page:, server:, context:, **|
      expect(get_permission_for(page, 'persistent-storage')).to eq('prompt')
      context.override_permissions(server.empty_page, ['persistent-storage'])
      expect(get_permission_for(page, 'persistent-storage')).to eq('granted')
    end
  end

  it 'should set permission state with set_permission', sinatra: true do
    with_incognito_page do |page:, server:, context:, **|
      context.set_permission(
        server.empty_page,
        { permission: { name: 'geolocation' }, state: 'denied' },
      )
      expect(get_permission_for(page, 'geolocation')).to eq('denied')

      context.set_permission(
        server.empty_page,
        { permission: { name: 'geolocation' }, state: 'granted' },
      )
      expect(get_permission_for(page, 'geolocation')).to eq('granted')

      context.set_permission(
        server.empty_page,
        { permission: { name: 'geolocation' }, state: 'prompt' },
      )
      expect(get_permission_for(page, 'geolocation')).to eq('prompt')
    end
  end

  it 'should apply set_permission to all origins with wildcard', sinatra: true do
    with_incognito_page do |page:, context:, **|
      context.set_permission(
        '*',
        { permission: { name: 'geolocation' }, state: 'denied' },
      )
      expect(get_permission_for(page, 'geolocation')).to eq('denied')
    end
  end
end
