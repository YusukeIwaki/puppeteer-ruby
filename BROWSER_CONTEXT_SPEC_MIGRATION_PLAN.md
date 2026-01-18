# BrowserContext Spec Migration Plan

This document outlines the plan to port BrowserContext-related specs from TypeScript Puppeteer to puppeteer-ruby.

## Current State Analysis

### Existing Ruby Implementation

**`lib/puppeteer/browser_context.rb`** - Current methods:
- `id` - Context ID accessor
- `targets` - Get all targets in context
- `wait_for_target` - Wait for matching target
- `pages` - Get all pages in context
- `incognito?` - Check if incognito context
- `closed?` - Check if context is closed
- `override_permissions` - Grant permissions to origin
- `clear_permission_overrides` - Reset permissions
- `new_page` - Create new page in context
- `browser` - Get parent browser
- `close` - Close the context

### Existing Ruby Specs

**`spec/integration/browser_context_spec.rb`** (11 tests):
- Default context tests
- Incognito context creation/closing
- Target events (created/changed/destroyed)
- wait_for_target functionality
- Isolation (localStorage/cookies)
- Cross-session context persistence
- Context ID validation

**`spec/integration/browser_context_permissions_spec.rb`** (8 tests):
- Permission states (prompt/denied/granted)
- Permission error handling
- Permission reset
- Permission onchange events
- Permission isolation between contexts
- Specific permission types (persistent-storage)

### Cookie Functionality Status

Currently, cookie methods exist only on `Page`:
- `Page#cookies(*urls)` - Get cookies
- `Page#set_cookie(*cookies)` - Set cookies
- `Page#delete_cookie(*cookies)` - Delete cookies

---

## Missing Functionality

### 1. BrowserContext Cookie Methods (Not Yet Implemented)

The TypeScript Puppeteer `BrowserContext` class includes cookie methods:

```typescript
// From puppeteer-core/src/api/BrowserContext.ts
abstract cookies(): Promise<Cookie[]>
abstract setCookie(...cookies: CookieData[]): Promise<void>
async deleteCookie(...cookies: Cookie[]): Promise<void>
async deleteMatchingCookies(...filters: DeleteCookiesRequest[]): Promise<void>
```

These methods operate at the context level rather than page level.

---

## Implementation Plan

### Phase 1: Add BrowserContext Cookie Methods

**File:** `lib/puppeteer/browser_context.rb`

Add the following methods:

```ruby
# Get all cookies in the browser context
# @return [Array<Hash>]
def cookies
  # Use Storage.getCookies CDP command with browserContextId
end

# Set cookies in the browser context
# @param cookies [Array<Hash>] Cookies to set
def set_cookie(*cookies)
  # Use Storage.setCookies CDP command with browserContextId
end

# Delete specific cookies
# @param cookies [Array<Hash>] Cookies to delete (by name, domain, path, etc.)
def delete_cookie(*cookies)
  # Set expiration to past to delete
end

# Delete cookies matching filter criteria
# @param filters [Array<Hash>] Filter criteria (name, domain, path, url, partitionKey)
def delete_matching_cookies(*filters)
  # Use Storage.deleteCookies or Network.deleteCookies CDP command
end
```

**CDP Commands to use:**
- `Storage.getCookies` - Get cookies for browser context
- `Storage.setCookies` - Set cookies for browser context
- `Storage.deleteCookies` or `Network.deleteCookies` - Delete cookies

### Phase 2: Create BrowserContext Cookie Specs

**New File:** `spec/integration/browser_context_cookies_spec.rb`

| Test Case | Description | Priority |
|-----------|-------------|----------|
| `should find no cookies in new context` | Empty cookie array in fresh context | High |
| `should find cookie created in page` | Cookies set via page.evaluate visible | High |
| `should set cookie in context` | Set cookie via context method | High |
| `should delete cookies` | Delete specific cookies by name | High |
| `should delete cookies matching filter` | Delete using name filter | Medium |
| `should delete cookies matching URL filter` | Delete using URL filter | Medium |
| `should delete cookies matching domain filter` | Delete using domain filter | Medium |
| `should delete cookies matching path filter` | Delete using path filter | Medium |
| `should find partitioned cookie` | Partitioned cookie support | Low |
| `should set cookie with partition key` | Partition key cookie setting | Low |

### Phase 3: Update API Coverage Documentation

**File:** `docs/api_coverage.md`

