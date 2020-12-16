require 'spec_helper'

RSpec.describe 'cookies' do
  sinatra do
    disable :protection

    get("/empty.html") { "" }
  end

  describe 'Page#cookies' do
    it 'should return no cookies in pristine browser context' do
      page.goto("http://127.0.0.1:4567/empty.html")
      expect(page.cookies).to eq([])
    end

    it 'should get a cookie' do
      page.goto("http://127.0.0.1:4567/empty.html")
      page.evaluate("() => { document.cookie = 'username=John Doe'; }")
      expect(page.cookies).to contain_exactly(include({
        "name" => 'username',
        "value" => 'John Doe',
        "domain" => '127.0.0.1',
        "path" => '/',
        "expires" => -1,
        "size" => 16,
        "httpOnly" => false,
        "secure" => false,
        "session" => true,
      }))
    end

    it 'should properly report httpOnly cookie' do
      sinatra.get("/empty_httponly.html") {
        response.headers["Set-Cookie"] = "a=b; HttpOnly; Path=/"
        ""
      }

      page.goto('http://127.0.0.1:4567/empty_httponly.html')
      cookies = page.cookies
      expect(cookies.size).to eq(1)
      expect(cookies.first["httpOnly"]).to eq(true)
    end

    it 'should properly report "Strict" sameSite cookie' do
      sinatra.get("/empty_samesite_strict.html") {
        response.headers["Set-Cookie"] = "a=b; SameSite=Strict"
        ""
      }

      page.goto('http://127.0.0.1:4567/empty_samesite_strict.html')
      cookies = page.cookies
      expect(cookies.size).to eq(1)
      expect(cookies.first["sameSite"]).to eq("Strict")
    end

    it 'should properly report "Lax" sameSite cookie' do
      sinatra.get("/empty_samesite_lax.html") {
        response.headers["Set-Cookie"] = "a=b; SameSite=Lax"
        ""
      }

      page.goto('http://127.0.0.1:4567/empty_samesite_lax.html')
      cookies = page.cookies
      expect(cookies.size).to eq(1)
      expect(cookies.first["sameSite"]).to eq("Lax")
    end

    it 'should get multiple cookies' do
      page.goto('http://127.0.0.1:4567/empty.html')
      page.evaluate("() => { document.cookie = 'username=John Doe'; document.cookie = 'password=1234'; }")
      expect(page.cookies).to match_array([
        include({
          'name' => 'password',
          'value' => '1234',
          'domain' => '127.0.0.1',
          'path' => '/',
          'expires' => -1,
          'size' => 12,
          'httpOnly' => false,
          'secure' => false,
          'session' => true,
        }),
        include({
          'name' => 'username',
          'value' => 'John Doe',
          'domain' => '127.0.0.1',
          'path' => '/',
          'expires' => -1,
          'size' => 16,
          'httpOnly' => false,
          'secure' => false,
          'session' => true,
        }),
      ])
    end

    it_fails_firefox 'should get cookies from multiple urls' do
      page.set_cookie(
        {
          url: 'https://foo.com',
          name: 'doggo',
          value: 'woofs',
        },
        {
          url: 'https://bar.com',
          name: 'catto',
          value: 'purrs',
        },
        {
          url: 'https://baz.com',
          name: 'birdo',
          value: 'tweets',
        },
      )

      expect(page.cookies('https://foo.com', 'https://baz.com')).to contain_exactly(
        include({
          'name' => 'birdo',
          'value' => 'tweets',
          'domain' => 'baz.com',
          'path' => '/',
          'expires' => -1,
          'size' => 11,
          'httpOnly' => false,
          'secure' => true,
          'session' => true,
        }),
        include({
          'name' => 'doggo',
          'value' => 'woofs',
          'domain' => 'foo.com',
          'path' => '/',
          'expires' => -1,
          'size' => 10,
          'httpOnly' => false,
          'secure' => true,
          'session' => true,
        }),
      )
    end
  end

  describe 'Page#set_cookie' do
    it 'should work' do
      page.goto('http://127.0.0.1:4567/empty.html')
      page.set_cookie(name: 'password', value: '123456')
      expect(page.evaluate('document.cookie')).to eq('password=123456')
    end

    it_fails_firefox 'should isolate cookies in browser contexts' do
      another_context = page.browser.create_incognito_browser_context
      another_page = another_context.new_page

      page.goto('http://127.0.0.1:4567/empty.html')
      another_page.goto('http://127.0.0.1:4567/empty.html')

      begin
        page.set_cookie(name: 'page1cookie', value: 'page1value')
        another_page.set_cookie(name: 'page2cookie', value: 'page2value')

        cookies1 = page.cookies
        cookies2 = another_page.cookies
        expect(cookies1).to contain_exactly(include("name" => "page1cookie", "value" => "page1value"))
        expect(cookies2).to contain_exactly(include("name" => "page2cookie", "value" => "page2value"))
      ensure
        another_context.close
      end
    end

    it 'should set multiple cookies' do
      page.goto('http://127.0.0.1:4567/empty.html')
      page.set_cookie(
        {
          name: 'password',
          value: '123456',
        },
        {
          name: 'foo',
          value: 'bar',
        },
      )
      expect(page.evaluate("() => document.cookie.split(';').map((cookie) => cookie.trim())")).to contain_exactly(
        "foo=bar",
        "password=123456",
      )
    end

    it 'should have |expires| set to |-1| for session cookies' do
      page.goto('http://127.0.0.1:4567/empty.html')
      page.set_cookie(name: "password", value: "123456")
      expect(page.cookies).to contain_exactly(include("session" => true, "expires" => -1))
    end

    it 'should set cookie with reasonable defaults' do
      page.goto('http://127.0.0.1:4567/empty.html')
      page.set_cookie(name: "password", value: "123456")
      expect(page.cookies).to contain_exactly(include(
        'name' => 'password',
        'value' => '123456',
        'domain' => '127.0.0.1',
        'path' => '/',
        'expires' => -1,
        'size' => 14,
        'httpOnly' => false,
        'secure' => false,
        'session' => true,
      ))
    end

    it 'should set a cookie with a path' do
      sinatra.get('/grid.html') { "GRID" }

      page.goto("http://127.0.0.1:4567/grid.html")
      page.set_cookie(name: "gridcookie", value: "GRID", path: "/grid.html")
      expect(page.cookies).to contain_exactly(include(
        'name' => 'gridcookie',
        'value' => 'GRID',
        'domain' => '127.0.0.1',
        'path' => '/grid.html',
        'expires' => -1,
        'size' => 14,
        'httpOnly' => false,
        'secure' => false,
        'session' => true,
      ))
      expect(page.evaluate("document.cookie")).to eq("gridcookie=GRID")

      page.goto("http://127.0.0.1:4567/empty.html")
      expect(page.evaluate("document.cookie")).to eq("")

      page.goto("http://127.0.0.1:4567/grid.html")
      expect(page.evaluate("document.cookie")).to eq("gridcookie=GRID")
    end

    it 'should not set a cookie on a blank page' do
      page.goto('about:blank')
      expect { page.set_cookie(name: 'example-cookie', value: 'best') }.to raise_error(/At least one of the url and domain needs to be specified/)
    end

    it 'should not set a cookie with blank page URL' do
      page.goto('http://127.0.0.1:4567/empty.html')
      expect {
        page.set_cookie(
          { name: 'example-cookie', value: 'best' },
          { url: 'about:blank', name: 'example-cookie-blank', value: 'best' },
        )
      }.to raise_error(/Blank page can not have cookie "example-cookie-blank"/)
    end

    it 'should not set a cookie on a data URL page' do
      page.goto('data:,Hello%2C%20World!')
      expect { page.set_cookie(name: 'example-cookie', value: 'best') }.to raise_error(/At least one of the url and domain needs to be specified/)
    end

    it_fails_firefox 'should default to setting secure cookie for HTTPS websites' do
      page.goto('http://127.0.0.1:4567/empty.html')
      secure_url = 'https://example.com'
      page.set_cookie(url: secure_url, name: "foo", value: "bar")
      expect(page.cookies(secure_url)).to contain_exactly(include("secure" => true))
    end

    it_fails_firefox 'should be able to set unsecure cookie for HTTP website' do
      page.goto('http://127.0.0.1:4567/empty.html')
      http_url = 'http://example.com'
      page.set_cookie(url: http_url, name: "foo", value: "bar")
      expect(page.cookies(http_url)).to contain_exactly(include("secure" => false))
    end

    it_fails_firefox 'should set a cookie on a different domain' do
      page.goto('http://127.0.0.1:4567/empty.html')
      page.set_cookie(
        url: 'https://www.example.com',
        name: 'example-cookie',
        value: 'best',
      )
      expect(page.evaluate('document.cookie')).to eq("")
      expect(page.cookies).to be_empty
      expect(page.cookies('https://www.example.com')).to contain_exactly(include(
        'name' => 'example-cookie',
        'value' => 'best',
        'domain' => 'www.example.com',
        'path' => '/',
        'expires' => -1,
        'size' => 18,
        'httpOnly' => false,
        'secure' => true,
        'session' => true,
      ))
    end

    it_fails_firefox 'should set cookies from a frame' do
      sinatra.get('/empty-frame.html') { "<iframe src='http://127.0.0.1:4567/empty.html'>" }
      page.goto('http://localhost:4567/empty-frame.html')
      page.set_cookie(name: 'localhost-cookie', value: 'best')
      page.set_cookie(
        name: '127-cookie',
        value: 'worst',
        url: 'http://127.0.0.1:4567/empty.html',
      )
      expect(page.evaluate("document.cookie")).to eq('localhost-cookie=best')
      expect(page.frames[1].evaluate("document.cookie")).to eq('')
      expect(page.cookies).to contain_exactly(include(
        'name' => 'localhost-cookie',
        'value' => 'best',
        'domain' => 'localhost',
        'path' => '/',
        'expires' => -1,
        'size' => 20,
        'httpOnly' => false,
        'secure' => false,
        'session' => true,
      ))
      expect(page.cookies("http://127.0.0.1:4567/empty.html")).to contain_exactly(include(
        'name' => '127-cookie',
        'value' => 'worst',
        'domain' => '127.0.0.1',
        'path' => '/',
        'expires' => -1,
        'size' => 15,
        'httpOnly' => false,
        'secure' => false,
        'session' => true,
      ))
    end

    #   itFailsFirefox(
    #     'should set secure same-site cookies from a frame',
    #     async () => {
    #       const {
    #         httpsServer,
    #         puppeteer,
    #         defaultBrowserOptions,
    #       } = getTestState();

    #       const browser = await puppeteer.launch({
    #         ...defaultBrowserOptions,
    #         ignoreHTTPSErrors: true,
    #       });

    #       const page = await browser.newPage();

    #       try {
    #         await page.goto(httpsServer.PREFIX + '/grid.html');
    #         await page.evaluate<(src: string) => Promise<void>>((src) => {
    #           let fulfill;
    #           const promise = new Promise<void>((x) => (fulfill = x));
    #           const iframe = document.createElement('iframe');
    #           document.body.appendChild(iframe);
    #           iframe.onload = fulfill;
    #           iframe.src = src;
    #           return promise;
    #         }, httpsServer.CROSS_PROCESS_PREFIX);
    #         await page.setCookie({
    #           name: '127-same-site-cookie',
    #           value: 'best',
    #           url: httpsServer.CROSS_PROCESS_PREFIX,
    #           sameSite: 'None',
    #         });

    #         expect(await page.frames()[1].evaluate('document.cookie')).toBe(
    #           '127-same-site-cookie=best'
    #         );
    #         expect(await page.cookies(httpsServer.CROSS_PROCESS_PREFIX)).toEqual([
    #           {
    #             name: '127-same-site-cookie',
    #             value: 'best',
    #             domain: '127.0.0.1',
    #             path: '/',
    #             expires: -1,
    #             size: 24,
    #             httpOnly: false,
    #             sameSite: 'None',
    #             secure: true,
    #             session: true,
    #           },
    #         ]);
    #       } finally {
    #         await page.close();
    #         await browser.close();
    #       }
    #     }
    #   );
    # });
  end

  describe 'Page#delete_cookie' do
    it 'should work' do
      page.goto('http://127.0.0.1:4567/empty.html')
      page.set_cookie(
        {
          name: 'cookie1',
          value: '1',
        },
        {
          name: 'cookie2',
          value: '2',
        },
        {
          name: 'cookie3',
          value: '3',
        },
      )
      expect(page.evaluate("document.cookie")).to eq("cookie1=1; cookie2=2; cookie3=3")
      page.delete_cookie(name: "cookie2")
      expect(page.evaluate("document.cookie")).to eq("cookie1=1; cookie3=3")
    end
  end
end
