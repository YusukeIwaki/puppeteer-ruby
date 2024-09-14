### main [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.45.6...main)]

- xxx

### 0.45.6 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.45.5...0.45.6)]

Bugfix:

- Fix puppeteer-ruby to work with Firefox >= 129. Note that CDP support for Firefox is already ended. [ref](https://fxdx.dev/deprecating-cdp-support-in-firefox-embracing-the-future-with-webdriver-bidi/)

### 0.45.5 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.45.4...0.45.5)]

Bugfix:

- Relax concurrent-ruby's dependency for Rails 7.2 compatibility. ([#333](https://github.com/YusukeIwaki/puppeteer-ruby/pull/333))

### 0.45.4 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.45.3...0.45.4)]

Bugfix

- Fixed to work with Windows Chrome browser on WSL v1. ([#327](https://github.com/YusukeIwaki/puppeteer-ruby/pull/327))

### 0.45.3 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.45.2...0.45.3)]

Bugfix

- Fix hang on the size using ServiceWorker.

### 0.45.2 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.45.1...0.45.2)]

Experimental feature

- Introduce `PUPPETEER_RUBY_NO_SANDBOX` for Docker users.

### 0.45.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.45.0...0.45.1)]

Bugfix

- Fix screenshot `full_page` option

### 0.45.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.44.3...0.45.0)]

- Port Puppeteer v18.0-v19.5 features except for 3 features below (If wanted, please create a issue of the feature request :)
  - Extra headers for Puppeteer.connect ([#9314](https://github.com/puppeteer/puppeteer/pull/9314))
  - Improvement of missing product message ([#9207](https://github.com/puppeteer/puppeteer/pull/9207))
  - Configuration file (.puppeteerrc/puppeteer.config.js) ([#9140](https://github.com/puppeteer/puppeteer/pull/9140)).

### 0.44.3 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.44.2...0.44.3)]

Bugfix

- Revive Firefox automation :tada:

### 0.44.2 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.44.1...0.44.2)]

Bugfix

- Fix warning on `Page#wait_for_navigation`

### 0.44.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.44.0...0.44.1)]

Bugfix

- Ensure closing websocket [#269](https://github.com/YusukeIwaki/puppeteer-ruby/pull/269)

### 0.44.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.43.1...0.44.0)]

- Port Puppeteer v17.0-v17.1 features.
  - `wait_for_selector` no longer accept `root` parameter.

### 0.43.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.43.0...0.43.1)]

- Port Puppeteer v16.1 features, including bugfix and XPath query handler.

### 0.43.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.42.0...0.43.0)]

- Port Puppeteer v16.0 features. Increasing stability.

### 0.42.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.41.0...0.42.0)]

- Port Puppeteer v15.3-v15.5 features, including `Frame#page`

### 0.41.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.40.7...0.41.0)]

- Port Puppeteer v14.0-v15.2 features, including `ElementHandle#wait_for_xpath`

### 0.40.7 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.40.6...0.40.7)]

- Port Puppeteer v13.6-v13.7 features.

### 0.40.6 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.40.5...0.40.6)]

- Port Puppeteer v13.1-v13.5 features mainly for request interception.

### 0.40.5 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.40.4...0.40.5)]

Bugfix:

- Port Puppeteer v13.1-v13.5 bugfixes mainly for OOPIFs.

### 0.40.4 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.40.3...0.40.4)]

Bugfix:

- Fix warning on handling console message.

### 0.40.3 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.40.2...0.40.3)]

Bugfix:

- Prevent `Ctrl+C` from stopping Chrome [#196](https://github.com/YusukeIwaki/puppeteer-ruby/pull/196)

### 0.40.2 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.40.1...0.40.2)]

Bugfix:

- Fix crash on setting response listener [#195](https://github.com/YusukeIwaki/puppeteer-ruby/pull/195)

### 0.40.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.40.0...0.40.1)]

Bugfix:

- Fix error on reload [#190](https://github.com/YusukeIwaki/puppeteer-ruby/pull/190)
- Fix error message on failing to find Chrome executable.
- Fix apidoc

### 0.40.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.39.0...0.40.0)]

New features:

- Puppeteer 13.0, 13.1 functionalities
- Support Ruby 3.1

### 0.39.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.38.0...0.39.0)]

New features:

- Puppeteer 12.0 functionalities

### 0.38.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.37.4...0.38.0)]

New features:

- Puppeteer 11.0 functionalities
  - OOP iframe support
  - Customize debugging port
  - HTTPRequest#initiator
  - Customize temp directory for user data
  - Add webp to screenshot quality option allow list

### 0.37.4 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.37.3...0.37.4)]

Bugfix:

- Fix ElementHandle#screenshot to work.

### 0.37.3 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.37.2...0.37.3)]

Improvement:

- Improve the logic of detection of Chrome/Firefox executable path on Linux.

### 0.37.2 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.37.1...0.37.2)]

Bugfix:

- `timeout: 0` did set the timeout value to zero. Now it disables the timeout as expected.

### 0.37.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.37.0...0.37.1)]

Bugfix:

- Fix handle_SIGINT, handle_SIGTERM, handle_SIGHUP options to work with `false` value specified.

### 0.37.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.36.0...0.37.0)]

New features:

- Some features introduced in Puppeteer 10.4

### 0.36.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.35.1...0.36.0)]

New features:

- Drag and Drop feature introduced in Puppeteer 10.1
- `Page#emulateNetworkConditions`, `Page#emulateCPUThrottling`
- `Page#exposeFunction`
- Metrics

### 0.35.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.35.0...0.35.1)]

New features:

- Allow Rails users to use this library without `require 'puppeteer'`.

### 0.35.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.34.3...0.35.0)]

New features:

- Add `channel` parameter for Puppeteer.launch. Now `channel: chrome` or `channel: chrome-canary` (chrome-beta, chrome-dev is also available) automatically detects the executablePath of Google Chrome. Windows/macOS users can also use `channel: msedge`.

### 0.34.3 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.34.2...0.34.3)]

Bugfix:

- Fix wait_for_xxx's timeout error type.

### 0.34.2 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.34.1...0.34.2)]

New features:

- Add `Page#bring_to_front`.

### 0.34.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.34.0...0.34.1)]

Bugfix:

- Fix `Page#pdf` to work without `path` parameter.

### 0.34.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.33.0...0.34.0)]

New features:

- Sync API with block

### 0.33.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.32.4...0.33.0)]

NOTE: Requires Ruby version >= 2.6 explicitly since this version.

Bugfix:

- Fix PDF options to work correctly on decimal numbers specified.

### 0.32.4 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.32.3...0.32.4)]

Bugfix:

- Fix `#type_text` to input '<' correctly.

### 0.32.3 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.32.2...0.32.3)]

Bugfix:

- Fix puppeteer-ruby to work on Rails in development mode.

### 0.32.2 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.32.1...0.32.2)]

Bugfix:

- Fix full_page option in screenshot.

### 0.32.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.32.0...0.32.1)]

Bugfix:

- Fix WebSocket to work with `wss://...` endpoint (ex. browserless.io)

### 0.32.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.31.6...0.32.0)]

New features:

- Tracing
- JS/CSS coverages

Improvement:

- Increase stability [#92](https://github.com/YusukeIwaki/puppeteer-ruby/pull/92)

### 0.31.6 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.31.5...0.31.6)]

Improvement:

- Increase stability [#87](https://github.com/YusukeIwaki/puppeteer-ruby/pull/87)

### 0.31.5 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.31.4...0.31.5)]

Bugfix:

- Fix file uploading to work without crash.

### 0.31.4 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.31.3...0.31.4)]

Bugfix:

- Fix PDF options (format, margin, omit_background) to work.

### 0.31.3 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.31.1...0.31.3)]

Bugfix:

- Fix `wait_for_selector` to work. _It is strongly recommended to update for 0.29.0-0.31.x users._

### 0.31.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.31.0...0.31.1)]

Bugfix:

- Fix `Page#pdf` to work on Windows.

### 0.31.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.30.0...0.31.0)]

New features:

- Now puppeteer-ruby is compatible with Windows

Bugfix:

- Fix `Page#add_script_tag` and `Page#add_style_tag` to work

### 0.30.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.29.0...0.30.0)]

New features:

- S, SS, Seval, SSeval is renamed to query_selector, query_selector_all, eval_on_selector, eval_on_selector_all

### 0.29.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.28.1...0.29.0)]

New features:

- Add `AriaQueryHandler`. Now we can use "aria/...." for selectors.

### 0.28.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.27...0.28.1)]

New features:

- Add `Page#emulate_idle_state`
- Change versioning rule.

### 0.0.27 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.26...0.0.27)]

New features:

- Now puppeteer-ruby is Ruby 3.0 compatible!

### 0.0.26 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.25...0.0.26)]

Bugfix:

- Fix `Page#screenshot` working correctly with `quality` parameter.

### 0.0.25 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.23...0.0.25)]

New feature:

- **Cookie** feature: `Page#set_cookie`, `Page#cookies`

### 0.0.23 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.22...0.0.23)]

New feature:

- **GeoLocation** feature
- grant/clear permission

Bugfix/Improvement:

- Refactoring for events ([#31](https://github.com/YusukeIwaki/puppeteer-ruby/pull/31))
- Improve SEND/RECV handling in CDPSession ([#34](https://github.com/YusukeIwaki/puppeteer-ruby/pull/34))

### 0.0.22 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.21...0.0.22)]

Bugfix

- Make `Puppeteer#default_args` to work
- Respect Firefox launch options
- Respect `default_viewport: nil`

### 0.0.21 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.20...0.0.21)]

Bugfix/Improvement:

- Update DeviceDescriptors (list of emulatable devices)
- Fix bug on inputing "(" ([#25](https://github.com/YusukeIwaki/puppeteer-ruby/pull/25))

### 0.0.20 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.19...0.0.20)]

New feature

- Dialog-handling feature

### 0.0.19 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.18...0.0.19)]

New feature

- **Firefox support**

Bugfix/Improvement

- Allow `Page#keyboard` with block ([#18](https://github.com/YusukeIwaki/puppeteer-ruby/pull/18))

### 0.0.18 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.17...0.0.18)]

New feature

- **Firefox support**

Bugfix/Improvement

- Allow `Page#keyboard` with block ([#18](https://github.com/YusukeIwaki/puppeteer-ruby/pull/18))
