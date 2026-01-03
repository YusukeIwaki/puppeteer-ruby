# Chrome DevTools Protocol (CDP)

This document covers CDP usage in puppeteer-ruby.

## Overview

The Chrome DevTools Protocol (CDP) is the low-level protocol used to communicate with Chrome/Chromium browsers. All browser automation in puppeteer-ruby is done through CDP.

## CDP Domains

CDP is organized into domains, each handling specific functionality:

| Domain | Purpose | Key Commands |
|--------|---------|--------------|
| `Page` | Page lifecycle | `navigate`, `reload`, `setContent` |
| `Runtime` | JavaScript execution | `evaluate`, `callFunctionOn` |
| `DOM` | DOM manipulation | `querySelector`, `getContentQuads` |
| `Input` | User input simulation | `dispatchKeyEvent`, `dispatchMouseEvent` |
| `Network` | Network control | `enable`, `setRequestInterception` |
| `Emulation` | Device emulation | `setDeviceMetricsOverride` |
| `Target` | Target management | `createTarget`, `attachToTarget` |

## Sending CDP Commands

### Basic Pattern

```ruby
# Via CDPSession
result = @client.send_message('Page.navigate', url: 'https://example.com')

# Result is a hash with response data
# { "frameId" => "...", "loaderId" => "..." }
```

### With Timeout

```ruby
# send_message has built-in timeout handling
result = @client.send_message('Page.captureScreenshot', format: 'png')
```

### Error Handling

```ruby
begin
  @client.send_message('Page.navigate', url: 'invalid-url')
rescue Puppeteer::CDPSession::Error => e
  # Handle CDP error
  puts "CDP Error: #{e.message}"
end
```

## Subscribing to Events

### Basic Event Subscription

```ruby
# Subscribe to event (persistent)
@client.on('Network.requestWillBeSent') do |event|
  puts "Request: #{event['request']['url']}"
end

# Subscribe once (auto-removes after first event)
@client.once('Page.loadEventFired') do |event|
  puts "Page loaded!"
end
```

### Enabling Domains

Some CDP domains require explicit enabling before events are sent:

```ruby
# Enable the Network domain
@client.send_message('Network.enable')

# Now Network events will be received
@client.on('Network.requestWillBeSent') { |e| ... }
@client.on('Network.responseReceived') { |e| ... }
```

### Common Domains That Need Enabling

- `Network.enable` - Network events
- `Page.enable` - Page lifecycle events
- `Runtime.enable` - Runtime events (console, exceptions)
- `DOM.enable` - DOM events

## Common CDP Patterns

### JavaScript Evaluation

```ruby
# Evaluate expression
result = @client.send_message('Runtime.evaluate',
  expression: 'document.title',
  returnByValue: true
)
# result['result']['value'] => "Page Title"

# Call function on object
result = @client.send_message('Runtime.callFunctionOn',
  functionDeclaration: '(a, b) => a + b',
  arguments: [{ value: 1 }, { value: 2 }],
  executionContextId: context_id,
  returnByValue: true
)
# result['result']['value'] => 3
```

### DOM Queries

```ruby
# Get document node
doc = @client.send_message('DOM.getDocument')
root_id = doc['root']['nodeId']

# Query selector
result = @client.send_message('DOM.querySelector',
  nodeId: root_id,
  selector: 'button'
)
button_node_id = result['nodeId']
```

### Input Simulation

```ruby
# Mouse click
@client.send_message('Input.dispatchMouseEvent',
  type: 'mousePressed',
  x: 100,
  y: 200,
  button: 'left',
  clickCount: 1
)
@client.send_message('Input.dispatchMouseEvent',
  type: 'mouseReleased',
  x: 100,
  y: 200,
  button: 'left',
  clickCount: 1
)

# Key press
@client.send_message('Input.dispatchKeyEvent',
  type: 'keyDown',
  key: 'Enter',
  code: 'Enter'
)
@client.send_message('Input.dispatchKeyEvent',
  type: 'keyUp',
  key: 'Enter',
  code: 'Enter'
)
```

### Screenshots

```ruby
result = @client.send_message('Page.captureScreenshot',
  format: 'png',
  clip: {
    x: 0,
    y: 0,
    width: 800,
    height: 600,
    scale: 1
  }
)
image_data = Base64.decode64(result['data'])
```

## CDP Session Management

### Session Hierarchy

```
Browser
  └── Connection (WebSocket to browser DevTools)
        ├── Browser-level CDPSession
        └── Target-level CDPSessions (one per page/worker)
```

### Creating Target Sessions

```ruby
# New page creates its own session
target = browser.wait_for_target { |t| t.url.include?('example.com') }
session = target.create_cdp_session

# Use session for that specific page
session.send_message('Page.enable')
```

## CDP Events Reference

### Page Events

| Event | When Fired |
|-------|------------|
| `Page.loadEventFired` | Window load event |
| `Page.domContentEventFired` | DOMContentLoaded event |
| `Page.frameNavigated` | Frame navigation complete |
| `Page.frameAttached` | New frame attached |
| `Page.frameDetached` | Frame removed |

### Network Events

| Event | When Fired |
|-------|------------|
| `Network.requestWillBeSent` | Request about to be sent |
| `Network.responseReceived` | Response headers received |
| `Network.loadingFinished` | Response body loaded |
| `Network.loadingFailed` | Request failed |

### Runtime Events

| Event | When Fired |
|-------|------------|
| `Runtime.consoleAPICalled` | console.log/warn/error |
| `Runtime.exceptionThrown` | Uncaught exception |
| `Runtime.executionContextCreated` | New JS context |
| `Runtime.executionContextDestroyed` | Context destroyed |

## Firefox CDP Support [DEPRECATED]

> **Planned for removal**: Firefox support will be removed from this library. Firefox automation will move to [puppeteer-bidi](https://github.com/YusukeIwaki/puppeteer-bidi) which uses the WebDriver BiDi protocol.

While Firefox support is still present, note that Firefox's CDP implementation differs from Chrome:

- Some CDP commands may not be implemented
- Event timing may differ
- Response format may vary slightly

When writing new code, focus on Chrome/CDP only. Do not add new Firefox-specific handling.

## Resources

- [Chrome DevTools Protocol Documentation](https://chromedevtools.github.io/devtools-protocol/)
- [CDP Protocol Viewer](https://chromedevtools.github.io/devtools-protocol/tot/)
- [Puppeteer CDP Usage](https://github.com/puppeteer/puppeteer/tree/main/packages/puppeteer-core/src/cdp)
