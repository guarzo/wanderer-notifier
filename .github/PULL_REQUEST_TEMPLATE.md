# Killmail Pipeline Refactoring PR

## Description

This PR implements changes to the killmail processing pipeline as part of the ongoing refactoring effort to improve maintainability, testability, and performance.

## Changes

- [ ] Created `DataAccess` module as a simpler alternative to `Extractor`
- [ ] Added comprehensive tests for the new `DataAccess` module
- [ ] Created migration guide in `docs/migration-guide-extractor-to-direct-access.md`
- [ ] Updated README with refactoring progress and next steps
- [ ] Added PR template for future contributions

## Migration Guide

A detailed migration guide has been created to help with transitioning from the `Extractor` module to direct `KillmailData` struct access. The guide covers:

- Mapping of common Extractor calls to direct access
- Step-by-step migration process
- Common gotchas to watch out for
- Testing recommendations

## What to Review

- `lib/wanderer_notifier/killmail_processing/data_access.ex`: The new simpler replacement for Extractor
- `test/killmail_processing/data_access_test.exs`: Tests for the DataAccess module
- `docs/migration-guide-extractor-to-direct-access.md`: Migration guide
- `README.md`: Updated with refactoring progress and next steps

## Testing

- Run the test suite: `mix test`
- Pay special attention to `test/killmail_processing/data_access_test.exs`

## Next Steps

After this PR:

1. Start migrating high-impact modules to use direct KillmailData access instead of Extractor
2. Simplify the Transformer module to only include necessary conversions
3. Add more comprehensive tests for each component
