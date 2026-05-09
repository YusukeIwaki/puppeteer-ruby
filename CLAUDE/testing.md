# Testing Strategy

This document describes the testing approach for puppeteer-ruby.

## Test Organization

```
spec/
├── puppeteer/                # RSpec unit tests (no browser required)
├── assets/                   # Upstream-compatible HTML/JS/CSS/image fixtures
├── support/                  # Shared server and RSpec support code
├── spec_helper.rb            # RSpec configuration for unit tests
└── utils.rb                  # Shared browser-test utilities

smartest/
├── integration/              # Smartest browser automation tests
├── fixtures/                 # Shared browser and test-server fixtures
├── matchers/                 # Browser-test matchers, including golden matching
├── support/                  # Smartest compatibility DSL and server adapters
└── test_helper.rb            # Smartest configuration
```

Unit tests stay on RSpec. Browser-driven integration tests run on Smartest.

## Integration Tests

### Basic Structure

Integration tests live in `smartest/integration/**/*_test.rb` and require `test_helper`:

```ruby
require 'test_helper'

describe 'Page#goto' do
  it 'navigates to a URL' do
    with_test_state do |page:, **|
      page.goto('https://example.com')
      expect(page.title).to eq('Example Domain')
    end
  end
end
```

The compatibility DSL keeps upstream-style `describe`, `context`, `it`, `before`, `after`, `let`, `subject`, and common RSpec matchers available while Smartest supplies fixtures and execution.

### Available Helpers

| Helper | Description |
|--------|-------------|
| `with_test_state` | Creates an isolated page/context and cleans it up after the block |
| `page` | Current `Puppeteer::Page` when the test uses metadata-backed state |
| `browser` | Shared browser instance, or metadata-backed browser state |
| `browser_context` / `context` | Current `BrowserContext` when available |
| `server` / `https_server` | Shared HTTP/HTTPS test servers |
| `sinatra` | Route adapter for the shared HTTP server |
| `server_prefix` | HTTP server prefix |
| `server_cross_process_prefix` | Cross-process HTTP server prefix |
| `server_empty_page` | Empty page URL on the shared server |
| `asset_path(relative_path)` | Absolute path under `spec/assets` |
| `headless?` | Whether tests run headless |
| `default_launch_options` | Launch options used for browser tests |

### Test with Local Server

For tests requiring local routes, use `sinatra: true` metadata and the `sinatra` adapter:

```ruby
describe 'Page#goto', sinatra: true do
  it 'navigates to local server' do
    sinatra.get('/hello') { 'Hello World' }

    page.goto("#{server_prefix}/hello")
    expect(page.content).to include('Hello World')
  end
end
```

### Test with Direct Browser Access

For tests that need direct browser access, use `puppeteer: :browser` metadata:

```ruby
describe 'Browser', puppeteer: :browser do
  it 'creates new pages' do
    page1 = browser.new_page
    page2 = browser.new_page
    expect(browser.pages.length).to eq(2)
  ensure
    page1&.close
    page2&.close
  end
end
```

### Incognito Context Tests

```ruby
describe 'BrowserContext', browser_context: :incognito do
  it 'has isolated cookies' do
    browser_context.set_cookie(name: 'test', value: 'value')
  end
end
```

### OOPIF Tests

For tests requiring cross-process iframes, use `enable_site_per_process_flag: true`:

```ruby
it 'clicks button in cross-process iframe', enable_site_per_process_flag: true do
  with_test_state do |page:, server:, **|
    page.goto(server.empty_page)
    attach_frame(page, 'frame-id', "#{server.cross_process_prefix}/input/button.html")

    frame = page.frames[1]
    frame.click('button')
  end
end
```

This metadata launches an isolated browser with `--site-per-process` and `--host-rules=MAP * 127.0.0.1`.

## Running Tests

### Basic Commands

```bash
# Run RSpec unit tests and Smartest browser tests
bundle exec rake

# Run RSpec unit tests only
bundle exec rspec

# Run Smartest browser tests only
bundle exec smartest

# Run a specific Smartest file
bundle exec smartest smartest/integration/page_test.rb

# Run a specific Smartest test by line number
bundle exec smartest smartest/integration/page_test.rb:42

# Run Smartest with profiling disabled
bundle exec smartest --profile 0 smartest/integration/page_test.rb
```

### Chrome Configuration

```bash
# Run Smartest with a custom Chrome path
PUPPETEER_EXECUTABLE_PATH_SMARTEST=/path/to/chrome bundle exec smartest

# Run Smartest with a Chrome channel
PUPPETEER_CHANNEL_SMARTEST=chrome-beta bundle exec smartest
```

The legacy `_RSPEC` environment variable names are still accepted by Smartest for compatibility with existing scripts.

### Debug Mode

```bash
# Non-headless mode and CDP debug logging
DEBUG=1 bundle exec smartest smartest/integration/page_test.rb

# Save debug output
DEBUG=1 bundle exec smartest smartest/integration/page_test.rb 2>&1 | tee test.log
```

### Container/CI Mode

```bash
# Add --no-sandbox flag
PUPPETEER_NO_SANDBOX_SMARTEST=true bundle exec smartest
```

## Screenshot Testing

### Golden Matcher

Use `match_golden` / `be_golden` for screenshot comparisons:

```ruby
describe 'Page#screenshot' do
  it 'captures page screenshot' do
    page.goto(server_empty_page)
    screenshot = page.screenshot

    expect(screenshot).to match_golden('screenshot-empty-page.png')
  end
end
```

Golden images are stored in `spec/integration/golden-chromium/`.

### Updating Golden Images

When intentionally changing visual output:

```bash
# Remove old golden and re-run the relevant Smartest test to generate a new one
rm spec/integration/golden-chromium/screenshot-empty-page.png
bundle exec smartest smartest/integration/screenshot_test.rb
```

## Writing New Tests

### Guidelines

1. Keep upstream-equivalent browser tests in `smartest/integration/*_test.rb`.
2. Keep non-browser unit tests in `spec/puppeteer/*_spec.rb`.
3. Use `with_test_state` for explicit browser/page setup when possible.
4. Use Smartest fixtures and matchers instead of per-test browser bootstrapping.
5. Clean up resources created outside `with_test_state`.
6. Minimize flakiness with explicit waits instead of sleeps.

### Example Test Pattern

```ruby
describe 'ElementHandle#click', sinatra: true do
  before do
    sinatra.get('/button') do
      <<~HTML
        <button onclick="window.clicked = true">Click me</button>
      HTML
    end
    page.goto("#{server_prefix}/button")
  end

  it 'clicks the button' do
    button = page.query_selector('button')
    button.click

    result = page.evaluate('() => window.clicked')
    expect(result).to eq(true)
  end
end
```

## CI Configuration

GitHub Actions run both suites:

- `bundle exec rspec --profile 10 --format documentation` for unit tests
- `bundle exec smartest` for browser integration tests

The matrix covers Ruby 3.2, 3.3, 3.4 with latest Chrome, plus Alpine with Chromium.

## Debugging Tips

### See What's Happening

```bash
# Run with visible browser and CDP logs
DEBUG=1 bundle exec smartest smartest/integration/page_test.rb

# Add screenshots for debugging
page.screenshot(path: 'debug.png')

# Log page content
puts page.content
```

### Slow Down Execution

```ruby
Puppeteer.launch(slow_mo: 100) do |browser|
  # Actions are slowed by 100ms each
end
```

### Inspect CDP Messages

```bash
DEBUG=1 bundle exec smartest 2>&1 | grep -E "(SEND|RECV)"
```
