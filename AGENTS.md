# Repository Guidelines

## Start Here (Project-Specific Guidance)

- Read `CLAUDE.md` and `CLAUDE/` first; they define the CDP architecture, porting workflow, testing strategy, and concurrency plan.
- This repository is a CDP-based Ruby port of Puppeteer, **focused on Chrome/Chromium only**.
- CI covers Ruby 3.2, 3.3, 3.4 with latest Chrome.

### Technical Details

- **Ruby version**: Minimum is 3.2+
- **Concurrency**: Uses `socketry/async` (version 2.35.1+) for Fiber-based concurrency. See `CLAUDE/concurrency.md` for details.

## Project Structure & Module Organization

- `lib/puppeteer/`: core implementation (entry points: `puppeteer.rb`, `browser.rb`, `page.rb`, `frame.rb`, `element_handle.rb`, `connection.rb`, `cdp_session.rb`).
- `spec/integration/`: browser-driven specs; fixtures in `spec/assets/`.
- `spec/puppeteer/`: unit tests that do not require a browser.
- `docs/api_coverage.md`: API implementation status.

## Build, Test, and Development Commands

- Run all tests: `bundle exec rspec`
- Run a single file: `bundle exec rspec spec/integration/page_spec.rb`
- Debug (non-headless): `DEBUG=1 bundle exec rspec spec/integration/page_spec.rb`
- Lint: `bundle exec rubocop` (auto-fix: `bundle exec rubocop -a`)

### Useful Environment Variables

- `PUPPETEER_EXECUTABLE_PATH_RSPEC`: custom Chrome path
- `PUPPETEER_CHANNEL_RSPEC`: Chrome channel (for example `chrome-dev`)
- `PUPPETEER_NO_SANDBOX_RSPEC`: add `--no-sandbox` flag

## Coding Style & Naming Conventions

- Follow `.rubocop.yml`; prefer explicit keyword arguments for public APIs.
- Public APIs mirror Puppeteer naming but use Ruby `snake_case`.
- Custom errors inherit from `Puppeteer::Error`.
- Use `Puppeteer::AsyncUtils` for async operations; see `CLAUDE/concurrency.md` for patterns.

## Testing Guidelines

- Integration tests are `spec/integration/` with `type: :puppeteer` helpers.
- Use `sinatra: true` for tests that need a local server.
- Use `match_golden` for screenshot comparisons where applicable.

## Agent Notes (Porting/Review)

### Source Code Porting

- When porting from upstream, use `packages/puppeteer-core/src/cdp/` as the primary source.
- Mirror upstream behavior, error messages, and option handling as closely as possible.
- Enable required CDP domains before relying on their events (see `CLAUDE/cdp_protocol.md`).

### Test Porting Guidelines

When porting tests from upstream `test/src/*.spec.ts` to `spec/integration/*_spec.rb`:

**Structure & Order**
- Keep `it` blocks in the **exact same order** as upstream
- Use the **same test names** (translated to Ruby style, e.g., `'should type into a textarea'`)
- Do NOT add extra `context`/`describe` wrappers unless upstream has them
- Do NOT add Ruby-specific tests in the middle; add them at the end if needed

**Asset Files**
- `spec/assets/` files must be **identical** to upstream `test/assets/`
- Fetch assets directly: `wget https://raw.githubusercontent.com/puppeteer/puppeteer/main/test/assets/xxx`
- Do NOT hand-edit asset files; if upstream changes, re-fetch

**Code Translation**
- `page.evaluate(() => expr)` → `page.evaluate('() => expr')` (string form)
- `page.$('selector')` → `page.query_selector('selector')`
- `page.$$('selector')` → `page.query_selector_all('selector')`
- `page.$eval()` → `page.eval_on_selector()`
- `await expect(...)` assertions → RSpec `expect(...).to eq(...)`
- `toThrow`/`rejects.toThrow` → `raise_error` matcher
- Platform checks: `os.platform() !== 'darwin'` → `skip(...) unless Puppeteer.env.darwin?`

**JavaScript Object Comparisons**
- When comparing JS objects, use `eval_on_selector` or `evaluate` returning a hash
- Compare with Ruby hash: `expect(result).to eq({ 'key' => 'value' })`
- Note: JS object keys become string keys in Ruby hashes

**Upstream Test Location**
- Tests: `https://github.com/puppeteer/puppeteer/tree/main/test/src`
- Assets: `https://github.com/puppeteer/puppeteer/tree/main/test/assets`

See `CLAUDE/porting_puppeteer.md` for detailed examples.
- Update `docs/api_coverage.md` when new APIs are added.
- `CHANGELOG.md` is being retired; do not update it for new changes.
- Porting plan (CDP + async):
  - Aim for Node.js Puppeteer fidelity, but use `socketry/async` (like puppeteer-bidi) instead of JS async/await.
  - Use puppeteer-bidi as the Ruby porting reference: follow its approach and patterns.
  - For `Puppeteer::Page`, mirror upstream `api/Page.ts` and `cdp/Page.ts`, similar to how puppeteer-bidi uses `api/Page.ts` + `bidi/Page.ts`.
  - Follow puppeteer-bidi's `Page` patterns: wrap `:request` handlers to enqueue interception actions (WeakMap to keep `on/off` mapping), serialize interception with `Async::Semaphore`, and keep `Page` mostly as a thin delegator to `Frame`.
  - Mirror upstream timeout/deferred behavior with `Async::Promise` + `AsyncUtils.async_timeout` (timeout 0 = infinite) and keep error messages aligned (e.g., file chooser/network idle).
  - Screenshot parity: apply default option behavior and clip rounding (`normalize/round`), and convert clip coordinates when `captureBeyondViewport` is false (visualViewport offsets).
  - Serialize screenshot operations (bidi uses `browserContext.waitForScreenshotOperations`); keep `ScreenshotTaskQueue`/guards to avoid overlapping captures.
  - `evaluate_on_new_document`: build IIFE expressions and serialize args the same way as puppeteer-bidi's `build_evaluation_expression`/`serialize_arg_for_preload`.
  - `wait_for_network_idle`: track inflight requests and reset idle timers on changes (mirrors Page.ts inflight counter logic).
  - `wait_for_file_chooser`: resolve all pending waiters and keep timeout error messaging aligned (`Waiting for \`FileChooser\` failed: <ms> exceeded`).
  - RxJS Observable flows are replaced with manual EventEmitter listeners + `Async::Promise` (no `fromEmitterEvent`/`merge`/`timeout`), so compose waits explicitly (e.g., `wait_for_navigation`, `set_content`).
  - Use `AsyncUtils` (Barrier-based Promise.all/race + `async_timeout`) instead of RxJS `combineLatest`/`firstValueFrom`/`timeout`.
  - `WaitTask`/`TaskManager` mirror Puppeteer's polling waits; no AbortSignal, use Async tasks + cancellation.
  - `ReactorRunner` runs a dedicated Async reactor thread and proxies sync calls into it (wrap/unwrap).
  - Use `Core::EventEmitter` + symbols instead of RxJS event streams; clean up listeners explicitly.
  - Disposable patterns: `Core::Disposable::DisposableStack`/`DisposableMixin` stand in for JS DisposableStack/AsyncDisposableStack.

## Security & Configuration Tips

- Do not commit credentials or secrets.
- Be cautious with network-fetched/generated files; review diffs carefully.

## Release & CI

- Release/tagging workflow follows the current project practice (no new rules).
