# Test Suite Restoration & Coverage Plan

## 1. Assess the Current State

- **Test suite run:** 155 tests, 128 failures (see `tests.txt` for full output)
- **Key failure patterns:**
  - Many `UndefinedFunctionError` and `ArgumentError` for missing or undefined modules/functions (e.g., `WandererNotifier.Config.Notifications`, `WandererNotifier.Data.Cache.Keys`, `WandererNotifier.Data.MapUtil`, etc.)
  - Warnings about deprecated log levels and unused variables/aliases
  - Mox-related errors: modules not mocks, unknown functions for mocks, or missing mock modules
  - Test setup errors: modules given as children to supervisors but do not exist
- **Initial assessment:**
  - The refactor likely involved renaming, moving, or removing modules and functions, and possibly changes to the mocking/test infrastructure.
  - Many tests are failing due to missing or outdated references to modules/functions that no longer exist or have changed.

## 2. Map Refactor Changes to Test Failures

- **Refactor summary (from `refactor.yaml`):**
  - Major removals: all database persistence, chart service, Ash resource modules, PostgreSQL setup, chart generation services, and related config files.
  - Configuration: modular config files removed; replaced with a single centralized configuration module.
  - API: many API controllers/helpers removed or rewritten to drop persistence/chart features.
  - Cache: new cache key management and behavior modules; refactored Cachex implementation.
  - Startup: application startup logic simplified.
  - Mocks/Testing: many modules and behaviors removed or replaced, impacting test mocks and setup.
  - Docs/CI: documentation and CI/CD updated to reflect the above.
- **Mapping to test failures:**
  - Most failures are due to tests referencing deleted or renamed modules/functions (e.g., Ash, chart-service, modular config, persistence-related API).
  - Mox errors are likely because mocks reference deleted modules or behaviors.
  - Supervisor errors and test setup failures are due to missing modules or changed application structure.
  - Warnings about unused variables/aliases and deprecated log levels should be cleaned up.

## 3. Update the Test Suite

- **Next actionable steps:**

  1. Catalog all test files and their dependencies.
  2. Identify tests that are now obsolete (e.g., those for persistence, chart-service, or removed APIs/config).
  3. Update or remove tests:
     - Remove tests for deleted features.
     - Update tests for refactored modules (e.g., config, cache, API).
     - Refactor test setup and mocks to match the new structure.
  4. Incrementally restore passing state by focusing first on tests for features that remain in the codebase.

- Update imports/aliases in test files to match new module paths/names.
- Adjust test setup (fixtures, mocks, test data) to align with new data structures or APIs.
- Refactor test logic to match new function signatures and expected behaviors.
- Remove or rewrite obsolete tests that no longer make sense after the refactor.

## 4. Restore Passing State Incrementally

- Fix tests in small batches (by module or feature) and re-run the suite after each batch.
- Commit frequently to track progress and isolate issues.

## 5. Ensure Proper Test Coverage

- Identify key functionality (core business logic, critical paths, edge cases).
- Check for missing or outdated tests for these areas.
- Write new tests where coverage is lacking, especially for new or changed code.

## 6. Validate and Improve

- Run a coverage tool (e.g., ExCoveralls for Elixir) to measure test coverage.
- Review uncovered lines and add tests as needed.
- Refactor tests for clarity and maintainability (use descriptive names, remove duplication).

## 7. Document and Maintain

- Document any new testing patterns or helpers introduced during the refactor.
- Add comments to complex tests for future maintainers.
- Set up CI to catch regressions early.

---

_This plan will be updated as progress is made and new information is discovered._
