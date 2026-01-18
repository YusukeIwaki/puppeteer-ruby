require 'json'
require 'uri'
require 'spec_helper'

RSpec.describe 'BrowserContext cookies' do
  describe 'BrowserContext.cookies' do
    it 'should find no cookies in new context' do
      with_test_state(incognito: true, create_page: false) do |context:, **|
        expect(context.cookies).to eq([])
      end
    end

    it 'should find cookie created in page', sinatra: true do
      with_test_state(incognito: true) do |page:, server:, context:, **|
        page.goto(server.empty_page)
        page.evaluate("() => { document.cookie = 'infoCookie = secret'; }")
        cookies = context.cookies
        expect(cookies.length).to eq(1)
        expect(cookies.first).to include({
          'name' => 'infoCookie',
          'value' => 'secret',
          'domain' => 'localhost',
          'path' => '/',
          'sameParty' => false,
          'expires' => -1,
          'size' => 16,
          'httpOnly' => false,
          'secure' => false,
          'session' => true,
          'sourceScheme' => 'NonSecure',
        })
      end
    end

    it 'should find partitioned cookie' do
      with_test_state(incognito: true, create_page: false) do |context:, **|
        top_level_site = 'https://example.test'
        context.set_cookie(
          name: 'infoCookie',
          value: 'secret',
          domain: URI.parse(top_level_site).host,
          path: '/',
          sameParty: false,
          expires: -1,
          httpOnly: false,
          secure: true,
          partitionKey: {
            sourceOrigin: top_level_site,
            hasCrossSiteAncestor: false,
          },
        )
        cookies = context.cookies
        expect(cookies.length).to eq(1)
        expect(cookies.first['partitionKey']).to eq({
          'sourceOrigin' => top_level_site,
          'hasCrossSiteAncestor' => false,
        })
      end
    end
  end

  describe 'BrowserContext.setCookie' do
    it 'should set with undefined partition key', sinatra: true do
      with_test_state(incognito: true) do |page:, context:, server:, **|
        context.set_cookie(
          name: 'infoCookie',
          value: 'secret',
          domain: 'localhost',
          path: '/',
          sameParty: false,
          expires: -1,
          httpOnly: false,
          secure: false,
          sourceScheme: 'NonSecure',
        )

        page.goto(server.empty_page)

        expect(page.evaluate('() => document.cookie')).to eq('infoCookie=secret')
      end
    end

    it 'should set cookie with a partition key', sinatra: true do
      with_test_state(incognito: true) do |page:, context:, https_server:, **|
        url = URI.parse(https_server.empty_page)
        context.set_cookie(
          name: 'infoCookie',
          value: 'secret',
          domain: url.host,
          secure: true,
          partitionKey: {
            sourceOrigin: url.origin.sub(/:\d+$/, ''),
            hasCrossSiteAncestor: false,
          },
        )

        page.goto(url.to_s)

        expect(page.evaluate('() => document.cookie')).to eq('infoCookie=secret')
      end
    end
  end

  describe 'BrowserContext.deleteCookies' do
    it 'should delete cookies', sinatra: true do
      with_test_state(incognito: true) do |page:, context:, server:, **|
        page.goto(server.empty_page)
        context.set_cookie(
          {
            name: 'cookie1',
            value: '1',
            domain: 'localhost',
            path: '/',
            sameParty: false,
            expires: -1,
            httpOnly: false,
            secure: false,
            sourceScheme: 'NonSecure',
          },
          {
            name: 'cookie2',
            value: '2',
            domain: 'localhost',
            path: '/',
            sameParty: false,
            expires: -1,
            httpOnly: false,
            secure: false,
            sourceScheme: 'NonSecure',
          },
        )
        expect(page.evaluate('() => document.cookie')).to eq('cookie1=1; cookie2=2')

        cookie1 = context.cookies.find { |cookie| cookie['name'] == 'cookie1' }
        context.delete_cookie(cookie1)

        expect(page.evaluate('() => document.cookie')).to eq('cookie2=2')
      end
    end
  end

  describe 'BrowserContext.deleteMatchingCookies' do
    filters = [
      {
        name: 'cookie1',
      },
      {
        url: 'https://example.test/test',
        name: 'cookie1',
      },
      {
        domain: 'example.test',
        name: 'cookie1',
      },
      {
        path: '/test',
        name: 'cookie1',
      },
      {
        name: 'cookie1',
        partitionKey: {
          sourceOrigin: 'https://example.test',
        },
      },
    ]

    filters.each do |filter|
      it "should delete cookies matching #{JSON.generate(filter)}", sinatra: true do
        with_test_state(incognito: true) do |page:, context:, server:, **|
          page.goto(server.empty_page)
          expect(context.cookies).to eq([])
          top_level_site = 'https://example.test'
          context.set_cookie(
            {
              name: 'cookie1',
              value: 'secret',
              domain: URI.parse(top_level_site).host,
              path: '/test',
              sameParty: false,
              expires: -1,
              httpOnly: false,
              secure: true,
              partitionKey: {
                sourceOrigin: top_level_site,
                hasCrossSiteAncestor: false,
              },
            },
            {
              name: 'cookie2',
              value: 'secret',
              domain: URI.parse(top_level_site).host,
              path: '/test',
              sameParty: false,
              expires: -1,
              httpOnly: false,
              secure: true,
              partitionKey: {
                sourceOrigin: top_level_site,
                hasCrossSiteAncestor: false,
              },
            },
          )
          expect(context.cookies.length).to eq(2)
          context.delete_matching_cookies(filter)
          cookies = context.cookies
          expect(cookies.length).to eq(1)
          expect(cookies.first['name']).to eq('cookie2')
        end
      end
    end
  end
end
