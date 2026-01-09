# Detailed Implementation Documentation

This directory contains in-depth documentation for AI agents and developers working on puppeteer-ruby.

## Documentation Index

| Document | Description |
|----------|-------------|
| [architecture.md](./architecture.md) | CDP-based architecture and component relationships |
| [testing.md](./testing.md) | Testing strategies, patterns, and debugging |
| [cdp_protocol.md](./cdp_protocol.md) | Chrome DevTools Protocol usage |
| [concurrency.md](./concurrency.md) | Concurrency model and migration plans |
| [porting_puppeteer.md](./porting_puppeteer.md) | Guide for porting from TypeScript Puppeteer |
| [rbs_type_checking.md](./rbs_type_checking.md) | RBS type annotations and Steep type checking |

## Quick Navigation

### For New Feature Implementation

1. Read [porting_puppeteer.md](./porting_puppeteer.md) for workflow
2. Understand the feature's CDP calls in [cdp_protocol.md](./cdp_protocol.md)
3. Review [architecture.md](./architecture.md) for component relationships

### For Bug Fixes

1. Review [architecture.md](./architecture.md) to understand component relationships
2. Write tests following patterns in [testing.md](./testing.md)
3. Consider concurrency issues per [concurrency.md](./concurrency.md)

### For Code Review

1. Ensure alignment with [architecture.md](./architecture.md)
2. Verify test coverage per [testing.md](./testing.md)
3. Review concurrency patterns per [concurrency.md](./concurrency.md)

## Related Resources

- [CLAUDE.md](../CLAUDE.md) - High-level project summary
- [docs/api_coverage.md](../docs/api_coverage.md) - API implementation status
- [Puppeteer TypeScript source](https://github.com/puppeteer/puppeteer) - Reference implementation
- [Chrome DevTools Protocol docs](https://chromedevtools.github.io/devtools-protocol/) - CDP reference
