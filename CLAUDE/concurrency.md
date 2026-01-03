# Concurrency Model

This document explains the concurrency architecture in puppeteer-ruby and the planned migration path.

## Current State: concurrent-ruby

puppeteer-ruby currently uses Thread-based concurrency with the `concurrent-ruby` gem.

### Key Components

| Component | Purpose |
|-----------|---------|
| `Concurrent::Promises.resolvable_future` | Promise that can be fulfilled later |
| `Concurrent::Promises.future` | Run operation in background thread |
| `Concurrent::Promises.zip` | Wait for multiple promises |
| `Concurrent::Promises.any` | Wait for any of multiple promises |
| `Concurrent::Promises.delay` | Deferred execution |
| `Concurrent::Promises.schedule` | Scheduled execution (timeout) |
| `Concurrent::Hash` | Thread-safe hash for callbacks |

### Threading Model

```
Main Thread                   WebSocket Thread
    │                              │
    ├── send_message() ──────────►│
    │                              │ (process message)
    │   ◄────────────────────────── (response)
    │                              │
    ├── on('event') ──────────────►│
    │                              │ (receives event)
    │   ◄────────────────────────── callback execution
    │                              │
```

### Synchronization Patterns

#### Waiting for Response (CDPSession)

```ruby
# From lib/puppeteer/cdp_session.rb
def send_message(method, params = {})
  id = raw_send(message: { method: method, params: params })
  promise = Concurrent::Promises.resolvable_future
  @callbacks[id] = promise

  # Wait for response with timeout
  promise.value!(timeout_in_seconds)
end

# When response arrives:
def handle_message(message)
  if message['id']
    promise = @callbacks.delete(message['id'])
    promise&.fulfill(message['result'])
  end
end
```

#### Waiting for Events

```ruby
# Common pattern for waiting on events
promise = Concurrent::Promises.resolvable_future.tap do |future|
  page.once('load') { future.fulfill(true) }
end

# Later, wait for the event
promise.value!
```

#### Running Multiple Operations

```ruby
# Wait for all
Concurrent::Promises.zip(promise1, promise2, promise3).value!

# Wait for any
Concurrent::Promises.any(promise1, promise2).value!
```

#### Scheduled Timeout

```ruby
# From lib/puppeteer/wait_task.rb
Concurrent::Promises.schedule(timeout / 1000.0) do
  terminate(timeout_error) unless @timeout_cleared
end
```

### Async Method Pattern

```ruby
# Define synchronous method
def wait_for_selector(selector, timeout: nil)
  # Implementation...
end

# Generate async version that returns Future
define_async_method :async_wait_for_selector
```

Usage:

```ruby
# Synchronous (blocks)
element = page.wait_for_selector('button')

# Asynchronous (returns Future)
future = page.async_wait_for_selector('button')
# Do other work...
element = future.value!
```

## Planned Migration: socketry/async

The project is planning to migrate to Fiber-based concurrency using the `socketry/async` gem.

### Why Migrate?

1. **Simpler Mental Model**: Fibers are cooperative, no race conditions
2. **No Mutex Needed**: Single-threaded execution within Fiber context
3. **Better JavaScript Alignment**: Mirrors JavaScript async/await patterns
4. **Modern Ruby Support**: Leverages Ruby 3.x Fiber scheduler

### Target Architecture

```ruby
# With Async gem
Async do
  browser = Puppeteer.launch.wait
  page = browser.new_page.wait

  # Concurrent operations
  [
    page.goto('https://example1.com'),
    page.goto('https://example2.com'),
  ].each(&:wait)

  browser.close.wait
end
```

### Migration Strategy

1. **Minimum Ruby Version**: Raise to 3.2 (required for Fiber scheduler)
2. **Two-Layer Architecture**:
   - Core layer: Async operations returning `Async::Task`
   - Upper layer: Synchronous wrappers that call `.wait`
3. **Gradual Migration**: Convert components one at a time

### Example: Before and After

```ruby
# Before (concurrent-ruby)
class Connection
  def send_message(method, params)
    event = Concurrent::Event.new
    @callbacks[id] = ->(r) { @result = r; event.set }
    @socket.write(message)
    event.wait(timeout)
    @result
  end
end

# After (async)
class Connection
  def send_message(method, params)
    Async do |task|
      @pending[id] = task
      @socket.write(message)
      task.sleep(timeout) # or wait for signal
      @pending.delete(id)
    end
  end
end
```

### Key Async Patterns

```ruby
# Basic async block
Async do
  result = some_async_operation.wait
end

# Parallel execution
Async do |task|
  results = [
    task.async { operation1 },
    task.async { operation2 },
  ].map(&:wait)
end

# Timeout
Async do |task|
  task.with_timeout(5) do
    slow_operation.wait
  end
end
```

## Guidelines for New Code

When writing new code, follow these guidelines to prepare for migration:

### Do

- Keep synchronous and async logic separate
- Use clear patterns for waiting/signaling
- Document any threading assumptions
- Write tests that work with both models

### Don't

- Add new concurrent-ruby dependencies if avoidable
- Create complex thread synchronization
- Rely on thread-specific behavior
- Use global mutable state

### Example: Migration-Ready Code

```ruby
class MyComponent
  # Core logic: can be wrapped in Thread or Fiber
  def perform_operation
    send_command
    wait_for_response
    process_result
  end

  private

  # Abstract the waiting mechanism
  def wait_for_response
    @waiter.wait  # Could be Event or Async::Task
  end
end
```

## Testing Concurrency

### Current Tests

Tests generally run synchronously with occasional async patterns:

```ruby
it 'waits for navigation' do
  # This blocks until navigation completes
  page.wait_for_navigation do
    page.click('a')
  end
end
```

### Future Tests (with Async)

```ruby
it 'waits for navigation' do
  Async do
    page.wait_for_navigation do
      page.click('a').wait
    end.wait
  end
end
```

## Resources

- [concurrent-ruby documentation](https://github.com/ruby-concurrency/concurrent-ruby)
- [socketry/async documentation](https://github.com/socketry/async)
- [Ruby Fiber scheduler](https://ruby-doc.org/core-3.1.0/Fiber/Scheduler.html)
