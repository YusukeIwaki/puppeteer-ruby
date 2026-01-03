# Architecture Overview

This document describes the architecture of puppeteer-ruby.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        User-Facing API                          │
│  Puppeteer.launch / Puppeteer.connect                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Browser                                 │
│  - Manages browser process lifecycle                            │
│  - Creates browser contexts (incognito sessions)                │
│  - Tracks all targets (pages, workers, etc.)                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      BrowserContext                             │
│  - Represents an incognito session or default context           │
│  - Manages permissions, cookies, geolocation                    │
│  - Creates new pages within the context                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                          Page                                   │
│  - Main user interaction point                                  │
│  - Navigation, content, screenshots, PDF                        │
│  - Delegates to Frame, Keyboard, Mouse, etc.                    │
└─────────────────────────────────────────────────────────────────┘
                              │
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
      ┌──────────┐     ┌──────────┐     ┌──────────────┐
      │  Frame   │     │ Keyboard │     │    Mouse     │
      │          │     │          │     │              │
      └──────────┘     └──────────┘     └──────────────┘
            │
            ▼
      ┌──────────────────────────────────────────┐
      │              IsolatedWorld               │
      │  - Execution context for JavaScript      │
      │  - Query selectors, evaluate JS          │
      └──────────────────────────────────────────┘
            │
            ▼
      ┌──────────────────────────────────────────┐
      │         ElementHandle / JSHandle         │
      │  - References to DOM elements / JS objs  │
      │  - Click, type, evaluate, etc.           │
      └──────────────────────────────────────────┘
```

## Core Components

### Connection Layer

```
┌─────────────────────────────────────────────────────────────────┐
│                        Connection                               │
│  lib/puppeteer/connection.rb                                    │
│                                                                 │
│  - WebSocket connection to browser's DevTools endpoint          │
│  - Manages message routing to correct CDPSession                │
│  - Handles connection lifecycle                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       CDPSession                                │
│  lib/puppeteer/cdp_session.rb                                   │
│                                                                 │
│  - Represents a CDP session to a specific target                │
│  - send_message: Send CDP commands                              │
│  - on/once: Subscribe to CDP events                             │
└─────────────────────────────────────────────────────────────────┘
```

### Target Management

```
┌─────────────────────────────────────────────────────────────────┐
│                    ChromeTargetManager                          │
│  lib/puppeteer/chrome_target_manager.rb                         │
│                                                                 │
│  - Discovers and tracks all targets in browser                  │
│  - Creates Target objects for new pages, workers, etc.          │
│  - Handles target attachment and auto-attach                    │
└─────────────────────────────────────────────────────────────────┘

```

### Page Architecture

```
Page
 ├── FrameManager          # Manages all frames in the page
 │    ├── Frame (main)     # Main frame
 │    └── Frame (child)... # Iframes
 │         └── IsolatedWorld
 │              ├── Main world (page's JS context)
 │              └── Puppeteer utility world (isolated context)
 │
 ├── NetworkManager        # Request interception, network events
 │    └── NetworkEventManager
 │
 ├── EmulationManager      # Viewport, device emulation
 │
 ├── Keyboard              # Keyboard input
 ├── Mouse                 # Mouse input
 └── TouchScreen           # Touch input
```

## Key Patterns

### Event Handling

Components use `EventCallbackable` mixin for event handling:

```ruby
class Page
  include Puppeteer::EventCallbackable

  def initialize
    @frame_manager.on('load') do
      emit_event('load')
    end
  end
end

# Usage
page.on('load') { puts 'Page loaded!' }
```

### CDP Command/Response Pattern

```ruby
# Send CDP command and wait for response
result = @client.send_message('Page.navigate', url: url)

# Subscribe to CDP events
@client.on('Network.requestWillBeSent') do |event|
  handle_request(event)
end
```

### Resource Cleanup

Use `begin/ensure` blocks for cleanup:

```ruby
def screenshot(options = {})
  original_viewport = @viewport
  begin
    self.viewport = options[:viewport] if options[:viewport]
    # Take screenshot...
  ensure
    self.viewport = original_viewport if options[:viewport]
  end
end
```

## File Organization

```
lib/puppeteer/
├── puppeteer.rb              # Module with launch/connect methods
├── puppeteer/
│   ├── browser.rb            # Browser class
│   ├── browser_context.rb    # BrowserContext class
│   ├── page.rb               # Page class (largest file)
│   ├── frame.rb              # Frame class
│   ├── frame_manager.rb      # FrameManager class
│   ├── element_handle.rb     # ElementHandle class
│   ├── js_handle.rb          # JSHandle class
│   ├── connection.rb         # WebSocket connection
│   ├── cdp_session.rb        # CDP session
│   ├── keyboard.rb           # Keyboard input
│   ├── mouse.rb              # Mouse input
│   ├── network_manager.rb    # Network interception
│   ├── launcher/
│   │   ├── chrome.rb         # Chrome-specific launch
│   └── ...
```

## Data Flow Examples

### Page Navigation

```
User: page.goto('https://example.com')
  │
  ▼
Page#goto
  │
  ├── FrameManager#navigate_frame
  │     │
  │     ├── CDPSession.send('Page.navigate', url: ...)
  │     │
  │     └── LifecycleWatcher.new(wait_until: 'load')
  │           │
  │           └── Waits for 'Page.loadEventFired' event
  │
  └── Returns HTTPResponse
```

### Element Click

```
User: element.click
  │
  ▼
ElementHandle#click
  │
  ├── scroll_into_view_if_needed
  │     └── CDPSession.send('DOM.scrollIntoViewIfNeeded')
  │
  ├── clickable_point
  │     └── CDPSession.send('DOM.getContentQuads')
  │
  └── Page#mouse.click(x, y)
        │
        ├── Mouse#move(x, y)
        │     └── CDPSession.send('Input.dispatchMouseEvent', type: 'mouseMoved')
        │
        ├── Mouse#down
        │     └── CDPSession.send('Input.dispatchMouseEvent', type: 'mousePressed')
        │
        └── Mouse#up
              └── CDPSession.send('Input.dispatchMouseEvent', type: 'mouseReleased')
```

### JavaScript Evaluation

```
User: page.evaluate('() => document.title')
  │
  ▼
Page#evaluate
  │
  └── Frame#evaluate
        │
        └── IsolatedWorld#evaluate
              │
              ├── CDPSession.send('Runtime.callFunctionOn', ...)
              │
              └── RemoteObject.new(result).value
```