Add new methods to BrowserContext section:
```markdown
## BrowserContext

* browser
* clearPermissionOverrides => `#clear_permission_overrides`
* close
* cookies  <-- NEW
* deleteCookie => `#delete_cookie`  <-- NEW
* deleteMatchingCookies => `#delete_matching_cookies`  <-- NEW
* isIncognito => `#incognito?`
* newPage => `#new_page`
* overridePermissions => `#override_permissions`
* pages
* setCookie => `#set_cookie`  <-- NEW
* targets
* waitForTarget => `#wait_for_target`
```

---

## Test Case Mapping

### From `browsercontext.spec.ts` (Already Implemented)

| TypeScript Test | Ruby Equivalent | Status |
|-----------------|-----------------|--------|
| should have default context | `browser_context_spec.rb:7` | Done |
| should not be able to close default context | `browser_context_spec.rb:13` | Done |
| should create new context | `browser_context_spec.rb:21` | Done |
| should close all belonging targets | `browser_context_spec.rb:30` | Done |
| window.open should use parent tab context | `browser_context_spec.rb:42` | Done |
| should fire target events | `browser_context_spec.rb:65` | Done |
| should wait for a target | `browser_context_spec.rb:98` | Done |
| should timeout waiting for non-existent target | `browser_context_spec.rb:111` | Done |
| should isolate localStorage and cookies | `browser_context_spec.rb:131` | Done |
| should work across sessions | `browser_context_spec.rb:163` | Done |
| should provide a context id | `browser_context_spec.rb:174` | Done |

### From `browsercontext.spec.ts` - Permission Tests (Already Implemented)

| TypeScript Test | Ruby Equivalent | Status |
|-----------------|-----------------|--------|
| should be prompt by default | `browser_context_permissions_spec.rb:18` | Done |
| should deny permission when not listed | `browser_context_permissions_spec.rb:24` | Done |
| should fail when bad permission is given | `browser_context_permissions_spec.rb:31` | Done |
| should grant permission when listed | `browser_context_permissions_spec.rb:38` | Done |
| should reset permissions | `browser_context_permissions_spec.rb:45` | Done |
| should trigger permission onchange | `browser_context_permissions_spec.rb:55` | Done |
| should isolate permissions between contexts | `browser_context_permissions_spec.rb:81` | Done |
| should grant persistent-storage | `browser_context_permissions_spec.rb:105` | Done |

### From `browsercontext-cookies.spec.ts` (To Be Implemented)

| TypeScript Test | Ruby File | Status |
|-----------------|-----------|--------|
| should find no cookies in new context | `browser_context_cookies_spec.rb` | TODO |
| should find cookie created in page | `browser_context_cookies_spec.rb` | TODO |
| should find partitioned cookie | `browser_context_cookies_spec.rb` | TODO (Low Priority) |
| should set with undefined partition key | `browser_context_cookies_spec.rb` | TODO |
| should set cookie with partition key | `browser_context_cookies_spec.rb` | TODO (Low Priority) |
| should delete cookies | `browser_context_cookies_spec.rb` | TODO |
| should delete cookies matching filter | `browser_context_cookies_spec.rb` | TODO |

### From `defaultbrowsercontext.spec.ts` (Already Covered)

| TypeScript Test | Ruby Equivalent | Status |
|-----------------|-----------------|--------|
| page.cookies() should work | `cookies_spec.rb:17` | Done (Page level) |
| page.setCookie() should work | `cookies_spec.rb:145` | Done (Page level) |
| page.deleteCookie() should work | `cookies_spec.rb:396` | Done (Page level) |

---

## Implementation Steps

### Step 1: Research CDP Commands
- [ ] Verify `Storage.getCookies` supports `browserContextId` parameter
- [ ] Verify `Storage.setCookies` supports `browserContextId` parameter
- [ ] Determine best CDP command for deleting cookies at context level

### Step 2: Implement BrowserContext Cookie Methods
- [ ] Add `cookies` method to `BrowserContext`
- [ ] Add `set_cookie` method to `BrowserContext`
- [ ] Add `delete_cookie` method to `BrowserContext`
- [ ] Add `delete_matching_cookies` method to `BrowserContext`

### Step 3: Write Specs
- [ ] Create `spec/integration/browser_context_cookies_spec.rb`
- [ ] Port relevant tests from `browsercontext-cookies.spec.ts`
- [ ] Ensure tests pass in both headless and headed modes

### Step 4: Documentation
- [ ] Update `docs/api_coverage.md` with new methods
- [ ] Add RBS type signatures if applicable

### Step 5: Validation
- [ ] Run full test suite: `bundle exec rspec`
- [ ] Run RuboCop: `bundle exec rubocop`
- [ ] Run Steep type check: `bundle exec steep check`

---

## Notes

### Partitioned Cookies
Partitioned cookies (CHIPS - Cookies Having Independent Partitioned State) are a newer feature. Implementation priority is lower as they may require newer Chrome versions.

### Browser vs Page Cookie Methods
The BrowserContext cookie methods operate context-wide, while Page cookie methods are scoped to the page's URL. Both should coexist:
- Use `Page#cookies` when working with a specific page
- Use `BrowserContext#cookies` when managing cookies across all pages in a context

### CDP Protocol Reference
- [Storage Domain](https://chromedevtools.github.io/devtools-protocol/tot/Storage/)
- [Network Domain - Cookies](https://chromedevtools.github.io/devtools-protocol/tot/Network/#type-Cookie)
