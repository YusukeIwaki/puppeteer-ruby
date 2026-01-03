# Puppeteer-Ruby Development Guide

This document provides essential guidance for AI agents working on the puppeteer-ruby codebase.

## Project Overview

puppeteer-ruby is a Ruby port of [Puppeteer](https://pptr.dev/), the Node.js browser automation library. It uses the Chrome DevTools Protocol (CDP) to automate Chrome/Chromium browsers.

> **Note on Firefox Support**: Firefox support currently exists in the codebase but is planned for removal. Firefox automation will be handled by [puppeteer-bidi](https://github.com/YusukeIwaki/puppeteer-bidi), which uses the WebDriver BiDi protocol. New development should focus on Chrome/CDP only.

### Core Principles

1. **CDP Protocol Focus**: All browser automation is done via CDP
2. **Chrome Specialization**: Focused on Chrome/Chromium automation (Firefox support is deprecated)
3. **API Compatibility**: Follow Puppeteer's API design closely, but use Ruby idioms

## Quick Reference

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/integration/page_spec.rb

# Run in debug mode (non-headless)
DEBUG=1 bundle exec rspec spec/integration/page_spec.rb
```

### Key Environment Variables

| Variable | Description |
|----------|-------------|
| `PUPPETEER_EXECUTABLE_PATH_RSPEC` | Custom browser executable path |
| `PUPPETEER_CHANNEL_RSPEC` | Chrome channel (e.g., `chrome`, `chrome-beta`) |
| `DEBUG` | Set to `1` for debug output |
| `PUPPETEER_NO_SANDBOX_RSPEC` | Add `--no-sandbox` flag (for containers) |
| `PUPPETEER_PRODUCT_RSPEC` | **[DEPRECATED]** Browser: `chrome` (default) or `firefox` |

### Code Quality

```bash
# Run RuboCop
bundle exec rubocop

# Auto-fix RuboCop issues
bundle exec rubocop -a
```

## Architecture

The codebase follows a straightforward architecture:

```
lib/puppeteer/
├── puppeteer.rb          # Main entry point (Puppeteer.launch, Puppeteer.connect)
├── browser.rb            # Browser instance management
├── browser_context.rb    # Incognito/default context
├── page.rb               # Page API (main user-facing class)
├── frame.rb              # Frame handling
├── element_handle.rb     # DOM element operations
├── js_handle.rb          # JavaScript object handles
├── connection.rb         # WebSocket connection to browser
├── cdp_session.rb        # CDP session management
├── keyboard.rb           # Keyboard input simulation
├── mouse.rb              # Mouse input simulation
└── ...
```

### Key Components

- **Connection**: Manages WebSocket connection to the browser's DevTools
- **CDPSession**: Sends CDP commands and receives events
- **FrameManager**: Tracks frames and their execution contexts
- **NetworkManager**: Handles request interception and network events
- **LifecycleWatcher**: Waits for navigation events (load, DOMContentLoaded, etc.)

## Code Standards

### Ruby Version & Style

- Minimum Ruby version: 2.6
- Follow RuboCop rules defined in `.rubocop.yml`
- Use explicit keyword arguments for public APIs

### API Naming Conventions

JavaScript Puppeteer methods use camelCase, Ruby methods use snake_case:

| Puppeteer (JS) | puppeteer-ruby |
|----------------|----------------|
| `page.waitForSelector()` | `page.wait_for_selector` |
| `page.setContent()` | `page.content=` or `page.set_content` |
| `element.boundingBox()` | `element.bounding_box` |
| `browser.newPage()` | `browser.new_page` |

### Error Classes

All custom errors inherit from `Puppeteer::Error`:

```ruby
module Puppeteer
  class Error < StandardError; end
  class TimeoutError < Error; end
  class FrameNotFoundError < Error; end
  # etc.
end
```

## Testing Strategy

### Test Types

- **Unit tests**: `spec/puppeteer/` - Test individual classes without browser
- **Integration tests**: `spec/integration/` - Test with real browser

### Integration Test Setup

Integration tests use RSpec metadata:

```ruby
RSpec.describe 'Page', type: :puppeteer do
  it 'navigates to a page' do
    page.goto('https://example.com')
    expect(page.title).to eq('Example Domain')
  end
end
```

The `type: :puppeteer` metadata automatically:
- Launches Chrome before each test
- Provides `page` helper method
- Closes browser after test

### Firefox Tests [DEPRECATED]

> **Planned for removal**: Firefox support will be removed in a future version.

Currently, `it_fails_firefox` is used for tests that don't work on Firefox:

```ruby
it_fails_firefox 'uses Chrome-specific feature' do
  # Skipped on Firefox, runs on Chrome
end
```

To run tests on Firefox (while still supported):
```bash
PUPPETEER_PRODUCT_RSPEC=firefox bundle exec rspec spec/integration/
```

## Porting from Puppeteer

When implementing new features, reference the TypeScript Puppeteer source:

1. Find the corresponding TypeScript file in [puppeteer/puppeteer](https://github.com/puppeteer/puppeteer)
2. Understand the CDP calls being made
3. Implement in Ruby following existing patterns
4. Port the relevant tests
5. Update `docs/api_coverage.md`

### CDP Command Pattern

```ruby
# TypeScript Puppeteer
await this._client.send('Page.navigate', { url });

# Ruby equivalent
@client.send_message('Page.navigate', url: url)
```

## Concurrency Model

### Current State (concurrent-ruby)

Currently, puppeteer-ruby uses Thread-based concurrency with `concurrent-ruby`:

- `Concurrent::Promises.resolvable_future` - For async operations that complete later
- `Concurrent::Promises.future` - For running operations in background
- `Concurrent::Promises.zip` - For waiting on multiple promises
- `Concurrent::Promises.any` - For waiting on any of multiple promises
- `Concurrent::Hash` - Thread-safe hash for callbacks and sessions

### Planned Migration (socketry/async)

The project is planning to migrate from concurrent-ruby to socketry/async:

- **Target**: Fiber-based concurrency using `Async` gem
- **Minimum Ruby Version**: Will be raised to Ruby 3.2
- **Benefits**: Simpler concurrency model, no mutex locks needed, better alignment with JavaScript async/await patterns

When implementing new features, consider the upcoming migration:
- Avoid adding new concurrent-ruby dependencies where possible
- Design with Fiber-based concurrency in mind

### Async Method Pattern (Current)

```ruby
class Page
  # Synchronous version
  def wait_for_selector(selector, timeout: nil)
    # ...
  end

  # Async version (returns Concurrent::Promises::Future)
  define_async_method :async_wait_for_selector
end
```

## Development Workflow

### Before Submitting Changes

1. Run tests: `bundle exec rspec`
2. Run RuboCop: `bundle exec rubocop`
3. Update `docs/api_coverage.md` if adding new API methods

### Version Updates

Version is defined in `lib/puppeteer/version.rb`. GitHub Actions automatically publishes to RubyGems when a version tag is pushed.

## Detailed Documentation

For in-depth information on specific topics, see the [CLAUDE/](./CLAUDE/) directory:

- [README.md](./CLAUDE/README.md) - Documentation index
- [architecture.md](./CLAUDE/architecture.md) - Detailed architecture overview
- [testing.md](./CLAUDE/testing.md) - Testing strategies and patterns
- [cdp_protocol.md](./CLAUDE/cdp_protocol.md) - CDP protocol details
- [concurrency.md](./CLAUDE/concurrency.md) - Concurrency patterns
- [porting_puppeteer.md](./CLAUDE/porting_puppeteer.md) - Guide for porting from TypeScript
- [browser_differences.md](./CLAUDE/browser_differences.md) - **[DEPRECATED]** Firefox differences
