# Technical Debt Resolution Plan

## 1. Migration from `mock` to `Mox` for Testing

### Current State

- The codebase has both `mock` and `Mox` as dependencies
- Test files are using `mock` with `with_mock` and `with_mocks` calls
- Behavior interfaces are defined for Mox but not fully utilized

### Implementation Plan

#### Phase 1: Preparation and Planning (2 days)

- [ ] Create a comprehensive inventory of all test files using `mock`
  - [ ] Run `grep -r "import Mock\|use Mock\|with_mock" test/` to find usages
- [ ] Categorize test files by module/feature to prioritize migration
- [ ] Document existing behavior interfaces for Mox and identify any gaps

#### Phase 2: Create Missing Behavior Interfaces (3 days)

- [ ] For each module being mocked with `mock`, ensure a proper behavior interface exists
  - [ ] Create template behaviors for all needed modules
  - [ ] Example:
    ```elixir
    defmodule WandererNotifier.ModuleName.Behaviour do
      @callback function_name(arg1 :: type1, arg2 :: type2) :: return_type
    end
    ```
- [ ] Update modules to implement these behaviors where needed
- [ ] Register all behavior mocks in test_helper.exs using `Mox.defmock`

#### Phase 3: Migrate Tests to Mox (5-7 days)

- [ ] Convert one test file at a time, starting with simpler cases
- [ ] For each test:
  - [ ] Replace `import Mock` with `import Mox`
  - [ ] Replace `with_mock` pattern with `expect` calls
  - [ ] Replace `assert_called` with Mox verification
  - [ ] Add `Mox.verify_on_exit!()` to setup blocks

#### Phase 4: Testing and Validation (3 days)

- [ ] Run the updated test suite to identify any issues
- [ ] Check for any edge cases or complex mocking scenarios
- [ ] Verify test coverage is maintained or improved

#### Phase 5: Finalization (1 day)

- [ ] Remove the `mock` dependency from mix.exs
- [ ] Update documentation to reflect the new testing approach
- [ ] Create testing guidelines for new test development

## 2. Refactoring config.exs

### Current State

- The config.exs file contains configuration that should follow proper patterns
- Some configuration may have hardcoded values that should be externalized

### Implementation Plan

#### Phase 1: Analysis (1-2 days)

- [ ] Identify configuration sections that need improvement
- [ ] Categorize configuration by:
  - [ ] Dynamic runtime config vs. static compile-time config
  - [ ] Environment-specific vs. common config
  - [ ] External service dependencies

#### Phase 2: Restructure Configuration (2-3 days)

- [ ] Create domain-specific configuration modules:
  - [ ] `WandererNotifier.Config.API`
  - [ ] `WandererNotifier.Config.Notifications`
  - [ ] Other domain-specific modules as needed
- [ ] Implement a centralized configuration provider with proper defaults and environment variable handling
- [ ] Move hardcoded values to environment variables with sensible defaults

#### Phase 3: Update config.exs and Runtime Config (2 days)

- [ ] Refactor config.exs to:
  - [ ] Organize related configs together
  - [ ] Remove redundancies
  - [ ] Use consistent naming patterns
  - [ ] Add clear documentation comments
- [ ] Create or update runtime.exs for dynamic configuration

#### Phase 4: Update Code References (2-3 days)

- [ ] Replace direct `Application.get_env` calls with the new configuration modules
- [ ] Replace hardcoded values with configuration

## 3. Remove Backwards Compatibility Layers

### Current State

- There are non-namespaced modules that may still be in use
- These modules need to be removed once migration is complete

### Implementation Plan

#### Phase 1: Audit Usage (2 days)

- [ ] Identify all proxy/compatibility modules
  - [ ] Run `grep -r "alias" --include="*.ex" lib/ | grep -v "WandererNotifier"`
- [ ] For each module, identify where it's being used
  - [ ] Run `grep -r "ModuleName" --include="*.ex*" lib/ test/`
- [ ] Create a dependency graph to understand migration order

#### Phase 2: Update References (3-4 days)

- [ ] For each usage identified, update to use the new namespaced module
- [ ] Update any tests that depend on the old module names
- [ ] Run tests after each update to verify functionality

#### Phase 3: Remove Proxy Modules (1 day)

- [ ] After all references are updated, remove the proxy modules
- [ ] Verify all tests still pass
- [ ] Update documentation to remove references to old modules

## 4. Replace Deprecated API Calls in discord/notifier.ex

### Implementation Plan (2-3 days)

- [ ] Audit current Discord API calls to identify deprecated methods
  - [ ] Check Discord API documentation for deprecations
  - [ ] Review `nostrum` documentation for updated methods
- [ ] Create migration plan for each deprecated call
- [ ] Update each call with the appropriate replacement
- [ ] Test notification functionality thoroughly after changes

## 5. Consolidate Duplicate Code in Notification Formatters

### Implementation Plan (2-3 days)

- [ ] Identify duplicate formatting logic across notification modules
- [ ] Extract common formatting patterns into shared utility functions
- [ ] Create a unified formatting module (e.g., `WandererNotifier.Notifications.Formatter`)
- [ ] Update all notification modules to use the shared formatters

## 6. Clean Up Unused Variables and Functions

### Implementation Plan (2 days)

- [ ] Run static analysis tools:
  - [ ] `mix credo --strict`
  - [ ] Review compiler warnings
- [ ] Address warnings for unused variables and functions
- [ ] Remove dead code

## 7. Standardize Cache Key Formats

### Implementation Plan (2-3 days)

- [ ] Audit current cache key formats
  - [ ] Run `grep -r "set\|put\|get\|delete" --include="*.ex" lib/ | grep "Repository\|Cache"`
- [ ] Create a centralized module for cache key generation:
  ```elixir
  defmodule WandererNotifier.Cache.Keys do
    def character_key(character_id), do: "character:#{character_id}"
    def system_key(system_id), do: "system:#{system_id}"
    # etc.
  end
  ```
- [ ] Update all cache operations to use the standardized format

## 8. Split Large Modules

### Implementation Plan (3-5 days)

- [ ] Identify large modules:
  - [ ] Run `find lib/ -name "*.ex" -exec wc -l {} \; | sort -nr | head -10`
- [ ] For each large module:
  - [ ] Identify logical component boundaries
  - [ ] Extract functionality into separate modules
  - [ ] Update references and imports
- [ ] Target modules specifically mentioned in action items:
  - [ ] `MapSystem`
  - [ ] `Character`

## Implementation Timeline

Total estimated time: 30-40 days

- Week 1-2: Mock to Mox Migration
- Week 3: Config.exs Refactoring
- Week 4: Backwards Compatibility Removal
- Week 5-6: Other Technical Debt Items

## Testing and Validation Strategy

- [ ] Ensure all unit tests pass after each change
- [ ] Verify critical functionality after significant changes
- [ ] Address one area of technical debt at a time
- [ ] Update documentation to reflect new patterns
