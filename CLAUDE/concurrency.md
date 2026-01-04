# Concurrency Model

This document explains the concurrency architecture in puppeteer-ruby using `socketry/async`.

## Current State: socketry/async

puppeteer-ruby uses Fiber-based concurrency with the `socketry/async` gem (version 2.35.1+).

### Key Components

| Component | Purpose |
|-----------|---------|
| `Async::Promise` | Promise that can be resolved/rejected later |
| `Puppeteer::AsyncUtils` | Utility module for async operations |
| `Puppeteer::ReactorRunner` | Dedicated Async reactor thread for sync API |

### AsyncUtils Module

Located in `lib/puppeteer/async_utils.rb`:

```ruby
module Puppeteer::AsyncUtils
  # Wait for all promises to complete (like Promise.all)
  def await_promise_all(*tasks)
    # ...
  end

  # Wait for first promise to complete (like Promise.race)
  def await_promise_race(*tasks)
    # ...
  end

  # Timeout wrapper
  def async_timeout(timeout_ms, &block)
    # ...
  end

  # Sleep helper that works in Async context
  def sleep_seconds(seconds)
    # ...
  end
end
```

### ReactorRunner

`ReactorRunner` manages a dedicated Async reactor thread and provides a bridge between synchronous API calls and the Async context:

```ruby
# From lib/puppeteer/reactor_runner.rb

# ReactorRunner runs Async operations in a dedicated thread
runner = Puppeteer::ReactorRunner.new

# Wrap an object to proxy calls through the reactor
browser = runner.wrap(actual_browser)

# Calls are executed in the Async reactor context
browser.new_page  # Runs in reactor thread
```

Key features:
- Dedicated thread running Async reactor
- Proxies method calls into reactor context
- Handles result unwrapping and error propagation
- `wait_until_idle` for graceful shutdown

### Threading Model

```
Main Thread                   Reactor Thread (Async)
    │                              │
    ├── sync method call ─────────►│
    │                              │ (execute in Async context)
    │   ◄────────────────────────── result
    │                              │
    ├── browser.close ────────────►│
    │                              │ wait_until_idle
    │   ◄────────────────────────── cleanup complete
    │                              │
```

### Promise Patterns

#### Creating and Resolving Promises

```ruby
# Create a promise
promise = Async::Promise.new

# Resolve with value
promise.resolve(result)

# Reject with error
promise.reject(error)

# Wait for result
result = promise.wait
```

#### Waiting for Events

```ruby
# Common pattern for waiting on events
promise = Async::Promise.new.tap do |p|
  page.once('load') { p.resolve(true) }
end

# Later, wait for the event
promise.wait
```

#### Running Multiple Operations

```ruby
# Wait for all (like Promise.all)
Puppeteer::AsyncUtils.await_promise_all(
  page.async_goto('https://example1.com'),
  page.async_goto('https://example2.com'),
)

# Wait for any (like Promise.race)
Puppeteer::AsyncUtils.await_promise_race(
  timeout_promise,
  navigation_promise,
)
```

#### Timeout Handling

```ruby
# With timeout (milliseconds)
Puppeteer::AsyncUtils.async_timeout(5000) do
  slow_operation
end
# Raises Async::TimeoutError if exceeded
```

### Async Method Pattern

```ruby
# Define synchronous method
def wait_for_selector(selector, timeout: nil)
  # Implementation...
end

# Generate async version that returns Async task
define_async_method :async_wait_for_selector
```

Usage:

```ruby
# Synchronous (blocks)
element = page.wait_for_selector('button')

# Asynchronous (returns Async task)
task = page.async_wait_for_selector('button')
# Do other work...
element = task.wait
```

## Key Implementation Files

| File | Description |
|------|-------------|
| `lib/puppeteer/async_utils.rb` | Core async utility functions |
| `lib/puppeteer/reactor_runner.rb` | Reactor thread management |
| `lib/puppeteer/define_async_method.rb` | Async method generation |
| `lib/puppeteer/connection.rb` | WebSocket with async messaging |
| `lib/puppeteer/lifecycle_watcher.rb` | Navigation wait logic |

## Guidelines for New Code

### Do

- Use `Async::Promise` for deferred results
- Use `AsyncUtils` methods for combining promises
- Keep synchronous and async logic separate
- Handle `Async::TimeoutError` for timeout operations
- Use `Mutex` for shared state between threads

### Don't

- Block the reactor thread with synchronous I/O
- Create nested `Async` blocks unnecessarily
- Ignore promise rejections
- Use `sleep` directly (use `AsyncUtils.sleep_seconds`)

### Example: Async-Ready Code

```ruby
class MyComponent
  def perform_operation(timeout: 30000)
    promise = Async::Promise.new

    listener_id = @emitter.add_event_listener('complete') do |result|
      promise.resolve(result) unless promise.resolved?
    end

    begin
      Puppeteer::AsyncUtils.async_timeout(timeout) do
        promise.wait
      end
    ensure
      @emitter.remove_event_listener(listener_id)
    end
  end
end
```

## Resources

- [socketry/async documentation](https://github.com/socketry/async)
- [Async::Promise](https://github.com/socketry/async)
- [Ruby Fiber scheduler](https://ruby-doc.org/core-3.1.0/Fiber/Scheduler.html)
