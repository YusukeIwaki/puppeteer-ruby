# Browser Differences [DEPRECATED]

> **This document is deprecated**: Firefox support will be removed from puppeteer-ruby. Firefox automation will be handled by [puppeteer-bidi](https://github.com/YusukeIwaki/puppeteer-bidi) which uses the WebDriver BiDi protocol.
>
> **For new development**: Focus only on Chrome/Chromium. Do not add new Firefox-specific code.

## Current State

puppeteer-ruby currently supports both Chrome/Chromium and Firefox through CDP, but Firefox support is planned for removal.

## Firefox-Related Files (To Be Removed)

| File | Purpose |
|------|---------|
| `lib/puppeteer/firefox_target_manager.rb` | Firefox target management |
| `lib/puppeteer/launcher/firefox.rb` | Firefox-specific launch |

## Testing on Firefox (While Still Supported)

```bash
# Run integration tests on Firefox
PUPPETEER_PRODUCT_RSPEC=firefox bundle exec rspec spec/integration/

# Check if pending tests now pass
PENDING_CHECK=true PUPPETEER_PRODUCT_RSPEC=firefox bundle exec rspec
```

## `it_fails_firefox` Helper

Used to mark tests that don't work on Firefox:

```ruby
it_fails_firefox 'uses Chrome-specific feature' do
  # Skipped on Firefox, runs on Chrome
end
```

## Known Firefox Differences

These differences exist in the current codebase but will become irrelevant after Firefox support is removed:

- Different target attachment model
- Some CDP commands not implemented
- Different event timing
- PDF generation differences

## Migration Path

1. Firefox support will be removed from this library
2. Users needing Firefox automation should migrate to [puppeteer-bidi](https://github.com/YusukeIwaki/puppeteer-bidi)
3. puppeteer-ruby will focus exclusively on Chrome/CDP
