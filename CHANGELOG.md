### master [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.31.1...master)]

* xxx

### 0.31.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.31.0...0.31.1)]

Bugfix:

* Fix `Page#pdf` to work on Windows.

### 0.31.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.30.0...0.31.0)]

New features:

* Now puppeteer-ruby is compatible with Windows

Bugfix:

* Fix `Page#add_script_tag` and `Page#add_style_tag` to work

### 0.30.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.29.0...0.30.0)]

New features:

* S, SS, Seval, SSeval is renamed to query_selector, query_selector_all, eval_on_selector, eval_on_selector_all

### 0.29.0 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.28.1...0.29.0)]

New features:

* Add `AriaQueryHandler`. Now we can use "aria/...." for selectors.

### 0.28.1 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.27...0.28.1)]

New features:

* Add `Page#emulate_idle_state`
* Change versioning rule.

### 0.0.27 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.26...0.0.27)]

New features:

* Now puppeteer-ruby is Ruby 3.0 compatible!

### 0.0.26 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.25...0.0.26)]

Bugfix:

* Fix `Page#screenshot` working correctly with `quality` parameter.

### 0.0.25 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.23...0.0.25)]

New feature:

* **Cookie** feature: `Page#set_cookie`, `Page#cookies`

### 0.0.23 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.22...0.0.23)]

New feature:

* **GeoLocation** feature
* grant/clear permission

Bugfix/Improvement:

* Refactoring for events ([#31](https://github.com/YusukeIwaki/puppeteer-ruby/pull/31))
* Improve SEND/RECV handling in CDPSession ([#34](https://github.com/YusukeIwaki/puppeteer-ruby/pull/34))

### 0.0.22 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.21...0.0.22)]

Bugfix

* Make `Puppeteer#default_args` to work
* Respect Firefox launch options
* Respect `default_viewport: nil`

### 0.0.21 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.20...0.0.21)]

Bugfix/Improvement:

* Update DeviceDescriptors (list of emulatable devices)
* Fix bug on inputing "(" ([#25](https://github.com/YusukeIwaki/puppeteer-ruby/pull/25))

### 0.0.20 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.19...0.0.20)]

New feature

* Dialog-handling feature

### 0.0.19 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.18...0.0.19)]

New feature

* **Firefox support**

Bugfix/Improvement

* Allow `Page#keyboard` with block ([#18](https://github.com/YusukeIwaki/puppeteer-ruby/pull/18))

### 0.0.18 [[diff](https://github.com/YusukeIwaki/puppeteer-ruby/compare/0.0.17...0.0.18)]

New feature

* **Firefox support**

Bugfix/Improvement

* Allow `Page#keyboard` with block ([#18](https://github.com/YusukeIwaki/puppeteer-ruby/pull/18))
