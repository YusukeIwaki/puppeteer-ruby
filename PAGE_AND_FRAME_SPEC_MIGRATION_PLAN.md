# Plan: Porting Puppeteer TypeScript Tests to puppeteer-ruby

## Overview

Port tests from Puppeteer TypeScript repository to puppeteer-ruby:
- `test/src/page.spec.ts` → `spec/integration/page_spec.rb`
- `test/src/frame.spec.ts` → `spec/integration/frame_spec.rb`

Also implement missing methods required by the tests.

---

## Phase 1: Tests for Existing Methods (No Implementation Required)

These tests can be ported directly as the Ruby methods already exist.

### 1.1 Page.waitForResponse Tests (7 tests)
**File:** `spec/integration/page_spec.rb`
**Existing method:** `lib/puppeteer/page.rb:862-879`

Tests to add:
- `should work`
- `should respect timeout`
- `should respect default timeout`
- `should work with predicate`
- `should work with async predicate`
- `should work with no timeout`
- `should be cancellable` (skip if not supported)

### 1.2 Page.waitForFrame Tests (3 tests)
**File:** `spec/integration/page_spec.rb`
**Existing method:** `lib/puppeteer/page.rb:890-918`

Tests to add:
- `should work`
- `should work with a URL predicate`
- `should timeout`

### 1.3 Page.bringToFront Test
**File:** `spec/integration/page_spec.rb`
**Existing method:** `lib/puppeteer/page.rb:947-949`

Test to add:
- `should work`

### 1.4 Page.Events.Console Tests (expand existing)
**File:** `spec/integration/page_spec.rb`
**Existing:** Partial coverage at lines 445-547

Tests to add:
- `should not fail for window object`
- `should trigger correct Log`
- `should have location when fetch fails`
- `should not throw when there are console messages in detached iframes`

### 1.5 Page.reload Tests
**File:** `spec/integration/page_spec.rb`
**Existing method:** `lib/puppeteer/page.rb:741-745`

Tests to add:
- `should work`
- `should enable or disable the cache based on reload params`

### 1.6 Page.client Accessor Test
**File:** `spec/integration/page_spec.rb`
**Existing:** `attr_reader :client` at line 253

Test to add:
- `should return the client instance`

---

## Phase 2: Minor Implementation Changes

### 2.1 Page#off (Event Handler Removal)
**Status:** Marked `~~off~~` in api_coverage.md, but `remove_event_listener` exists in EventCallbackable

**Implementation:** Add alias in `lib/puppeteer/page.rb`:
```ruby
alias_method :off, :remove_event_listener
```

**Update:** `docs/api_coverage.md` - change `~~off~~` to `off`

**Tests to enable:** (currently pending at line 115-132 in page_spec.rb)
- `should correctly fire event handlers as they are added and then removed`
- `should correctly added and removed request events`

### 2.2 Frame#client Accessor
**Status:** `_client` method exists (private convention)

**Implementation:** Add to `lib/puppeteer/frame.rb`:
```ruby
attr_reader :client
```
And assign `@client` in initialize.

**Test to add to frame_spec.rb:**
- `should return the client instance`

### 2.3 Frame#frame_element
**Status:** Not implemented

**Implementation:** Add to `lib/puppeteer/frame.rb`:
```ruby
def frame_element
  return nil if @parent_frame.nil?

  # Get frame owner node from CDP
  response = @frame_manager.client.send_message('DOM.getFrameOwner', frameId: @id)
  node_id = response['backendNodeId']

  @frame_manager.page.main_frame.puppeteer_world.adopt_backend_node(node_id)
rescue => e
  nil
end
```

**Tests to add to frame_spec.rb:**
- `should work`
- `should handle shadow roots`
- `should return nil for main frame`

---

## Phase 3: New Method Implementations

### 3.1 Page#wait_for_network_idle (HIGH PRIORITY)
**Status:** Marked `~~waitForNetworkIdle~~` in api_coverage.md

**Implementation:** Add to `lib/puppeteer/page.rb`:
```ruby
def wait_for_network_idle(idle_time: 500, timeout: nil, concurrent_requests: 0)
  option_timeout = timeout || @timeout_settings.timeout

  network_manager = @frame_manager.network_manager
  inflight_requests = Set.new

  promise = Async::Promise.new
  idle_timer = nil

  on_request = ->(request) {
    inflight_requests.add(request)
    idle_timer&.cancel
  }

  on_response = ->(response) {
    inflight_requests.delete(response.request)
    check_idle = -> {
      if inflight_requests.size <= concurrent_requests
        idle_timer = Async::Task.new {
          Async::Task.current.sleep(idle_time / 1000.0)
          promise.resolve(nil) unless promise.resolved?
        }
      end
    }
    check_idle.call
  }

  request_listener = on('request', &on_request)
  response_listener = on('requestfinished', &on_response)
  failed_listener = on('requestfailed', &on_response)

  begin
    Puppeteer::AsyncUtils.async_timeout(option_timeout, promise).wait
  ensure
    off(request_listener)
    off(response_listener)
    off(failed_listener)
  end
end

define_async_method :async_wait_for_network_idle
```

