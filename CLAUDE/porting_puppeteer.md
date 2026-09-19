# Porting from TypeScript Puppeteer

This guide explains how to port features from the TypeScript Puppeteer to puppeteer-ruby.

## Workflow Overview

1. **Pin the upstream revision and scope** in [puppeteer/puppeteer](https://github.com/puppeteer/puppeteer)
2. **Trace the public API through its implementation**, dependencies, and tests
3. **Implement in Ruby** while preserving observable behavior
4. **Port the tests and challenge the changed behavior** using the guidance below
5. **Regenerate API coverage and report verified and unresolved scope**

## Porting and Review Contract

This contract applies to both implementation and review. Local guides and migration
tables are navigation aids, not an exhaustive specification of supported behavior.
Silence in a document, a missing Ruby method, a difficult test, or a missing local
dependency does not authorize omitting behavior, adding a no-op implementation,
or replacing a regression with a stubbed success. Follow the user's requested scope
and explicit repository exclusions (Chrome/CDP only; no AbortSignal).

### Establish the scope before claiming completion

- Use the revision/range specified by the task. If the task says latest/main,
  resolve it to a SHA and record that SHA. Compare implementation, tests, assets,
  and test expectations at the same revision.
- For a multi-feature port, keep a mapping in the PR description or review notes:
  upstream change and regression cases, Ruby implementation/specs, disposition,
  and evidence. Include colocated unit tests under `packages/puppeteer-core/src/`,
  not just browser tests under `test/src/`.
- Distinguish **implemented and verified**, **already in the base**, **explicitly
  excluded**, and **unresolved**. Existing coverage needs a matching scenario and
  assertions, not just a similar test title. Skipped or unrun tests are not verified.
- Trace prerequisites and follow-up fixes across `api/`, `cdp/`, `common/`,
  `node/`, and `injected/`. A missing prerequisite API is work to account for,
  not evidence that an applicable regression is TypeScript-only.
- Ruby adaptations may replace language mechanisms, but must retain their
  observable contract. For example, document and test the Ruby stream/iteration
  or resource-lifetime equivalent instead of silently dropping it with a JS type.
  Record intentional deviations and their rationale; do not claim full parity
  or close the tracking issue while applicable requested items remain unresolved.

### Preserve behavior, not only CDP command names

Review the dimensions relevant to the changed feature; this is not a requirement
to add unrelated tests or exhaustively multiply every option in the library.

| Dimension | What to preserve and challenge |
| --- | --- |
| Validation and side effects | Validate before opening/truncating files or starting processes when upstream does. Invalid inputs must preserve existing data and state. |
| Completion and cleanup | Match the whole guarded operation, not just a flag assignment. A second concurrent stop/close must wait for completion when upstream does. Exercise failure/disconnect paths without masking the original error. |
| Collections and streams | Preserve Set deduplication, destination removal, chunk delivery, iteration, and close semantics. An Array or an all-data buffer is not automatically equivalent. |
| Option combinations | Preserve omission, defaults, and precedence. Exercise branches such as launch/connect, WebSocket/pipe, and follow-symlinks/overwrite when touched. |
| File operations | Compare flags, creation permissions, exclusive creation, and resource ownership in each changed branch. A rejected symlink alone does not establish file-policy parity. |
| Logger propagation | Trace factories and sinks through all affected constructors and error paths, including disabled channels, argument types, and factory lifetime. A successful SEND log does not cover error logging. |
| Static API data | Compare every added descriptor field with the pinned source, rather than checking only a few representative values. |

Use the pinned upstream as the control: do not report a behavior shared with
upstream as a Ruby porting regression. Separate newly introduced defects from
pre-existing gaps that the requested port is meant to resolve.

### Completion evidence

Run the relevant regression and boundary tests, plus the repository checks
appropriate to the change. Record the commands, Ruby/browser versions, actual
results, pending/skipped cases, and limitations. Where a regression could pass
without the fix, use a targeted negative control (the pre-fix implementation or a
temporarily disabled fix in an isolated checkout) and confirm it fails for the
intended reason. A green suite or matching example count alone does not prove
fidelity.

Check CI on the PR's actual head. Call a failure pre-existing only with evidence
such as the same reproduction on the base under matching conditions; otherwise
report its attribution as unresolved. For documentation-only changes, check
links, examples, and consistency with the current code; state that runtime tests
were not run instead of implying behavioral validation.

## Step 1: Find the TypeScript Source

Puppeteer source is organized in:

```
packages/puppeteer-core/src/
├── api/                    # Public API definitions
│   ├── Page.ts
│   ├── Frame.ts
│   └── ...
├── cdp/                    # CDP implementation
│   ├── Page.ts
│   ├── Frame.ts
│   └── ...
├── bidi/                   # BiDi implementation (not needed for this project)
└── common/                 # Shared utilities
```

For CDP-based puppeteer-ruby, use `cdp/` as the primary implementation source,
and trace the public API and shared helpers that determine its behavior.

### Example: Finding waitForSelector

```
packages/puppeteer-core/src/
├── api/Frame.ts            # waitForSelector API definition
└── cdp/Frame.ts            # CDP implementation
```

## Step 2: Understand CDP Calls

Read the TypeScript code to understand what CDP commands are used.

### TypeScript Example

```typescript
// From packages/puppeteer-core/src/cdp/Frame.ts
async click(selector: string, options?: ClickOptions): Promise<void> {
  const handle = await this.$(selector);
  await handle?.click(options);
  await handle?.dispose();
}
```

This shows:
1. Query selector to find element
2. Click the element
3. Dispose the handle

Look deeper to find CDP calls:

```typescript
// From ElementHandle
async click(options: ClickOptions = {}): Promise<void> {
  await this.scrollIntoViewIfNeeded();
  const {x, y} = await this.clickablePoint(options.offset);
  await this.page.mouse.click(x, y, options);
}

// From Mouse
async click(x: number, y: number, options: MouseClickOptions = {}): Promise<void> {
  await this.#client.send('Input.dispatchMouseEvent', {
    type: 'mousePressed',
    // ...
  });
}
```

## Step 3: Implement in Ruby

Translate the TypeScript to idiomatic Ruby:

### Ruby Implementation

```ruby
# lib/puppeteer/frame.rb
def click(selector, delay: nil, button: nil, click_count: nil, count: nil)
  handle = query_selector(selector)
  raise ArgumentError, "No element found for selector: #{selector}" unless handle

  begin
    handle.click(delay: delay, button: button, click_count: click_count, count: count)
  ensure
    handle.dispose
  end
end

# lib/puppeteer/element_handle.rb
def click(delay: nil, button: nil, click_count: nil, count: nil, offset: nil)
  scroll_into_view_if_needed
  point = clickable_point(offset: offset)
  @page.mouse.click(point.x, point.y,
    delay: delay,
    button: button,
    click_count: click_count,
    count: count
  )
end

# lib/puppeteer/mouse.rb
def click(x, y, delay: nil, button: nil, click_count: nil, count: nil)
  move(x, y)
  down(button: button, click_count: click_count)
  Puppeteer::AsyncUtils.sleep_seconds(delay / 1000.0) if delay
  up(button: button, click_count: click_count)
end
```

Note: `click_count` is deprecated (mirrors Puppeteer's `clickCount` deprecation). Use `count` for multiple clicks and let `click_count` default to `count`.

### Mouse Button Types

The `button` parameter accepts these values (defined in `Puppeteer::Mouse::Button`):

| Value | Button Code | Description |
|-------|-------------|-------------|
| `'left'` | 0 | Primary button (default) |
| `'right'` | 2 | Secondary button (context menu) |
| `'middle'` | 1 | Auxiliary button (wheel click) |
| `'back'` | 3 | Browser back button |
| `'forward'` | 4 | Browser forward button |

### Key Translation Patterns

| TypeScript | Ruby |
|------------|------|
| `async/await` | Direct calls inside the reactor; `.wait` for Async tasks/promises |
| `Promise.all([...])` | Start concurrent Async tasks and join with `Puppeteer::AsyncUtils.await_promise_all`; do not serialize operations whose overlap matters |
| `options: {...}` | Keyword arguments `(key: value)` |
| `options?.key` | `options&.[](:key)` or explicit nil check |
| `throw new Error()` | `raise ErrorClass, 'message'` |
| `try/finally` | `begin/ensure` |

## Step 4: Port Tests

Find corresponding tests in Puppeteer's test suite:

```
test/src/                    # Test specs
├── keyboard.spec.ts
├── click.spec.ts
├── page.spec.ts
└── ...
test/assets/                 # Test fixtures (HTML, JS, CSS)
├── input/
│   ├── keyboard.html
│   ├── textarea.html
│   └── button.html
└── ...
```

### Test File Comparison Workflow

To verify test alignment between TypeScript and Ruby:

1. **Fetch TypeScript test structure at the pinned SHA:**
   ```
   https://raw.githubusercontent.com/puppeteer/puppeteer/<upstream-sha>/test/src/page.test.ts
   ```
   Use the filenames present at that revision; older releases use `*.spec.ts`.

2. **Compare describe/it block titles** between files, checking:
   - Order matches
   - Names match (accounting for Ruby naming conventions)
   - No missing tests
   - Same public API entry point, setup, options, action sequence, and assertions
   - Same surrounding hooks and platform/browser expectations

3. **Handle differences:**
   - **Language-specific mechanisms**: Test the equivalent Ruby behavior; explicitly excluded features such as AbortSignal must be marked with that specific reason
   - **Applicable missing behavior**: Implement it and its prerequisites; if still incomplete, record it as unresolved, not ported
   - **Ruby-only tests**: Move to `*_ext_spec.rb` file

### Skips, expected failures, and test substitutions

- Preserve upstream inputs and preconditions. Do not change dimensions, timeouts,
  fixtures, assertions, or an option's enclosing context just to pass locally.
  Moving a test out of a `followSymlinks: false` group, for example, changes the
  branch exercised even when its body and title remain the same.
- A new skip/pending/platform/version guard must cite an explicit repository
  exclusion, the pinned upstream expectation, or a reproduced environment/browser
  limitation with a tracking reference. Record the affected conditions and what
  enables the test to run again. Scope it to those conditions, retain the test
  body, and expose it in the completion report. `Not implemented` alone is not a
  justification for treating a requested port as complete.
- Distinguish upstream **SKIP** from **FAIL** or **FAIL/PASS**. Preserve execution
  where upstream executes the test. If the Ruby harness cannot represent that
  expectation, document the limitation and retain an executable reproducer;
  a blanket skip must not silently replace expected-failure coverage.
- Preserve the tested API layer. If upstream tests `page.record` through a mock
  Page, do not substitute direct construction of its internal recorder and claim
  equivalent validation of the public method. Keep real-browser regression tests
  as real-browser tests. Payload spies and protocol fakes can supplement them.
- Fakes must preserve the failure/timing behavior being tested. Use deferred
  responses to hold an operation in flight when testing concurrent stop or
  disconnect; an immediately completed fake proves only sequential behavior.
  See [test-double guidance](testing.md#test-doubles-and-regression-evidence).

### Key Test File Pairs

| TypeScript | Ruby | Ruby Extension |
|------------|------|----------------|
| `test/src/page.spec.ts` | `spec/integration/page_spec.rb` | `page_ext_spec.rb` |
| `test/src/frame.spec.ts` | `spec/integration/frame_spec.rb` | `frame_ext_spec.rb` |
| `test/src/keyboard.spec.ts` | `spec/integration/keyboard_spec.rb` | `keyboard_ext_spec.rb` |
| `test/src/click.spec.ts` | `spec/integration/click_spec.rb` | - |

Note: Some tests (e.g., `BrowserContext#override_permissions`) may be split into separate files like `browser_context_permissions_spec.rb` if they represent distinct features.

### Porting Principles

1. **Preserve test order** - Keep `it` blocks in the exact same order as upstream
2. **Preserve test names** - Use the same test descriptions
3. **Preserve test structure** - Don't add extra `context`/`describe` wrappers
4. **Preserve asset files** - Keep `spec/assets/` identical to upstream `test/assets/`
5. **Separate Ruby-specific tests** - Move Ruby-only features to `*_ext_spec.rb` files

## Fidelity Notes

- `JSHandle#json_value`: Node.js normalizes CDP errors like "Object reference chain is too long" and
  "Object couldn't be returned by value" via `ExecutionContext#rewriteError` to `undefined`. The
  Ruby port keeps the same behavior by rescuing in `JSHandle#json_value` and returning `nil`.
- PSelectors/PQueryHandler: The Ruby PSelector path relies on `PQueryHandler` with the same
  `IDENT_TOKEN_START` regex behavior as upstream. Keep the CSS query selector JS in a single-quoted
  heredoc so the regex survives Ruby parsing. `wait_for` should use `Frame#default_timeout` to match
  Node's timeout settings.

### Ruby-Specific Tests (`*_ext_spec.rb`)

When porting tests, separate Ruby-only features into dedicated extension spec files:

```
spec/integration/
├── keyboard_spec.rb       # Upstream port (faithful to test/src/keyboard.spec.ts)
└── keyboard_ext_spec.rb   # Ruby-specific extensions
```

**Ruby-specific features to separate:**
- Block DSL syntax: `page.keyboard { type_text('hello'); press('Enter') }`
- Nested block syntax: `press('Shift') { press('Comma') }`
- Other Ruby idioms not present in upstream

**Example `*_ext_spec.rb` structure:**

```ruby
RSpec.describe 'Keyboard (white-box / Ruby-specific)' do
  def with_textarea(&block)
    with_test_state do |page:, **|
      page.evaluate(<<~JAVASCRIPT)
      () => {
        const textarea = document.createElement('textarea');
        document.body.appendChild(textarea);
        textarea.focus();
      }
      JAVASCRIPT
      block.call(page: page)
    end
  end

  it 'should input < by pressing Shift + , using press with block' do
    with_textarea do |page:|
      page.keyboard do
        press('Shift') { press('Comma') }
      end
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq('<')
    end
  end
end
```

### TypeScript to Ruby Translation

#### Test State Setup

Use `with_test_state` block to access test helpers explicitly:

```ruby
RSpec.describe Puppeteer::Page do
  it 'should click button' do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/input/button.html")
      page.click('button')
      expect(page.evaluate('() => globalThis.result')).to eq('Clicked')
    end
  end
end
```

Available block arguments:
- `page:` - Current `Puppeteer::Page` instance
- `server:` - Test server (use `server.prefix` for URL base)
- `https_server:` - HTTPS test server
- `browser:` - Browser instance
- `browser_context:` - BrowserContext instance

**Do NOT use** `include_context 'with test state'` - prefer explicit `with_test_state` blocks.

#### Basic Test Structure

```typescript
// TypeScript
describe('Keyboard', function () {
  it('should type into a textarea', async () => {
    await page.evaluate(() => {
      const textarea = document.createElement('textarea');
      document.body.appendChild(textarea);
      textarea.focus();
    });
    const text = 'Hello world. I am the text that was typed!';
    await page.keyboard.type(text);
    expect(
      await page.evaluate(() => document.querySelector('textarea').value)
    ).toBe(text);
  });
});
```

```ruby
# Ruby
RSpec.describe Puppeteer::Keyboard do
  it 'should type into a textarea' do
    with_test_state do |page:, **|
      page.evaluate(<<~JAVASCRIPT)
      () => {
        const textarea = document.createElement('textarea');
        document.body.appendChild(textarea);
        textarea.focus();
      }
      JAVASCRIPT
      text = 'Hello world. I am the text that was typed!'
      page.keyboard.type_text(text)
      expect(page.evaluate("() => document.querySelector('textarea').value")).to eq(text)
    end
  end
end
```

#### Method Name Mappings

| TypeScript | Ruby |
|------------|------|
| `page.keyboard.type(text)` | `page.keyboard.type_text(text)` |
| `page.$(selector)` | `page.query_selector(selector)` |
| `page.$$(selector)` | `page.query_selector_all(selector)` |
| `page.$eval(sel, fn)` | `page.eval_on_selector(sel, fn)` |
| `page.$$eval(sel, fn)` | `page.eval_on_selector_all(sel, fn)` |
| `element.press(key, {text: ...})` | `element.press(key)` (text option ignored) |

#### Assertion Mappings

| TypeScript (Jest) | Ruby (RSpec) |
|-------------------|--------------|
| `expect(x).toBe(y)` | `expect(x).to eq(y)` |
| `expect(x).toEqual(y)` | `expect(x).to eq(y)` |
| `expect(fn).toThrow()` | `expect { fn }.to raise_error` |
| `expect(fn).toThrow('msg')` | `expect { fn }.to raise_error(/msg/)` |

#### Platform-Specific Tests

```typescript
// TypeScript
it('should press the meta key', async () => {
  if (os.platform() !== 'darwin') {
    return;
  }
  // test body
});
```

```ruby
# Ruby
it 'should press the meta key' do
  skip('This test only runs on macOS.') unless Puppeteer.env.darwin?
  # test body
end
```

#### JavaScript Object Comparison

```typescript
// TypeScript
expect(
  await page.$eval('textarea', (textarea) => ({
    value: textarea.value,
    inputs: globalThis.inputCount,
  }))
).toEqual({ value: '嗨', inputs: 1 });
```

```ruby
# Ruby - JS object keys become string keys
result = page.eval_on_selector('textarea', <<~JAVASCRIPT)
(textarea) => ({
  value: textarea.value,
  inputs: globalThis.inputCount,
})
JAVASCRIPT
expect(result).to eq({ 'value' => '嗨', 'inputs' => 1 })
```

#### Nested iframes with srcdoc

```typescript
// TypeScript
await page.setContent(`
  <iframe srcdoc="<iframe name='test' srcdoc='<textarea></textarea>'></iframe>"></iframe>
`);
const frame = await page.waitForFrame((frame) => frame.name() === 'test');
```

```ruby
# Ruby
page.set_content(<<~HTML)
  <iframe
    srcdoc="<iframe name='test' srcdoc='<textarea></textarea>'></iframe>"
  ></iframe>
HTML
frame = page.wait_for_frame(predicate: ->(frame) { frame.name == 'test' })
```

### Test Asset Policy

Assets in `spec/assets/` must be **identical** to upstream `test/assets/`:

```bash
# Use the SHA recorded for this port, not moving main.
UPSTREAM_SHA='replace-with-the-recorded-upstream-sha'
wget -O spec/assets/input/keyboard.html \
  "https://raw.githubusercontent.com/puppeteer/puppeteer/${UPSTREAM_SHA}/test/assets/input/keyboard.html"

# Verify content matches
diff spec/assets/input/keyboard.html <(curl -fsSL "https://raw.githubusercontent.com/puppeteer/puppeteer/${UPSTREAM_SHA}/test/assets/input/keyboard.html")
```

**Never hand-edit asset files.** If a test needs different HTML:
1. Check if upstream has the asset you need
2. If not, create a new file with a different name
3. If upstream changes, re-fetch the asset

### Common Gotchas

#### 0. AbortSignal Not Supported

**Do NOT port `signal` parameters from upstream Puppeteer.**

```typescript
// TypeScript - has signal parameter
async click(options?: {signal?: AbortSignal}): Promise<void> {
  // ...
}
```

```ruby
# Ruby - do NOT include signal parameter
def click(delay: nil, button: nil)
  # ...
end
```

Ruby's concurrency model doesn't align with JavaScript's AbortController/AbortSignal pattern. Use timeout parameters instead for cancellation.

#### 1. Event Type Differences

Upstream keyboard tests use `input` events, not `keypress`:

```javascript
// Correct (upstream uses this)
textarea.addEventListener('input', event => {
  log('input:', event.data, event.inputType, event.isComposing);
});

// Incorrect (older puppeteer-ruby had this)
textarea.addEventListener('keypress', event => {
  log('Keypress:', event.key, event.code, event.which, event.charCode);
});
```

#### 2. Modifier Key Mapping

```ruby
# Correct: Meta on macOS, Control elsewhere
cmd_key = Puppeteer.env.darwin? ? 'Meta' : 'Control'

# Wrong: reversed mapping
cmd_key = Puppeteer.env.darwin? ? 'Control' : 'Meta'
```

#### 3. Loop Iteration

```typescript
// TypeScript
for (const char of 'World!') {
  await page.keyboard.press('ArrowLeft');
}
```

```ruby
# Ruby
'World!'.each_char { page.keyboard.press('ArrowLeft') }
```

## Step 5: Update API Coverage

**Important:** `docs/api_coverage.md` is auto-generated. Do not edit it manually.

To update the API coverage documentation:

```bash
bundle exec ruby development/generate_api_coverage.rb
```

This script reads `development/puppeteer.api.json` and compares it with the Ruby implementation to generate the coverage report.

If an added upstream API is absent from that input, update the versioned metadata
first using the build procedure in [the Check workflow](../.github/workflows/check.yml).
Keep `development/DOCS_VERSION` and `Puppeteer::REF_PUPPETEER_VERSION` aligned;
do not bump the gem release version unless the task calls for a release. Never
hand-add coverage entries that the generator will remove. Review and include the
generated diff, then verify a second generation produces no additional changes.

### How the Coverage Report Works

The script marks methods as:
- `~~methodName~~` (strikethrough) = Not implemented in Ruby
- `methodName` = Implemented with same name
- `methodName => \`#ruby_method\`` = Implemented with different name

The CI workflow "Check / documents updated" verifies this file is up-to-date. If it fails, run the command above and commit the changes.

## Code Style Guidelines

### Keyword Arguments

Use explicit keyword arguments in public APIs:

```ruby
# Good
def goto(url, referer: nil, timeout: nil, wait_until: nil)
end

# Avoid
def goto(url, options = {})
end
```

### Error Handling

```ruby
# Raise specific errors
raise Puppeteer::TimeoutError, "Waiting for selector timed out: #{selector}"

# Use begin/ensure for cleanup
def screenshot(path: nil)
  data = capture_screenshot
  File.write(path, data) if path
  data
ensure
  restore_viewport
end
```

### Nil Handling

```ruby
# Use safe navigation
element&.click

# Explicit nil returns
def query_selector(selector)
  result = @client.send_message('DOM.querySelector', selector: selector)
  return nil if result['nodeId'].zero?
  create_handle(result)
end
```

## Common Gotchas

### 1. JavaScript vs Ruby Truthiness

```typescript
// JavaScript: 0, '', null, undefined are falsy
if (result) { ... }

// Ruby: only nil and false are falsy
if result && !result.zero? && !result.empty?
```

### 2. Parameter Ordering

Puppeteer often uses options objects; Ruby prefers keyword args:

```typescript
// TypeScript
page.screenshot({ path: 'screenshot.png', fullPage: true });

// Ruby
page.screenshot(path: 'screenshot.png', full_page: true)
```

### 3. Async Patterns

```typescript
// TypeScript - concurrent
await Promise.all([
  page.waitForNavigation(),
  page.click('a'),
]);

// Ruby (current) - use block pattern
page.wait_for_navigation do
  page.click('a')
end
```

### 4. Base64 Data

```typescript
// TypeScript
const data = await page.screenshot({ encoding: 'base64' });

// Ruby
data = page.screenshot(encoding: 'base64')
# Returns Base64 string, not binary
```

## Reference Resources

- [Puppeteer TypeScript source](https://github.com/puppeteer/puppeteer/tree/main/packages/puppeteer-core/src)
- [Puppeteer API docs](https://pptr.dev/api)
- [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/)
- [Puppeteer test suite](https://github.com/puppeteer/puppeteer/tree/main/test)
