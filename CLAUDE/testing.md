# Testing Strategy

This document describes the testing approach for puppeteer-ruby.

## Test Organization

```
spec/
├── integration/              # Browser automation tests (type: :puppeteer)
│   ├── page_spec.rb
│   ├── element_handle_spec.rb
│   ├── click_spec.rb
│   └── ...
├── puppeteer/                # Unit tests (no browser required)
│   ├── devices_spec.rb
│   ├── launcher_spec.rb
│   └── ...
├── assets/                   # Test HTML/JS/CSS files
├── golden_matcher.rb         # Screenshot comparison matcher
├── spec_helper.rb            # RSpec configuration
└── utils.rb                  # Test utilities
```

## Integration Tests

### Basic Structure

Integration tests use `type: :puppeteer` metadata which is automatically applied to files in `spec/integration/`:

```ruby
RSpec.describe 'Page#goto' do
  # This file is in spec/integration/, so type: :puppeteer is applied

  it 'navigates to a URL' do
    page.goto('https://example.com')
    expect(page.title).to eq('Example Domain')
  end
end
```

### Available Helpers

The `type: :puppeteer` metadata provides these helpers:

| Helper | Description |
|--------|-------------|
| `page` | Current `Puppeteer::Page` instance |
| `browser` | Browser instance (requires `puppeteer: :browser` metadata) |
| `browser_context` | BrowserContext (requires `browser_context: :incognito`) |
| `headless?` | Whether running in headless mode |
| `default_launch_options` | Launch options used for current test |

### Test with Sinatra Server

For tests requiring a web server, use `sinatra: true` metadata:

```ruby
RSpec.describe 'Page#goto', sinatra: true do
  it 'navigates to local server' do
    sinatra.get('/hello') { 'Hello World' }

    page.goto("#{server_prefix}/hello")
    expect(page.content).to include('Hello World')
  end
end
```

Sinatra helpers:

| Helper | Description |
|--------|-------------|
| `sinatra` | Sinatra app instance |
| `server_prefix` | `http://localhost:4567` |
| `server_cross_process_prefix` | `http://127.0.0.1:4567` |
| `server_empty_page` | `http://localhost:4567/empty.html` |

### Test with Browser Instance

For tests that need direct browser access:

```ruby
RSpec.describe 'Browser', puppeteer: :browser do
  it 'creates new pages' do
    page1 = browser.new_page
    page2 = browser.new_page
    expect(browser.pages.length).to eq(2)
  end
end
```

### Incognito Context Tests

```ruby
RSpec.describe 'BrowserContext', browser_context: :incognito do
  it 'has isolated cookies' do
    browser_context.set_cookie(name: 'test', value: 'value')
    # Cookies are isolated to this context
  end
end
```

## Running Tests

### Basic Commands

```bash
# Run all tests
bundle exec rspec

# Run specific file
bundle exec rspec spec/integration/page_spec.rb

# Run specific test by line number
bundle exec rspec spec/integration/page_spec.rb:42

# Run with documentation format
bundle exec rspec --format documentation
```

### Chrome Configuration

```bash
# Run with custom Chrome path
PUPPETEER_EXECUTABLE_PATH_RSPEC=/path/to/chrome bundle exec rspec

# Run with Chrome channel
PUPPETEER_CHANNEL_RSPEC=chrome-beta bundle exec rspec
```

### Debug Mode

```bash
# Non-headless mode (see the browser)
DEBUG=1 bundle exec rspec spec/integration/page_spec.rb

# With debug output
DEBUG=1 bundle exec rspec spec/integration/page_spec.rb 2>&1 | tee test.log
```

### Container/CI Mode

```bash
# Add --no-sandbox flag
PUPPETEER_NO_SANDBOX_RSPEC=true bundle exec rspec
```

### Firefox Testing [DEPRECATED]

> **Planned for removal**: Firefox support will be removed in a future version. Firefox automation will move to [puppeteer-bidi](https://github.com/YusukeIwaki/puppeteer-bidi).

While Firefox support is still present:

```bash
# Run with Firefox
PUPPETEER_PRODUCT_RSPEC=firefox bundle exec rspec spec/integration/

# Check if pending Firefox tests now pass
PENDING_CHECK=true PUPPETEER_PRODUCT_RSPEC=firefox bundle exec rspec
```

Use `it_fails_firefox` for tests that don't work on Firefox:

```ruby
RSpec.describe 'Chrome-specific features' do
  it_fails_firefox 'uses Chrome DevTools extension' do
    # Skipped on Firefox, runs on Chrome
  end
end
```

## Screenshot Testing

### Golden Matcher

Use `match_golden` matcher for screenshot comparisons:

```ruby
RSpec.describe 'Page#screenshot' do
  it 'captures page screenshot' do
    page.goto(server_empty_page)
    screenshot = page.screenshot

    expect(screenshot).to match_golden('empty-page.png')
  end
end
```

Golden images are stored in `spec/golden/`.

### Updating Golden Images

When intentionally changing visual output:

```bash
# Remove old golden and re-run test to generate new one
rm spec/golden/empty-page.png
bundle exec rspec spec/integration/screenshot_spec.rb
```

## Writing New Tests

### Guidelines

1. **One assertion per test when possible** - Easier to identify failures
2. **Use descriptive test names** - Should read like documentation
3. **Clean up resources** - Close pages, restore state in `after` blocks
4. **Minimize flakiness** - Use explicit waits, not sleeps

### Example Test Pattern

```ruby
RSpec.describe 'ElementHandle#click', sinatra: true do
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

  it 'triggers click event' do
    events = []
    page.evaluate(<<~JS)
      document.querySelector('button').addEventListener('click', () => {
        window.clickEvent = true;
      });
    JS

    page.click('button')

    expect(page.evaluate('() => window.clickEvent')).to eq(true)
  end
end
```

## CI Configuration

Tests run on GitHub Actions with matrix of:

- Ruby versions: 2.7, 3.0, 3.1, 3.2, 3.3, 3.4
- Environments: Ubuntu with Chrome, Alpine with Chromium
- Firefox tests (deprecated, will be removed)

See `.github/workflows/ci.yml` for details.

### Retry Strategy

CI uses two-pass retry:

```yaml
- name: Run RSpec (initial pass)
  run: bundle exec rspec --failure-exit-code 0

- name: Run RSpec (retry failures)
  run: DEBUG=1 bundle exec rspec --only-failures
```

This handles flaky tests while still catching real failures.

## Debugging Tips

### See What's Happening

```bash
# Run with visible browser
DEBUG=1 bundle exec rspec spec/integration/page_spec.rb

# Add screenshots for debugging
page.screenshot(path: 'debug.png')

# Log page content
puts page.content
```

### Slow Down Execution

```ruby
# In spec_helper.rb or individual test
Puppeteer.launch(slow_mo: 100) do |browser|
  # Actions are slowed by 100ms each
end
```

### Inspect CDP Messages

```bash
# Enable CDP debug logging
DEBUG=1 bundle exec rspec 2>&1 | grep -E "(SEND|RECV)"
```
