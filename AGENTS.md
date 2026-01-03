# Repository Guidelines

## Start Here (Project-Specific Guidance)

- Read `CLAUDE.md` and `CLAUDE/` first; they define the CDP architecture, porting workflow, testing strategy, and concurrency plan.
- This repository is a CDP-based Ruby port of Puppeteer. Firefox/BiDi work lives in `puppeteer-bidi`.
- Ruby minimum is 2.6 today; a future migration to `async` targets Ruby 3.2+ (see `CLAUDE/concurrency.md`).
- CI covers Ruby 3.2, 3.3, 3.4, 4.0 with Chrome Dev.

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
- `PUPPETEER_CHANNEL_RSPEC`: Chrome channel (CI uses `chrome-dev`)
- `PUPPETEER_NO_SANDBOX_RSPEC`: add `--no-sandbox` flag

## Coding Style & Naming Conventions

- Follow `.rubocop.yml`; prefer explicit keyword arguments for public APIs.
- Public APIs mirror Puppeteer naming but use Ruby `snake_case`.
- Custom errors inherit from `Puppeteer::Error`.
- Avoid adding new `concurrent-ruby` dependencies when possible; design with the `async` migration in mind.

## Testing Guidelines

- Integration tests are `spec/integration/` with `type: :puppeteer` helpers.
- Use `sinatra: true` for tests that need a local server.
- Use `match_golden` for screenshot comparisons where applicable.

## Agent Notes (Porting/Review)

- When porting from upstream, use `packages/puppeteer-core/src/cdp/` as the primary source.
- Mirror upstream behavior, error messages, and option handling as closely as possible.
- Enable required CDP domains before relying on their events (see `CLAUDE/cdp_protocol.md`).
- Update `docs/api_coverage.md` when new APIs are added.
- `CHANGELOG.md` is being retired; do not update it for new changes.

## Security & Configuration Tips

- Do not commit credentials or secrets.
- Be cautious with network-fetched/generated files; review diffs carefully.

## Release & CI

- Release/tagging workflow follows the current project practice (no new rules).
