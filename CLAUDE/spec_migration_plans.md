# Puppeteer Test Comparison Report

This report compares test files between [puppeteer/puppeteer](https://github.com/puppeteer/puppeteer/tree/main/test/src) (Node.js) and [puppeteer-ruby](https://github.com/YusukeIwaki/puppeteer-ruby/tree/main/spec/integration).

**Legend:**
- `[MISSING IN RUBY]` - Test exists in Node.js but not ported to RSpec
- `[RUBY ONLY]` - Test exists only in Ruby (should be moved to `xxx_ext_spec.rb`)
- `[PORTED]` - Test successfully ported
- `[PARTIAL]` - Test exists but implementation differs significantly
- `[ ]` - Not started
- `[x]` - Completed

---

## Spec File Mapping Overview

### Node.js → Ruby Mapping Status

| Node.js Spec | Ruby Spec | Status |
|--------------|-----------|--------|
| acceptInsecureCerts.spec.ts | - | No Ruby equivalent (feature may be in launcher_spec) |
| accessibility.spec.ts | - | **[MISSING]** Not ported |
| ariaqueryhandler.spec.ts | aria_query_handler_spec.rb | [x] Ported |
| autofill.spec.ts | - | **[MISSING]** Not ported |
| bluetooth-emulation.spec.ts | - | Low priority (specialized feature) |
| browser.spec.ts | browser_spec.rb | [x] Ported |
| browsercontext.spec.ts | browser_context_spec.rb | [x] Ported |
| browsercontext-cookies.spec.ts | browser_context_cookies_spec.rb | [x] Ported |
| click.spec.ts | click_spec.rb | [x] Ported |
| connect.spec.ts | (in launcher_spec.rb) | [x] Ported |
| cookies.spec.ts | cookies_spec.rb | [x] Ported |
| coverage.spec.ts | coverage_spec.rb | [x] Ported |
| debugInfo.spec.ts | - | Low priority (debugging feature) |
| defaultbrowsercontext.spec.ts | (in browser_context_spec.rb) | [x] Ported |
| device-request-prompt.spec.ts | - | **[MISSING]** Not ported |
| dialog.spec.ts | dialog_spec.rb | [x] Ported |
| download.spec.ts | - | **[MISSING]** Not ported |
| drag-and-drop.spec.ts | drag_and_drop_spec.rb | [x] Ported |
| elementhandle.spec.ts | element_handle_spec.rb | [x] Ported |
| emulation.spec.ts | emulation_spec.rb | [x] Ported |
| evaluation.spec.ts | evaluation_spec.rb | [x] Ported |
| fixtures.spec.ts | - | N/A (test infrastructure) |
| frame.spec.ts | frame_spec.rb | [x] Ported |
| headful.spec.ts | - | Low priority (headful-specific) |
| idle_override.spec.ts | idle_override_spec.rb | [x] Ported |
| injected.spec.ts | - | N/A (internal implementation) |
| input.spec.ts | input_spec.rb | [x] Ported |
| jshandle.spec.ts | js_handle_spec.rb | [x] Ported |
| keyboard.spec.ts | keyboard_spec.rb | [x] Ported |
| launcher.spec.ts | launcher_spec.rb | [x] Ported |
| locator.spec.ts | - | **[MISSING]** Locator API not ported |
| mouse.spec.ts | mouse_spec.rb | [x] Ported |
| navigation.spec.ts | (in page_spec.rb) | [PARTIAL] Some tests ported |
| network.spec.ts | network_spec.rb | [PARTIAL] Minimal porting |
| oopif.spec.ts | oopif_spec.rb | [x] Ported |
| page.spec.ts | page_spec.rb | [x] Ported |
| proxy.spec.ts | - | **[MISSING]** Not ported |
| queryhandler.spec.ts | query_handler_spec.rb | [x] Ported |
| queryselector.spec.ts | query_selector_spec.rb | [x] Ported |
| requestinterception.spec.ts | request_interception_spec.rb | [x] Ported |
| requestinterception-experimental.spec.ts | request_interception_experimental_spec.rb | [x] Ported |
| screenshot.spec.ts | screenshot_spec.rb | [x] Ported |
| stacktrace.spec.ts | - | Low priority (debugging feature) |
| target.spec.ts | (in browser_spec.rb, launcher_spec.rb) | [PARTIAL] Some tests ported |
| touchscreen.spec.ts | touchscreen_spec.rb | [x] Ported |
| tracing.spec.ts | tracing_spec.rb | [x] Ported |
| waittask.spec.ts | wait_task_spec.rb | [PARTIAL] Many tests missing |
| webExtension.spec.ts | - | Low priority (Chrome extension feature) |
| webgl.spec.ts | - | Low priority (WebGL-specific) |
| worker.spec.ts | worker_spec.rb | [x] Ported |

---

## High Priority Missing Features

### 1. Accessibility API (`accessibility.spec.ts`)
**Priority: HIGH** - Important for web accessibility testing

Node.js tests include:
- `Accessibility > should work`
- `Accessibility > should report uninteresting nodes`
- `Accessibility > iframes` (same-origin, cross-origin)
- `Accessibility > filtering children of leaf nodes`
- `Accessibility > elementHandle()` - get ElementHandle from snapshot

**Ruby status:** Not implemented. Need to add `Page#accessibility` API.

### 2. Locator API (`locator.spec.ts`)
**Priority: HIGH** - Modern element interaction API

Node.js tests include:
- `Locator.click` - with retries, timeouts, visibility checks
- `Locator.hover`
- `Locator.scroll`
- `Locator.fill` - for inputs, textareas, selects, contenteditable
- `Locator.race` - race multiple locators
- `Locator.prototype.map/filter/wait/clone`
- `FunctionLocator`

**Ruby status:** Not implemented. This is a significant new API addition.

### 3. Navigation Tests (`navigation.spec.ts`)
**Priority: HIGH** - Core navigation functionality

Missing tests:
- `Page.goto` - many edge cases (redirects, 204 responses, timeouts)
- `Page.waitForNavigation` - history API, subframes
- `Page.goBack/goForward` - history navigation
- `Frame.goto` - subframe navigation
- `Frame.waitForNavigation`

**Ruby status:** Some tests exist in page_spec.rb but navigation.spec.ts has many more edge cases.

### 4. Network Tests (`network.spec.ts`)
**Priority: HIGH** - Network inspection is core functionality

Missing tests:
- `Page.Events.Request` - fire for navigation, iframes, fetches
- `Request.frame` - get frame for request
- `Request.headers` / `Response.headers`
- `Response.fromCache` / `Response.fromServiceWorker`
- `Response.text` / `Response.json` / `Response.buffer`
- `Response.timing` - timing information
- `Request.isNavigationRequest`
- `Page.setExtraHTTPHeaders`
- `Page.authenticate` - HTTP authentication
- `Response.remoteAddress`

**Ruby status:** network_spec.rb is minimal. Many network tests need porting.

### 5. Target API (`target.spec.ts`)
**Priority: MEDIUM** - Target management

Missing tests:
- `Browser.targets` - return all targets
- `Browser.pages` - return all pages
- `Target` events (created, destroyed, changed)
- Service worker targets
- Shared worker targets
- `Browser.waitForTarget` with abort

**Ruby status:** Some tests in browser_spec.rb and launcher_spec.rb, but target.spec.ts has more comprehensive coverage.

---

## Medium Priority Missing Features

### 6. Download API (`download.spec.ts`)
**Priority: MEDIUM** - File download handling

Node.js tests:
- `Browser.createBrowserContext > should download to configured location`
- `Browser.createBrowserContext > should not download to location`

**Ruby status:** Not implemented.

### 7. Proxy Support (`proxy.spec.ts`)
**Priority: MEDIUM** - Proxy configuration

**Ruby status:** Not implemented. Would need proxy launch options.

### 8. Device Request Prompt (`device-request-prompt.spec.ts`)
**Priority: LOW** - Bluetooth/USB device selection

**Ruby status:** Not implemented. Specialized feature.

---

## Migration Progress Tracking

### Phase 1: Core Functionality Gaps (High Priority)
- [ ] Port `accessibility.spec.ts` tests → Create `accessibility_spec.rb`
- [ ] Port missing `navigation.spec.ts` tests → Add to `page_spec.rb` or create `navigation_spec.rb`
- [ ] Port missing `network.spec.ts` tests → Expand `network_spec.rb`
- [ ] Port missing `target.spec.ts` tests → Add to `browser_spec.rb`

### Phase 2: New APIs (High Priority)
- [ ] Implement Locator API and port `locator.spec.ts` tests

### Phase 3: Medium Priority
- [ ] Port `download.spec.ts` tests
- [ ] Port `proxy.spec.ts` tests
- [ ] Port missing `waittask.spec.ts` tests (especially `Frame.waitForFunction`)

### Phase 4: Clean Up
- [ ] Move Ruby-only tests to `_ext_spec.rb` files
- [ ] Port remaining edge case tests from Node.js

---

## Detailed File-by-File Comparison

---

## 1. browsercontext.spec.ts vs browser_context_spec.rb

### Ported Tests
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| should have default context | should have default context | [PORTED] |
| should not be able to close default context | cannot be closed | [PORTED] |
| should create new context | should create new incognito context | [PORTED] |
| should close all belonging targets once closing context | should close all belonging targets once closing context | [PORTED] |
| window.open should use parent tab context | window.open should use parent tab context | [PORTED] |
| should fire target events | should fire target events | [PORTED] |
| should wait for a target | should wait for a target | [PORTED] |
| should timeout waiting for a non-existent target | should timeout waiting for a non-existent target | [PORTED] |
| should isolate localStorage and cookies | should isolate localStorage and cookies | [PORTED] |
| should work across sessions | should work across sessions | [PORTED] |
| should provide a context id | should provide a context id | [PORTED] |

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| BrowserContext.overridePermissions > should be prompt by default | [MISSING IN RUBY] |
| BrowserContext.overridePermissions > should deny permission when not listed | [MISSING IN RUBY] |
| BrowserContext.overridePermissions > should fail when bad permission is given | [MISSING IN RUBY] |
| BrowserContext.overridePermissions > should grant permission when listed | [MISSING IN RUBY] |
| BrowserContext.overridePermissions > should reset permissions | [MISSING IN RUBY] |
| BrowserContext.overridePermissions > should trigger permission onchange | [MISSING IN RUBY] |
| BrowserContext.overridePermissions > should isolate permissions between browser contexts | [MISSING IN RUBY] |
| BrowserContext.overridePermissions > should grant persistent-storage | [MISSING IN RUBY] |

---

## 2. browser.spec.ts vs browser_spec.rb

### Ported Tests
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| Browser.version > should return version | should return version | [PORTED] |
| Browser.userAgent > should include Browser engine | should include WebKit | [PORTED] |
| Browser.target > should return browser target | should return browser target | [PORTED] |
| Browser.isConnected > should set the browser connected state | should return the browser connected state | [PORTED] |

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| Browser.userAgent > should include Browser name | [MISSING IN RUBY] |
| Browser.process > should return child_process instance | [MISSING IN RUBY] |
| Browser.process > should not return child_process for remote browser | [MISSING IN RUBY] |
| Browser.process > should keep connected after the last page is closed | [MISSING IN RUBY] |
| Browser.screens > should return default screen info | [MISSING IN RUBY] |
| Browser.add\|removeScreen > should add and remove a screen | [MISSING IN RUBY] |
| Browser.get\|setWindowBounds > should get and set browser window bounds | [MISSING IN RUBY] |
| Browser.get\|setWindowBounds > should set and get browser window maximized state | [MISSING IN RUBY] |

---

## 3. click.spec.ts vs click_spec.rb

### Ported Tests (All tests appear to be faithfully ported)
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| should click the button | should click the button | [PORTED] |
| should click svg | should click svg | [PORTED] |
| should click the button if window.Node is removed | should click the button if window.Node is removed | [PORTED] |
| should click on a span with an inline element inside | should click on a span with an inline element inside | [PORTED] |
| should not throw UnhandledPromiseRejection when page closes | should not throw UnhandledPromiseRejection when page closes | [PORTED] |
| should click the button after navigation | should click the button after navigation | [PORTED] |
| should click with disabled javascript | should click with disabled javascript | [PORTED] |
| should scroll and click with disabled javascript | should scroll and click with disabled javascript | [PORTED] |
| should click when one of inline box children is outside of viewport | should click when one of inline box children is outside of viewport | [PORTED] |
| should select the text by triple clicking | should select the text by triple clicking | [PORTED] |
| should click offscreen buttons | should click offscreen buttons | [PORTED] |
| should click half-offscreen elements | should click half-offscreen elements | [PORTED] |
| should click wrapped links | should click wrapped links | [PORTED] |
| should click on checkbox input and toggle | should click on checkbox input and toggle | [PORTED] |
| should click on checkbox label and toggle | should click on checkbox label and toggle | [PORTED] |
| should fail to click a missing button | should fail to click a missing button | [PORTED] |
| should not hang with touch-enabled viewports | should not hang with touch-enabled viewports | [PORTED] |
| should scroll and click the button | should scroll and click the button | [PORTED] |
| should double click the button | should double click the button | [PORTED] |
| should double multiple times | should double multiple times | [PORTED] |
| should click a partially obscured button | should click a partially obscured button | [PORTED] |
| should click a rotated button | should click a rotated button | [PORTED] |
| should fire contextmenu event on right click | should fire contextmenu event on right click | [PORTED] |
| should fire aux event on middle click | should fire aux event on middle click | [PORTED] |
| should fire back click | should fire back click | [PORTED] |
| should fire forward click | should fire forward click | [PORTED] |
| should click links which cause navigation | should click links which cause navigation | [PORTED] |
| should click the button inside an iframe | should click the button inside an iframe | [PORTED] |
| should click the button with fixed position inside an iframe | should click the button with fixed position inside an iframe | [PORTED] |
| should click the button with deviceScaleFactor set | should click the button with deviceScaleFactor set | [PORTED] |

---

## 4. cookies.spec.ts vs cookies_spec.rb

### Ported Tests
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| Page.cookies > should return no cookies in pristine browser context | should return no cookies in pristine browser context | [PORTED] |
| Page.cookies > should get a cookie | should get a cookie | [PORTED] |
| Page.cookies > should properly report httpOnly cookie | should properly report httpOnly cookie | [PORTED] |
| Page.cookies > should properly report "Strict" sameSite cookie | should properly report "Strict" sameSite cookie | [PORTED] |
| Page.cookies > should properly report "Lax" sameSite cookie | should properly report "Lax" sameSite cookie | [PORTED] |
| Page.cookies > should get multiple cookies | should get multiple cookies | [PORTED] |
| Page.cookies > should get cookies from multiple urls | should get cookies from multiple urls | [PORTED] |
| Page.setCookie > should work | should work | [PORTED] |
| Page.setCookie > should isolate cookies in browser contexts | should isolate cookies in browser contexts | [PORTED] |
| Page.setCookie > should set multiple cookies | should set multiple cookies | [PORTED] |
| Page.setCookie > should have \|expires\| set to \|-1\| for session cookies | should have \|expires\| set to \|-1\| for session cookies | [PORTED] |
| Page.setCookie > should set cookie with reasonable defaults | should set cookie with reasonable defaults | [PORTED] |
| Page.setCookie > should set a cookie with a path | should set a cookie with a path | [PORTED] |
| Page.setCookie > should not set a cookie on a blank page | should not set a cookie on a blank page | [PORTED] |
| Page.setCookie > should not set a cookie with blank page URL | should not set a cookie with blank page URL | [PORTED] |
| Page.setCookie > should not set a cookie on a data URL page | should not set a cookie on a data URL page | [PORTED] |
| Page.setCookie > should default to setting secure cookie for HTTPS websites | should default to setting secure cookie for HTTPS websites | [PORTED] |
| Page.setCookie > should be able to set insecure cookie for HTTP website | should be able to set unsecure cookie for HTTP website | [PORTED] |
| Page.setCookie > should set a cookie on a different domain | should set a cookie on a different domain | [PORTED] |
| Page.setCookie > should set cookies from a frame | should set cookies from a frame | [PORTED] |
| Page.deleteCookie > should delete cookie | should work | [PORTED] |

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| Page.cookies > should get cookies from subdomain if the domain field allows it | [MISSING IN RUBY] |
| Page.cookies > should not get cookies from subdomain if the cookie is for top-level domain | [MISSING IN RUBY] |
| Page.cookies > should get cookies from nested path | [MISSING IN RUBY] |
| Page.cookies > should not get cookies from not nested path | [MISSING IN RUBY] |
| Page.setCookie > should set cookie with all available properties | [MISSING IN RUBY] |
| Page.setCookie > should set a cookie with a partitionKey | [MISSING IN RUBY] |
| Page.setCookie > should set secure same-site cookies from a frame | [MISSING IN RUBY] (commented out in Ruby) |
| Page.deleteCookie > should not delete cookie for different domain | [MISSING IN RUBY] |
| Page.deleteCookie > should delete cookie for specified URL | [MISSING IN RUBY] |
| Page.deleteCookie > should delete cookie for specified URL regardless of the current page | [MISSING IN RUBY] |
| Page.deleteCookie > should only delete cookie from the default partition if partitionkey is not specified | [MISSING IN RUBY] |
| Page.deleteCookie > should delete cookie with partition key if partition key is specified | [MISSING IN RUBY] |

### Ruby Only
| Ruby Test | Notes |
|-----------|-------|
| should fail if specifying wrong cookie | [RUBY ONLY] - Ruby-specific validation |

---

## 5. dialog.spec.ts vs dialog_spec.rb

### Ported Tests (Fully ported)
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| should fire | should fire | [PORTED] |
| should allow accepting prompts | should allow accepting prompts | [PORTED] |
| should dismiss the prompt | should dismiss the prompt | [PORTED] |

---

## 6. elementhandle.spec.ts vs element_handle_spec.rb

### Ported Tests
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| ElementHandle.boundingBox > should work | should work | [PORTED] |
| ElementHandle.boundingBox > should handle nested frames | should handle nested frames | [PORTED] |
| ElementHandle.boundingBox > should return null for invisible elements | should return null for invisible elements | [PORTED] |
| ElementHandle.boundingBox > should force a layout | should force a layout | [PORTED] |
| ElementHandle.boundingBox > should work with SVG nodes | should work with SVG nodes | [PORTED] |
| ElementHandle.boxModel > should work | should work | [PORTED] |
| ElementHandle.boxModel > should return null for invisible elements | should return null for invisible elements | [PORTED] |
| ElementHandle.boxModel > should correctly compute box model with offsets | should correctly compute box model with offsets | [PORTED] |
| ElementHandle.contentFrame > should work | should work | [PORTED] |
| ElementHandle.isVisible and ElementHandle.isHidden > should work | should work | [PORTED] |
| ElementHandle.click > should work | should work | [PORTED] |
| ElementHandle.click > should return Point data | should return Point data | [PORTED] |
| ElementHandle.click > should work for Shadow DOM v1 | should work for Shadow DOM v1 | [PORTED] |
| ElementHandle.click > should not work for TextNodes | should throw for TextNodes | [PORTED] |
| ElementHandle.click > should throw for detached nodes | should throw for detached nodes | [PORTED] |
| ElementHandle.click > should throw for hidden nodes | should throw for hidden nodes | [PORTED] |
| ElementHandle.click > should throw for recursively hidden nodes | should throw for recursively hidden nodes | [PORTED] |
| ElementHandle.click > should throw for <br> elements | should throw for <br> elements | [PORTED] |
| ElementHandle.touchStart > should work | should work | [PORTED] |
| ElementHandle.touchStart > should work with the returned Touch | should work with the returned Touch | [PORTED] |
| ElementHandle.touchMove > should work | should work | [PORTED] |
| ElementHandle.touchMove > should work with a pre-existing Touch | should work with a pre-existing Touch | [PORTED] |
| ElementHandle.touchEnd > should work | should work | [PORTED] |
| ElementHandle.clickablePoint > should work | should work | [PORTED] |
| ElementHandle.clickablePoint > should not work if the click box is not visible | should not work if click box is not visible | [PORTED] |
| ElementHandle.clickablePoint > should not work if the click box is not visible due to the iframe | should not work if click box is not visible due to iframe | [PORTED] |
| ElementHandle.clickablePoint > should work for iframes | should work for iframes | [PORTED] |
| Element.waitForSelector > should wait correctly with waitForSelector on an element | should wait correctly with waitForSelector on an element | [PORTED] |
| ElementHandle.hover > should work | should work | [PORTED] |
| ElementHandle.isIntersectingViewport > should work | should work | [PORTED] |
| ElementHandle.isIntersectingViewport > should work with threshold | should work with threshold | [PORTED] |
| ElementHandle.isIntersectingViewport > should work with threshold of 1 | should work with threshold of 1 | [PORTED] |
| ElementHandle.isIntersectingViewport > should work with svg elements | should work with svg elements | [PORTED] |
| Custom queries > should register and unregister | should register and unregister | [PORTED] |
| Custom queries > should throw with invalid query names | should throw with invalid query names | [PORTED] |
| Custom queries > should work for multiple elements | should work for multiple elements | [PORTED] |
| Custom queries > should eval correctly | should eval correctly | [PORTED] |
| Custom queries > should work when both queryOne and queryAll are registered | should work when both queryOne and queryAll are registered | [PORTED] |
| ElementHandle.toElement > should work | should work | [PORTED] |
| ElementHandle.dispose > should dispose cached isolated handler | should dispose element handles | [PORTED] |
| ElementHandle.move > should work | should work | [PORTED] |

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| Custom queries > should wait correctly with waitForSelector | [MISSING IN RUBY] (commented out) |
| Custom queries > should wait correctly with waitForSelector on an element | [MISSING IN RUBY] (commented out) |
| Custom queries > should work with function shorthands | [MISSING IN RUBY] |
| ElementHandle[Symbol.dispose] > should work | [MISSING IN RUBY] |
| ElementHandle[Symbol.asyncDispose] > should work | [MISSING IN RUBY] |

### Ruby Only
| Ruby Test | Notes |
|-----------|-------|
| #wait_for_xpath > should wait correctly with waitForXPath on an element | [RUBY ONLY] - XPath specific test |

---

## 7. evaluation.spec.ts vs evaluation_spec.rb

### Ported Tests (Comprehensive porting)
Most tests are faithfully ported. Notable coverage includes:
- All basic `Page.evaluate` tests
- BigInt, NaN, Infinity, -Infinity transfer tests
- Arrays, RegEx transfer tests
- Error handling tests
- `Page.evaluateOnNewDocument` tests
- `Page.removeScriptToEvaluateOnNewDocument` tests
- `Frame.evaluate` tests

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| Page.evaluateOnNewDocument > should work with CSP | Partially implemented (test exists but CSP handling may differ) |

---

## 8. frame.spec.ts vs frame_spec.rb

### Ported Tests
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| Frame.evaluateHandle > should work | should work | [PORTED] |
| Frame.evaluate > should throw for detached frames | should throw for detached frames | [PORTED] |
| Frame.evaluate > allows readonly array to be an argument | allows readonly array to be an argument | [PORTED] |
| Frame.page > should retrieve the page from a frame | should retrieve the page from a frame | [PORTED] |
| Frame Management > should handle nested frames | should handle nested frames | [PORTED] |
| Frame Management > should send events when frames are manipulated dynamically | should send events when frames are manipulated dynamically | [PORTED] |
| Frame Management > should send "framenavigated" when navigating on anchor URLs | should send "framenavigated" when navigating on anchor URLs | [PORTED] |
| Frame Management > should persist mainFrame on cross-process navigation | should persist mainFrame on cross-process navigation | [PORTED] |
| Frame Management > should not send attach/detach events for main frame | should not send attach/detach events for main frame | [PORTED] |
| Frame Management > should detach child frames on navigation | should detach child frames on navigation | [PORTED] |
| Frame Management > should support framesets | should support framesets | [PORTED] |
| Frame Management > should click elements in a frameset | should click elements in a frameset | [PORTED] |
| Frame Management > should report frame from-inside shadow DOM | should report frame from-inside shadow DOM | [PORTED] |
| Frame Management > should report frame.parent() | should report frame.parent() | [PORTED] |
| Frame Management > should report different frame instance when frame re-attaches | should report different frame instance when frame re-attaches | [PORTED] |
| Frame Management > should support url fragment | should support url fragment | [PORTED] |
| Frame Management > should support lazy frames | should support lazy frames | [PORTED] |
| Frame.client > should return the client instance | should return the client instance | [PORTED] |
| Frame.prototype.frameElement > should work | should work | [PORTED] |
| Frame.prototype.frameElement > should handle shadow roots | should handle shadow roots | [PORTED] |
| Frame.prototype.frameElement > should return ElementHandle in the correct world | should return ElementHandle in the correct world | [PORTED] |

---

## 9. input.spec.ts vs input_spec.rb

### Ported Tests (All major tests ported)
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| ElementHandle.uploadFile > should upload the file | should upload the file | [PORTED] |
| ElementHandle.uploadFile > should read the file | should read the file | [PORTED] |
| Page.waitForFileChooser > should work when file input is attached to DOM | should work when file input is attached to DOM | [PORTED] |
| Page.waitForFileChooser > should work when file input is not attached to DOM | should work when file input is not attached to DOM | [PORTED] |
| Page.waitForFileChooser > should respect timeout | should respect timeout | [PORTED] |
| Page.waitForFileChooser > should respect default timeout when there is no custom timeout | should respect default timeout when there is no custom timeout | [PORTED] |
| Page.waitForFileChooser > should prioritize exact timeout over default timeout | should prioritize exact timeout over default timeout | [PORTED] |
| Page.waitForFileChooser > should work with no timeout | should work with no timeout | [PORTED] |
| Page.waitForFileChooser > should return the same file chooser when there are many watchdogs simultaneously | should return the same file chooser when there are many watchdogs simultaneously | [PORTED] |
| FileChooser.accept > should accept single file | should accept single file | [PORTED] |
| FileChooser.accept > should be able to read selected file | should be able to read selected file | [PORTED] |
| FileChooser.accept > should be able to reset selected files with empty file list | should be able to reset selected files with empty file list | [PORTED] |
| FileChooser.accept > should not accept multiple files for single-file input | should not accept multiple files for single-file input | [PORTED] |
| FileChooser.accept > should succeed even for non-existent files | should succeed even for non-existent files | [PORTED] |
| FileChooser.accept > should error on read of non-existent files | should error on read of non-existent files | [PORTED] |
| FileChooser.accept > should fail when accepting file chooser twice | should fail when accepting file chooser twice | [PORTED] |
| FileChooser.cancel > should cancel dialog | should cancel dialog | [PORTED] |
| FileChooser.cancel > should fail when canceling file chooser twice | should fail when canceling file chooser twice | [PORTED] |
| FileChooser.isMultiple > should work for single file pick | should work for single file pick | [PORTED] |
| FileChooser.isMultiple > should work for "multiple" | should work for "multiple" | [PORTED] |
| FileChooser.isMultiple > should work for "webkitdirectory" | should work for "webkitdirectory" | [PORTED] |

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| Page.waitForFileChooser > should be able to abort | [MISSING IN RUBY] - AbortController not supported |

---

## 10. jshandle.spec.ts vs js_handle_spec.rb

### Ported Tests (Comprehensive)
All major tests are ported including:
- `Page.evaluateHandle` tests
- `JSHandle.getProperty` tests
- `JSHandle.jsonValue` tests (including dates, circular objects)
- `JSHandle.getProperties` tests
- `JSHandle.asElement` tests
- `JSHandle.toString` tests
- Symbol dispose tests
- `JSHandle.move` tests

---

## 11. keyboard.spec.ts vs keyboard_spec.rb

### Ported Tests (All major tests ported)
All keyboard tests appear to be faithfully ported including:
- Type into textarea
- Arrow key movement
- Keyboard shortcuts/commands
- `ElementHandle.press`
- `sendCharacter` tests
- Modifier keys (Shift, Alt, Control)
- Multiple modifiers
- Proper codes while typing
- Repeat property
- Unicode/emoji typing
- Location specification
- Meta key tests

---

## 12. launcher.spec.ts vs launcher_spec.rb

### Ported Tests
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| Browser.disconnect > should reject navigation when browser closes | should reject navigation when browser closes | [PORTED] |
| Browser.disconnect > should reject waitForSelector when browser closes | should reject wait_for_selector when browser closes | [PORTED] |
| Browser.close > should terminate network waiters | should terminate network waiters | [PORTED] |
| Puppeteer.launch > should reject all promises when browser is closed | should reject all promises when browser is closed | [PORTED] |
| Puppeteer.launch > should reject if executable path is invalid | should reject if executable path is invalid | [PORTED] |
| Puppeteer.launch > userDataDir option | user_data_dir option | [PORTED] |
| Puppeteer.launch > userDataDir argument | user_data_dir argument | [PORTED] |
| Puppeteer.launch > userDataDir option should restore state | user_data_dir option should restore state | [PORTED] |
| Puppeteer.launch > userDataDir option should restore cookies | user_data_dir option should restore cookies | [PORTED] |
| Puppeteer.launch > should filter out ignored default arguments in Chrome | should filter out ignored default arguments | [PORTED] |
| Puppeteer.launch > should have default URL when launching browser | should have default URL when launching browser | [PORTED] |
| Puppeteer.launch > should have custom URL when launching browser | should have custom URL when launching browser | [PORTED] |
| Puppeteer.launch > should pass the timeout parameter to browser.waitForTarget | should pass the timeout parameter to browser.waitForTarget | [PORTED] |
| Puppeteer.launch > should set the default viewport | should set the default viewport | [PORTED] |
| Puppeteer.launch > should disable the default viewport | should disable the default viewport | [PORTED] |
| Puppeteer.launch > should set the debugging port | should set the debugging port | [PORTED] |
| Puppeteer.connect > should be able to connect multiple times to the same browser | should be able to connect multiple times to the same browser | [PORTED] |
| Puppeteer.connect > should be able to close remote browser | should be able to close remote browser | [PORTED] |
| Puppeteer.connect > should be able to reconnect to a disconnected browser | should be able to reconnect to a disconnected browser | [PORTED] |
| Puppeteer.connect > should be able to connect to the same page simultaneously | should be able to connect to the same page simultaneously | [PORTED] |
| Puppeteer.executablePath > should work | returns browser executable path | [PORTED] |
| Browser target events > should work | should work | [PORTED] |
| Browser.Events.disconnected > should be emitted when: browser gets closed, disconnected or underlying websocket gets closed | should be emitted when: browser gets closed, disconnected or underlying websocket gets closed | [PORTED] |

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| Puppeteer.launch > can launch and close the browser | [MISSING IN RUBY] |
| Puppeteer.launch > can launch multiple instances without node warnings | [MISSING IN RUBY] |
| Puppeteer.launch > should close browser with beforeunload page | [MISSING IN RUBY] |
| Puppeteer.launch > tmp profile should be cleaned up | [MISSING IN RUBY] |
| Puppeteer.launch > userDataDir option restores preferences | [MISSING IN RUBY] |
| Puppeteer.launch > userDataDir argument with non-existent dir | [MISSING IN RUBY] |
| Puppeteer.launch > should return the default arguments | [MISSING IN RUBY] |
| Puppeteer.launch > should report the correct product | [MISSING IN RUBY] |
| Puppeteer.launch > should filter out ignored default argument in Firefox | [MISSING IN RUBY] |
| Puppeteer.launch > should work with timeout = 0 | [MISSING IN RUBY] |
| Puppeteer.launch > should not allow setting debuggingPort and pipe | [MISSING IN RUBY] |
| Puppeteer.launch > throws an error if executable path is not valid with pipe=true | [MISSING IN RUBY] |
| Puppeteer.connect > should be able to connect to a browser with no page targets | [MISSING IN RUBY] |
| Puppeteer.connect > should support acceptInsecureCerts option | [MISSING IN RUBY] |
| Puppeteer.connect > should support targetFilter option in puppeteer.launch | [MISSING IN RUBY] |
| Puppeteer.connect > should support targetFilter option | [MISSING IN RUBY] |
| Puppeteer.connect > should be able to reconnect | [MISSING IN RUBY] |
| Puppeteer.executablePath > returns executablePath for channel | [MISSING IN RUBY] |
| Puppeteer.executablePath > when executable path is configured > its value is used | [MISSING IN RUBY] |

### Ruby Only
| Ruby Test | Notes |
|-----------|-------|
| should work with no default arguments | [RUBY ONLY] |
| should take fullPage screenshots when defaultViewport is null | [RUBY ONLY] |
| should take Element screenshots when defaultViewport is null | [RUBY ONLY] |
| Puppeteer.default_args tests | [RUBY ONLY] - Ruby-specific API |
| #product | [RUBY ONLY] |

---

## 13. mouse.spec.ts vs mouse_spec.rb

### Ported Tests (All major tests ported)
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| should click the document | should click the document | [PORTED] |
| should resize the textarea | should resize the textarea | [PORTED] |
| should select the text with mouse | should select the text with mouse | [PORTED] |
| should trigger hover state | should trigger hover state | [PORTED] |
| should trigger hover state with removed window.Node | should trigger hover state with removed window.Node | [PORTED] |
| should set modifier keys on click | should set modifier keys on click | [PORTED] |
| should send mouse wheel events | should send mouse wheel events | [PORTED] |
| should set ctrlKey on the wheel event | should set ctrlKey on the wheel event | [PORTED] |
| should tween mouse movement | should tween mouse movement | [PORTED] |
| should work with mobile viewports and cross process navigations | should work with mobile viewports and cross process navigations | [PORTED] |
| should not throw if buttons are pressed twice | should not throw if buttons are pressed twice | [PORTED] |
| should not throw if clicking in parallel | should not throw if clicking in parallel | [PORTED] |
| should reset properly | should reset properly | [PORTED] |
| should evaluate before mouse event | should evaluate before mouse event | [PORTED] |

---

## 14. network.spec.ts vs network_spec.rb

### Ported Tests
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| Request.initiator > should return the initiator | shoud return the initiator | [PORTED] |
| Response.statusText > should work | should work | [PORTED] |

### Missing in Ruby (Significant gaps)
| Node.js Test | Notes |
|--------------|-------|
| Page.Events.Request > should fire for navigation requests | [MISSING IN RUBY] |
| Page.Events.Request > should fire for iframes | [MISSING IN RUBY] |
| Page.Events.Request > should fire for fetches | [MISSING IN RUBY] |
| Request.frame > (all tests) | [MISSING IN RUBY] |
| Request.headers > (all tests) | [MISSING IN RUBY] |
| Response.headers > should work | [MISSING IN RUBY] |
| Response.fromCache > (all tests) | [MISSING IN RUBY] |
| Response.fromServiceWorker > (all tests) | [MISSING IN RUBY] |
| Request.fetchPostData > (all tests) | [MISSING IN RUBY] |
| Response.text > (all tests) | [MISSING IN RUBY] |
| Response.json > should work | [MISSING IN RUBY] |
| Response.buffer > (all tests) | [MISSING IN RUBY] |
| Response.statusText > handles missing status text | [MISSING IN RUBY] |
| Response.timing > returns timing information | [MISSING IN RUBY] |
| Network Events > (all tests) | [MISSING IN RUBY] |
| Request.isNavigationRequest > (all tests) | [MISSING IN RUBY] |
| Page.setExtraHTTPHeaders > (all tests) | [MISSING IN RUBY] |
| Page.authenticate > (all tests) | [MISSING IN RUBY] |
| raw network headers > (all tests) | [MISSING IN RUBY] |
| Page.setBypassServiceWorker > (all tests) | [MISSING IN RUBY] |
| Request.resourceType > (all tests) | [MISSING IN RUBY] |
| Response.remoteAddress > (all tests) | [MISSING IN RUBY] |

**Note:** The Ruby network_spec.rb is minimal compared to Node.js. Many network tests may exist in other spec files or require porting.

---

## 15. page.spec.ts vs page_spec.rb

### Ported Tests (Extensive coverage)
Most Page tests are faithfully ported. Key areas covered:
- Page.close tests
- Page.Events.Load
- Event handler adding/removing
- Page.Events.error
- Page.Events.Popup (all variations)
- Page.setGeolocation
- Page.setOfflineMode
- Page.Events.Console (comprehensive)
- Page.Events.DOMContentLoaded
- Page.metrics
- Page.waitForRequest
- Page.waitForResponse
- Page.waitForNetworkIdle
- Page.waitForFrame
- Page.exposeFunction (comprehensive)
- Page.removeExposedFunction
- Page.Events.PageError
- Page.setUserAgent
- Page.setContent
- Page.setBypassCSP
- Page.addScriptTag
- Page.addStyleTag
- Page.url
- Page.setJavaScriptEnabled
- Page.reload
- Page.setCacheEnabled
- Page.pdf
- Page.title
- Page.select
- Page.Events.Close
- Page.browser
- Page.browserContext
- Page.client
- Page.bringToFront

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| Page.newPage > should open pages in a new window | skipped |
| Page.newPage > should open pages in a new window at the specified position | skipped |
| Page.newPage > should open pages in a new window in maximized state | skipped |
| Page.newPage > should create a background page | skipped |
| Page.waitForRequest > should be cancellable | [MISSING IN RUBY] - AbortSignal not supported |
| Page.waitForResponse > should be cancellable | [MISSING IN RUBY] - AbortSignal not supported |
| Page.waitForNetworkIdle > should be cancelable | [MISSING IN RUBY] - AbortSignal not supported |
| Page.waitForFrame > should be cancellable | [MISSING IN RUBY] - AbortSignal not supported |
| Page.exposeFunction > should await returned promise | [MISSING IN RUBY] - Ruby doesn't have async functions |
| Page.exposeFunction > should fallback to default export when passed a module object | skipped |
| Page.setUserAgent > should work with options parameter | skipped |
| Page.setUserAgent > should work with platform option | skipped |
| Page.setUserAgent > should work with platform option without userAgent | skipped |
| Page.resize > should resize the browser window to fit page content | skipped |

---

## 16. queryselector.spec.ts vs query_selector_spec.rb

### Ported Tests (All major tests ported)
All querySelector tests are faithfully ported including:
- Page.$eval tests
- Page.$$eval tests
- Page.$ tests
- Page.$$ tests (including xpath)
- ElementHandle.$ tests
- ElementHandle.$eval tests
- ElementHandle.$$eval tests
- ElementHandle.$$ tests (including xpath)
- QueryAll custom handler tests

---

## 17. requestinterception.spec.ts vs request_interception_spec.rb

### Ported Tests (Comprehensive coverage)
The Ruby spec has extensive request interception tests including:
- Page.setRequestInterception basics
- Request.continue
- Request.respond
- Request.abort
- Request.resourceType

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| should work with keep alive redirects | [MISSING IN RUBY] |
| should not allow mutating request headers | [MISSING IN RUBY] |
| should work with requests without networkId | [MISSING IN RUBY] |
| should work with file URLs | [MISSING IN RUBY] |
| Request.continue > should fail if the header value is invalid | [MISSING IN RUBY] |
| Request.respond > should report correct content-length header with string | [MISSING IN RUBY] |
| Request.respond > should report correct content-length header with buffer | [MISSING IN RUBY] |
| Request.respond > should report correct encoding from page when content-type is set | [MISSING IN RUBY] |

---

## 18. screenshot.spec.ts vs screenshot_spec.rb

### Ported Tests
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| Page.screenshot > should work | should work | [PORTED] |
| Page.screenshot > should clip rect | should clip rect | [PORTED] |
| Page.screenshot > should use scale for clip | should use scale for clip | [PORTED] |
| Page.screenshot > should run in parallel | should run in parallel | [PORTED] |
| Page.screenshot > should take fullPage screenshots | should take fullPage screenshots | [PORTED] |
| Page.screenshot > should work with webp | should work with webp | [PORTED] |
| Page.screenshot > should work in "fromSurface: false" mode | should work in "fromSurface: false" mode | [PORTED] |
| ElementHandle.screenshot > should work | should work | [PORTED] |
| ElementHandle.screenshot > should take into account padding and border | should take into account padding and border | [PORTED] |
| ElementHandle.screenshot > should capture full element when larger than viewport | should capture full element when larger than viewport | [PORTED] |
| ElementHandle.screenshot > should scroll element into view | should scroll element into view | [PORTED] |
| ElementHandle.screenshot > should work with a rotated element | should work with a rotated element | [PORTED] |
| ElementHandle.screenshot > should fail to screenshot a detached element | should fail to screenshot a detached element | [PORTED] |
| ElementHandle.screenshot > should work for an element with fractional dimensions | should work for an element with fractional dimensions | [PORTED] |
| ElementHandle.screenshot > should work for an element with an offset | should work for an element with an offset | [PORTED] |

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| Page.screenshot > should get screenshot bigger than the viewport | [MISSING IN RUBY] |
| Page.screenshot > should clip clip bigger than the viewport without "captureBeyondViewport" | [MISSING IN RUBY] |
| Page.screenshot > should take fullPage screenshots without captureBeyondViewport | [MISSING IN RUBY] |
| Page.screenshot > should run in parallel in multiple pages | [MISSING IN RUBY] (commented out) |
| Page.screenshot > should work with odd clip size on Retina displays | [MISSING IN RUBY] (commented out) |
| Page.screenshot > should return base64 | [MISSING IN RUBY] (commented out) |
| Page.screenshot > should take fullPage screenshots when defaultViewport is null | [MISSING IN RUBY] |
| Page.screenshot > should restore to original viewport size after taking fullPage screenshots when defaultViewport is null | [MISSING IN RUBY] |
| ElementHandle.screenshot > should work with a null viewport | [MISSING IN RUBY] |
| ElementHandle.screenshot > should not hang with zero width/height element | [MISSING IN RUBY] |
| ElementHandle.screenshot > should run in parallel in multiple pages | [MISSING IN RUBY] |
| ElementHandle.screenshot > should run in parallel with page.close() | [MISSING IN RUBY] |
| ElementHandle.screenshot > should use element clip | [MISSING IN RUBY] |
| Cdp > should allow transparency | [MISSING IN RUBY] (commented out) |
| Cdp > should render white background on jpeg file | [MISSING IN RUBY] (commented out) |

### Ruby Only
| Ruby Test | Notes |
|-----------|-------|
| full_page > keep input value (with Mobile viewport) | [RUBY ONLY] - Regression test for issue #96 |
| full_page > keep input value (with 1200x1200 viewport) | [RUBY ONLY] - Regression test for issue #96 |

---

## 19. waittask.spec.ts vs wait_task_spec.rb

### Ported Tests
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| Page.waitFor > should wait for selector | should wait for selector | [PORTED] |
| Page.waitFor > should wait for an xpath | should wait for an xpath | [PORTED] |
| Page.waitFor > should timeout | should timeout | [PORTED] |
| Page.waitFor > should work with multiline body | should work with multiline body | [PORTED] |
| Page.waitFor > should wait for predicate | should wait for predicate | [PORTED] |
| Page.waitFor > should wait for predicate with arguments | should wait for predicate with arguments | [PORTED] |
| Frame.waitForSelector > should immediately resolve promise if node exists | should immediately resolve promise if node exists | [PORTED] |
| Frame.waitForSelector > should work with removed MutationObserver | should work with removed MutationObserver | [PORTED] |
| Frame.waitForSelector > should resolve promise when node is added | should resolve promise when node is added | [PORTED] |
| Frame.waitForSelector > should work when node is added through innerHTML | should work when node is added through innerHTML | [PORTED] |
| Frame.waitForSelector > Page.waitForSelector is shortcut for main frame | Page.waitForSelector is shortcut for main frame | [PORTED] |
| Frame.waitForSelector > should run in specified frame | should run in specified frame | [PORTED] |
| Frame.waitForSelector > should throw when frame is detached | should throw when frame is detached | [PORTED] |
| Frame.waitForSelector > should wait for visible | should wait for visible | [PORTED] |
| Frame.waitForSelector > hidden should wait for display: none | hidden should wait for display: none | [PORTED] |
| Frame.waitForSelector > hidden should wait for removal | hidden should wait for removal | [PORTED] |
| Frame.waitForSelector > should return null if waiting to hide non-existing element | should return null if waiting to hide non-existing element | [PORTED] |
| Frame.waitForSelector > should respect timeout | should respect timeout | [PORTED] |
| Frame.waitForSelector > should return the element handle | should return the element handle | [PORTED] |

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| Frame.waitForFunction > should accept a string | [MISSING IN RUBY] |
| Frame.waitForFunction > should work when resolved right before execution context disposal | [MISSING IN RUBY] |
| Frame.waitForFunction > should poll on interval | [MISSING IN RUBY] |
| Frame.waitForFunction > should poll on mutation | [MISSING IN RUBY] |
| Frame.waitForFunction > should poll on mutation async | [MISSING IN RUBY] |
| Frame.waitForFunction > should poll on raf | [MISSING IN RUBY] |
| Frame.waitForFunction > should poll on raf async | [MISSING IN RUBY] |
| Frame.waitForFunction > should work with strict CSP policy | [MISSING IN RUBY] |
| Frame.waitForFunction > should throw negative polling interval | [MISSING IN RUBY] |
| Frame.waitForFunction > should return the success value as a JSHandle | [MISSING IN RUBY] |
| Frame.waitForFunction > should return the window as a success value | [MISSING IN RUBY] |
| Frame.waitForFunction > should accept ElementHandle arguments | [MISSING IN RUBY] |
| Frame.waitForFunction > should respect timeout | [MISSING IN RUBY] |
| Frame.waitForFunction > should respect default timeout | [MISSING IN RUBY] |
| Frame.waitForFunction > should disable timeout when its set to 0 | [MISSING IN RUBY] |
| Frame.waitForFunction > should survive cross-process navigation | [MISSING IN RUBY] |
| Frame.waitForFunction > should survive navigations | [MISSING IN RUBY] |
| Frame.waitForFunction > should be cancellable | [MISSING IN RUBY] |
| Frame.waitForFunction > can start multiple tasks without node warnings | [MISSING IN RUBY] |
| Frame.waitForSelector > should be cancellable | [MISSING IN RUBY] |
| Frame.waitForSelector > should work when node is added in a shadow root | [MISSING IN RUBY] |
| Frame.waitForSelector > should work for selector with a pseudo class | [MISSING IN RUBY] |
| Frame.waitForSelector > should survive cross-process navigation | [MISSING IN RUBY] (commented out) |
| Frame.waitForSelector > should wait for element to be visible (without DOM mutations) | [MISSING IN RUBY] |
| Frame.waitForSelector > should wait for element to be visible (bounding box) | [MISSING IN RUBY] |
| Frame.waitForSelector > should wait for element to be visible recursively | [MISSING IN RUBY] (commented out) |
| Frame.waitForSelector > should wait for element to be hidden (visibility) | [MISSING IN RUBY] (commented out) |
| Frame.waitForSelector > should wait for element to be hidden (bounding box) | [MISSING IN RUBY] |
| Frame.waitForSelector > should have an error message specifically for awaiting an element to be hidden | [MISSING IN RUBY] (commented out) |
| Frame.waitForSelector > should respond to node attribute mutation | [MISSING IN RUBY] (commented out) |
| Frame.waitForSelector > should have correct stack trace for timeout | [MISSING IN RUBY] (commented out) |
| Frame.waitForSelector > xpath > (all tests) | [MISSING IN RUBY] |
| protocol timeout > should error if underlying protocol command times out with raf polling | [MISSING IN RUBY] |

---

## 20. worker.spec.ts vs worker_spec.rb

### Ported Tests
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| Page.workers | Page.workers | [PORTED] |
| should emit created and destroyed events | should emit created and destroyed events | [PORTED] |
| should report console logs | should report console logs | [PORTED] |
| should work with console logs | should work with console logs | [PORTED] |
| should have an execution context | should have an execution context | [PORTED] |
| should report errors | should report errors | [PORTED] |
| can be closed | can be closed | [PORTED] |
| should work with waitForNetworkIdle | should work with waitForNetworkIdle | [PORTED] |
| should retrieve body for main worker requests | should retrieve body for main worker requests | [PORTED] |

**Note:** All worker tests are faithfully ported.

---

---

## 21. emulation.spec.ts vs emulation_spec.rb

### Ported Tests (Comprehensive)
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| Page.viewport > should get the proper viewport size | should get the proper viewport size | [PORTED] |
| Page.viewport > should support mobile emulation | should support mobile emulation | [PORTED] |
| Page.viewport > should support touch emulation | should support touch emulation | [PORTED] |
| Page.viewport > should be detectable by Modernizr | should be detectable by Modernizr | [PORTED] |
| Page.viewport > should detect touch when applying viewport with touches | should detect touch when applying viewport with touches | [PORTED] |
| Page.viewport > should support landscape emulation | should support landscape emulation | [PORTED] |
| Page.emulate > should work | should work | [PORTED] |
| Page.emulate > should support clicking | should support clicking | [PORTED] |
| Page.emulateMediaType > should work | should work | [PORTED] |
| Page.emulateMediaType > should throw in case of bad argument | should throw in case of bad argument | [PORTED] |
| Page.emulateMediaFeatures > should work | should work | [PORTED] |
| Page.emulateMediaFeatures > should throw in case of bad argument | should throw in case of bad argument | [PORTED] |
| Page.emulateTimezone > should work | should work | [PORTED] |
| Page.emulateTimezone > should throw for invalid timezone IDs | should throw for invalid timezone IDs | [PORTED] |
| Page.emulateVisionDeficiency > should work | should work | [PORTED] |
| Page.emulateVisionDeficiency > should throw for invalid vision deficiencies | should throw for invalid vision deficiencies | [PORTED] |
| Page.emulateNetworkConditions > should change navigator.connection.effectiveType | should change navigator.connection.effectiveType | [PORTED] |
| Page.emulateCPUThrottling > should change the CPU throttling rate successfully | should change the CPU throttling rate successfully | [PORTED] |

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| Page.viewport > should update media queries when resolution changes | [MISSING IN RUBY] |
| Page.viewport > should load correct pictures when emulation dpr | [MISSING IN RUBY] |
| Page.emulate > should work twice on about:blank | [MISSING IN RUBY] |
| Page.emulateNetworkConditions > should support offline | [MISSING IN RUBY] |
| Page.emulateFocusedPage > should emulate focus | [MISSING IN RUBY] |
| Page.emulateFocusedPage > should reset focus | [MISSING IN RUBY] |

---

## 22. touchscreen.spec.ts vs touchscreen_spec.rb

### Ported Tests (Comprehensive)
All touchscreen tests are faithfully ported including:
- `Touchscreen.prototype.tap` - basic tap, tap with existing touch
- `Touchscreen.prototype.touchMove` - basic move, two touches, three touches, move separately
- `Touchscreen.prototype.touchEnd` - error handling

---

## 23. drag-and-drop.spec.ts vs drag_and_drop_spec.rb

### Ported Tests (All ported)
| Node.js Test | Ruby Test | Status |
|--------------|-----------|--------|
| should emit a dragIntercepted event when dragged | should emit a dragIntercepted event when dragged | [PORTED] |
| should emit a dragEnter | should emit a dragEnter | [PORTED] |
| should emit a dragOver event | should emit a dragOver event | [PORTED] |
| can be dropped | can be dropped | [PORTED] |
| can be dragged and dropped with a single function | can be dragged and dropped with a single function | [PORTED] |

### Ruby Only
| Ruby Test | Notes |
|-----------|-------|
| should throw an exception if not enabled before usage | [RUBY ONLY] - Additional validation test |
| can be disabled | [RUBY ONLY] - Tests disabling drag interception |

---

## 24. coverage.spec.ts vs coverage_spec.rb

### Ported Tests (Comprehensive)
All JSCoverage and CSSCoverage tests are ported including:
- Basic coverage collection
- Source URL reporting
- Anonymous scripts handling
- Multiple scripts/stylesheets
- Range reporting
- Media queries
- Reset on navigation
- Raw script coverage

### Ruby Only
| Ruby Test | Notes |
|-----------|-------|
| should work with block | [RUBY ONLY] - Ruby block-style API |

---

## 25. tracing.spec.ts vs tracing_spec.rb

### Ported Tests (All ported)
All tracing tests are faithfully ported.

---

## 26. oopif.spec.ts vs oopif_spec.rb

### Ported Tests (Comprehensive)
Most OOPIF tests are ported including:
- OOP iframes vs normal iframes
- Navigation within OOP iframes
- Frames within OOP frames
- Detached OOP frames
- Evaluating in OOP iframes
- clickablePoint, boundingBox, boxModel for OOPIF elements

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| should recover cross-origin frames on reconnect | [MISSING IN RUBY] |
| should detect existing OOPIFs when Puppeteer connects | [MISSING IN RUBY] |
| should exposeFunction on a page with a PDF viewer | [MISSING IN RUBY] |
| should evaluate on a page with a PDF viewer | [MISSING IN RUBY] |
| should support evaluateOnNewDocument | [MISSING IN RUBY] |
| should support removing evaluateOnNewDocument scripts | [MISSING IN RUBY] |
| should support exposeFunction | [MISSING IN RUBY] |
| should support removing exposed function | [MISSING IN RUBY] |
| should report google.com frame | [MISSING IN RUBY] |
| should expose events within OOPIFs | [MISSING IN RUBY] |
| should retrieve body for OOPIF document requests | [MISSING IN RUBY] |

---

## 27. aria_query_handler.spec.ts vs aria_query_handler_spec.rb

### Ported Tests (Core functionality ported)
- parseAriaSelector tests
- queryOne tests (find by role, name, first matching)
- queryAll tests
- queryAllArray tests
- waitForSelector (aria) - basic waiting, visibility

### Missing in Ruby
| Node.js Test | Notes |
|--------------|-------|
| waitForSelector > should work for ElementHandle.waitForSelector | [MISSING IN RUBY] |
| waitForSelector > should survive cross-process navigation | [MISSING IN RUBY] |
| waitForSelector > should wait for visible recursively | [MISSING IN RUBY] |
| waitForSelector > hidden should wait for visibility: hidden | [MISSING IN RUBY] |
| waitForSelector > should have error message specifically for awaiting element | [MISSING IN RUBY] |
| waitForSelector > should respond to node attribute mutation | [MISSING IN RUBY] |
| waitForSelector > should have correct stack trace for timeout | [MISSING IN RUBY] |
| Chromium web test queries | [MISSING IN RUBY] |

---

## Summary

### Overall Statistics

| Category | Count |
|----------|-------|
| Node.js spec files | 47 |
| Ruby spec files | 40 |
| Fully ported spec files | 27 |
| Partially ported spec files | 4 |
| Missing spec files (important) | 5 |
| Low priority/N/A spec files | 11 |

### Spec Files Status Summary

**Fully Ported (27):**
aria_query_handler, browser, browser_context, browser_context_cookies, click, connect (in launcher), cookies, coverage, defaultbrowsercontext (in browser_context), dialog, drag_and_drop, element_handle, emulation, evaluation, frame, idle_override, input, js_handle, keyboard, launcher, mouse, oopif, page, query_handler, query_selector, request_interception, request_interception_experimental, screenshot, touchscreen, tracing, worker

**Partially Ported (4):**
- navigation.spec.ts → Some in page_spec.rb
- network.spec.ts → Minimal coverage
- target.spec.ts → Some in browser_spec.rb, launcher_spec.rb
- waittask.spec.ts → Many Frame.waitForFunction tests missing

**Missing - High Priority (5):**
1. **accessibility.spec.ts** - Accessibility API not implemented
2. **locator.spec.ts** - Locator API not implemented
3. **download.spec.ts** - Download handling not implemented
4. **proxy.spec.ts** - Proxy support not implemented
5. **autofill.spec.ts** - Autofill not implemented

**Low Priority/N/A (11):**
acceptInsecureCerts, bluetooth-emulation, debugInfo, device-request-prompt, fixtures, headful, injected, stacktrace, webExtension, webgl

### Priority Recommendations

#### High Priority (Core functionality gaps)
1. **Accessibility API** - Add `Page#accessibility` and port accessibility.spec.ts
2. **Locator API** - Implement Locator class and port locator.spec.ts
3. **network.spec.ts** - Ruby has minimal network tests; many tests need porting
4. **navigation.spec.ts** - Many edge cases missing
5. **waittask.spec.ts** - Many `Frame.waitForFunction` tests missing

#### Medium Priority
1. **download.spec.ts** - File download handling
2. **proxy.spec.ts** - Proxy configuration support
3. **target.spec.ts** - Complete target management tests
4. **oopif.spec.ts** - Several advanced OOPIF tests missing

#### Low Priority (Feature-specific)
1. AbortSignal/cancellation tests (Ruby doesn't support this pattern)
2. Firefox-specific tests (puppeteer-ruby focuses on Chrome)
3. WebGL, Bluetooth, Web Extension tests

### Files that may need `_ext_spec.rb` split
The following Ruby-only tests should potentially be moved to extension spec files:
- `cookies_spec.rb` - "should fail if specifying wrong cookie" (Ruby-specific validation)
- `screenshot_spec.rb` - Issue #96 regression tests
- `launcher_spec.rb` - Ruby-specific API tests (default_args, product)
- `element_handle_spec.rb` - XPath-specific tests
- `drag_and_drop_spec.rb` - Ruby-specific validation tests
- `coverage_spec.rb` - Ruby block-style API tests
