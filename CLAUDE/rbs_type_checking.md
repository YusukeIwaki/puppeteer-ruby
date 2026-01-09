# RBS Type Checking

This document covers RBS type annotations and Steep type checking for puppeteer-ruby.

## Overview

puppeteer-ruby uses [rbs-inline](https://github.com/soutaro/rbs-inline) for inline type annotations and [Steep](https://github.com/soutaro/steep) for type checking.

### File Structure

| File/Directory | Purpose |
|----------------|---------|
| `sig/_supplementary.rbs` | Manual RBS definitions for classes not using rbs-inline |
| `sig/puppeteer/*.rbs` | Auto-generated RBS files from rbs-inline |
| `Steepfile` | Steep configuration |

## Adding Type Annotations

### Inline Annotations (Preferred)

Use `# @rbs` comments in Ruby source files:

```ruby
# rbs_inline: enabled

class Foo
  # @rbs name: String
  # @rbs return: Integer
  def bar(name)
    name.length
  end
end
```

### Manual RBS Definitions

For classes that don't use rbs-inline, add definitions to `sig/_supplementary.rbs`.

## Common Issues

### Duplicate Method Definitions

**Problem**: Type check fails with `DuplicatedMethodDefinition` error.

```
sig/_supplementary.rbs:72:2: [error] Non-overloading method definition of `initialize`
in `::Puppeteer::ExecutionContext` cannot be duplicated
```

**Cause**: The same class/method is defined in both:
- `sig/_supplementary.rbs` (manual definitions)
- `sig/puppeteer/*.rbs` (rbs-inline generated)

**Solution**: Remove the duplicate definition from `_supplementary.rbs`. When rbs-inline generates definitions for a class, remove the corresponding manual definitions from `_supplementary.rbs`.

### String Slice Returns Nil

**Problem**: String slice operations with ranges may return `nil`:

```ruby
# @rbs return: [String, String]
def parse_something(text)
  part1 = text[1...5]    # Type: String? (may be nil)
  part2 = text[6..]      # Type: String? (may be nil)
  [part1, part2]         # Error: [String?, String?] not compatible with [String, String]
end
```

**Solution**: Add nil coalescing:

```ruby
def parse_something(text)
  part1 = text[1...5] || ''
  part2 = text[6..] || ''
  [part1, part2]
end
```

## Running Type Checks

```bash
# Generate RBS files from inline annotations
bundle exec rake rbs

# Run Steep type check
bundle exec steep check
```

## CI Integration

Type checking runs automatically in the `Check` workflow on every PR. The workflow:
1. Generates RBS files with `bundle exec rake rbs`
2. Validates RBS syntax with `rbs validate`
3. Runs Steep type check with `bundle exec steep check`

## Best Practices

1. **Prefer rbs-inline**: Use inline `# @rbs` annotations when possible instead of manual RBS files
2. **Remove duplicates**: When adding rbs-inline to a class, remove its entry from `_supplementary.rbs`
3. **Handle nil explicitly**: String slice and similar operations may return nil - handle this in code
4. **Run locally first**: Always run `bundle exec steep check` locally before pushing
