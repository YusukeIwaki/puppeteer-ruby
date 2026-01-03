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
def click(selector, delay: nil, button: nil, click_count: nil)
  handle = query_selector(selector)
  raise ArgumentError, "No element found for selector: #{selector}" unless handle

  begin
    handle.click(delay: delay, button: button, click_count: click_count)
  ensure
    handle.dispose
  end
end

# lib/puppeteer/element_handle.rb
def click(delay: nil, button: nil, click_count: nil, offset: nil)
  scroll_into_view_if_needed
  point = clickable_point(offset: offset)
  @page.mouse.click(point.x, point.y,
    delay: delay,
    button: button,
    click_count: click_count
  )
end

# lib/puppeteer/mouse.rb
def click(x, y, delay: nil, button: nil, click_count: nil)
  move(x, y)
  down(button: button, click_count: click_count)
  sleep(delay / 1000.0) if delay
  up(button: button, click_count: click_count)
end
```

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
packages/puppeteer-core/test/
├── click.spec.ts
├── page.spec.ts
└── ...
```

### TypeScript Test

```typescript
it('should click the button', async () => {
  await page.goto(server.PREFIX + '/input/button.html');
  await page.click('button');
  expect(await page.evaluate(() => globalThis.result)).toBe('Clicked');
});
```

### Ruby Test

```ruby
it 'clicks the button' do
  sinatra.get('/input/button.html') do
    '<button onclick="window.result = \'Clicked\'">Click me</button>'
  end

  page.goto("#{server_prefix}/input/button.html")
  page.click('button')

  result = page.evaluate('() => window.result')
  expect(result).to eq('Clicked')
end
```

### Test Asset Policy

Use Puppeteer's official test assets when available:

```ruby
# Copy from puppeteer/test/assets/ to spec/assets/
# Don't modify the content - preserve edge cases
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
