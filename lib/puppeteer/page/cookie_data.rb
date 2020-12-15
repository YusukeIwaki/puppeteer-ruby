class Puppeteer::Page
  class CookieData
    # name <string>
    # value <string>
    # domain <string>
    # path <string>
    # expires <number> Unix time in seconds.
    # size <number>
    # httpOnly <boolean>
    # secure <boolean>
    # session <boolean>
    # sameSite <"Strict"|"Lax"|"Extended"|"None">
    def initialize(name:, value:, domain:, path:, expires:, size:, http_only:, secure:, session:, same_site: nil)
      @name = name
      @value = value
      @domain = domain
      @path = path
      @expires = expires
      @size = size
      @http_only = http_only
      @secure = secure
      @session = session
      @same_site = same_site
    end

    attr_reader :name, :value, :domain, :path, :expires, :size, :same_site

    def http_only?
      @http_only
    end

    def secure?
      @secure
    end

    def session?
      @session
    end

    def hash
      {
        name: @name,
        value: @value,
        domain: @domain,
        path: @path,
        expires: @expires,
        size: @size,
        http_only: @http_only,
        secure: @secure,
        session: @session,
        same_site: @same_site,
      }
    end

    alias_method :to_h, :hash
    alias_method :to_hash, :hash

    def ==(other)
      hash == other.hash
    end

    def eql?(other)
      self.class == other.class && hash.eql?(other.hash)
    end
  end
end
