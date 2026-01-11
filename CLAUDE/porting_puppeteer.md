# Porting from TypeScript Puppeteer

This guide explains how to port features from the TypeScript Puppeteer to puppeteer-ruby.

## Workflow Overview

1. **Find the TypeScript source** in [puppeteer/puppeteer](https://github.com/puppeteer/puppeteer)
2. **Understand the CDP calls** being made
3. **Implement in Ruby** following existing patterns
4. **Port the tests** from Puppeteer's test suite
5. **Update API coverage** in `docs/api_coverage.md`

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

For CDP-based puppeteer-ruby, focus on the `cdp/` directory.

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
  sleep(delay / 1000.0) if delay
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
| `async/await` | Direct method calls (current), `.wait` (after migration) |
| `Promise.all([...])` | Execute in sequence or use `Concurrent::Promises.zip` |
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

### Porting Principles

1. **Preserve test order** - Keep `it` blocks in the exact same order as upstream
2. **Preserve test names** - Use the same test descriptions
3. **Preserve test structure** - Don't add extra `context`/`describe` wrappers
4. **Preserve asset files** - Keep `spec/assets/` identical to upstream `test/assets/`
5. **Separate Ruby-specific tests** - Move Ruby-only features to `*_ext_spec.rb` files

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
# Fetch asset from upstream
wget -O spec/assets/input/keyboard.html \
  https://raw.githubusercontent.com/puppeteer/puppeteer/main/test/assets/input/keyboard.html

# Verify content matches
diff spec/assets/input/keyboard.html <(curl -s https://raw.githubusercontent.com/puppeteer/puppeteer/main/test/assets/input/keyboard.html)
```

**Never hand-edit asset files.** If a test needs different HTML:
1. Check if upstream has the asset you need
2. If not, create a new file with a different name
3. If upstream changes, re-fetch the asset

### Common Gotchas

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

Edit `docs/api_coverage.md`:

```markdown
## Frame

* $ => `#query_selector`
* $$ => `#query_selector_all`
* click                       # <- Add if newly implemented
...
```

Change:
- `~~methodName~~` (strikethrough) = Not implemented
- `methodName` = Implemented
- `methodName => \`#ruby_method\`` = Implemented with different name

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