**Tests to add:**
- `should work`
- `should respect timeout`
- `should respect idleTime`
- `should work with no timeout`
- `should work with aborted requests`
- `should be cancelable` (skip if not supported)

**Test asset:** `spec/assets/networkidle.html` (already exists)

### 3.2 Page#remove_exposed_function
**Status:** Not implemented

**Implementation:** Add to `lib/puppeteer/page.rb`:
```ruby
def remove_exposed_function(name)
  raise ArgumentError, "Function '#{name}' is not exposed" unless @page_bindings.key?(name)

  @page_bindings.delete(name)
  @client.send_message('Runtime.removeBinding', name: name)

  remove_script = "(name) => { delete window[name]; }"
  @frame_manager.frames.each do |frame|
    frame.evaluate(remove_script, name) rescue nil
  end
end
```

**Tests to add:**
- `should work`
- `should throw for non-existent function`

---

## Phase 4: Frame.spec.ts Porting

### 4.1 Tests Using Existing Methods
- `Frame.evaluateHandle should work` (exists)
- `Frame.evaluate should throw for detached frames` (exists)
- `Frame.evaluate allows readonly array to be an argument`
- `Frame.page should retrieve the page from a frame` (exists)
- Frame management tests (13 tests, most exist)

### 4.2 New Tests
- `Frame.client should return the client instance` (after 2.2)
- `Frame.prototype.frameElement should work` (after 2.3)
- `Frame.prototype.frameElement should handle shadow roots`
- `Frame.prototype.frameElement should return ElementHandle in correct world`

---

## Implementation Order

1. **Phase 1** - Port tests for existing methods first (validates test infrastructure)
2. **Phase 2.1** - Add `Page#off` alias (enables pending tests)
3. **Phase 2.2** - Add `Frame#client` accessor
4. **Phase 3.1** - Implement `wait_for_network_idle` (most requested feature)
5. **Phase 2.3** - Implement `Frame#frame_element`
6. **Phase 3.2** - Implement `remove_exposed_function`
7. **Phase 4** - Port remaining frame tests

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/puppeteer/page.rb` | Add `off` alias, `wait_for_network_idle`, `remove_exposed_function` |
| `lib/puppeteer/frame.rb` | Add `client` accessor, `frame_element` method |
| `spec/integration/page_spec.rb` | Add ~25 new tests |
| `spec/integration/frame_spec.rb` | Add ~5 new tests |
| `docs/api_coverage.md` | Update coverage for new methods |

---

## Verification

After each phase:

```bash
# Run specific test file
rbenv exec bundle exec rspec spec/integration/page_spec.rb

# Run RuboCop
bundle exec rubocop lib/puppeteer/page.rb lib/puppeteer/frame.rb

# Run type check
bundle exec steep check

# Run full test suite
rbenv exec bundle exec rspec
```

---

## Test Pattern Reference

Use existing tests as templates:
- `wait_for_request` tests (lines 629-705) for `wait_for_response` pattern
- `expose_function` tests (lines 761-870) for `remove_exposed_function` pattern
- Frame management tests (frame_spec.rb lines 80-250) for frame tests

---

## Existing Test Coverage Summary

### page_spec.rb (1,580 lines, 28 describe blocks)
Already implemented:
- Navigation: `goto`, `Page.Events.Load`, `Page.Events.DOMContentLoaded`
- Page lifecycle: `#close` (5 tests), `Page.Events.Close`
- Permissions: `BrowserContext#override_permissions` (8 tests), `#geolocation=`
- Network: `#offline_mode=`, `Page.waitForRequest` (5 tests), `#cache_enabled`
- Content: `#content=/#set_content` (10 tests), `#bypass_csp=`, `#title`
- Scripting: `#expose_function` (8 tests), Console API handling
- JS execution: `#javascript_enabled=`
- Config: `#user_agent=` (4 tests), `#metrics`, `#url`
- PDF: 3 tests
- Forms: `Page.select`
- Script/style injection: `#add_script_tag` (9 tests), `#add_style_tag` (7 tests)
- Events: `Page.Events.error`, `Page.Events.Popup` (6 tests), `Page.Events.PageError`

### frame_spec.rb (253 lines, 6 describe blocks)
Already implemented:
- `#execution_context`
- `#evaluate_handle`
- `#evaluate` (detached frame error)
- `#page`
- Frame Management (13 tests): nested frames, events, navigation, framesets, shadow DOM, etc.

---

## TypeScript Source References

- Page tests: https://github.com/puppeteer/puppeteer/blob/main/test/src/page.spec.ts
- Frame tests: https://github.com/puppeteer/puppeteer/blob/main/test/src/frame.spec.ts
