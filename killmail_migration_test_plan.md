# Killmail Module Migration Test Plan

## Strategy

The migration of the killmail modules to a new structure requires thorough testing to ensure functionality is preserved. This document outlines the test strategy for this migration.

## Current Status

- **Working Tests**:

  - ✅ DataAccess tests now pass with updated expectations
  - Core module tests (Data, Context, Validator)

- **Tests Needing Fixes**:

  - 🔄 NotificationDeterminer (mock issues)
  - 🔄 ApiProcessor (mock issues)
  - 🔄 Persistence (mock issues)
  - 🔄 Cache (mock issues)

- **Issues Identified**:
  - Multiple mock-related issues with test files
  - DataAccess tests were expecting functions that were intentionally removed (direct struct access now preferred)

## Action Items

1. **Comprehensive Module Coverage**

   - [x] Create mapping of all old modules to new ones
   - [x] Document test status for each module
   - [x] Identify testing gaps

2. **Critical Path Tests**

   - [x] Create tests for NotificationDeterminer
   - [x] Create tests for ApiProcessor
   - [x] Create tests for Persistence
   - [ ] Fix mock issues in remaining tests

3. **Equivalence Tests**

   - [x] Create equivalence test for NotificationDeterminer
   - [ ] Ensure mock expectations are correctly set

4. **Error Case Testing**

   - [ ] Test error handling in each module
   - [ ] Ensure error propagation works correctly

5. **Specific Module Tests**

   - [x] Ensure DataAccess properly extracts all required data
   - [ ] Test KillmailQueries functionality
   - [ ] Test CharacterQueries functionality
   - [ ] Test SolarSystemQueries functionality

6. **Load/Performance Testing**

   - [ ] Verify performance with large dataset
   - [ ] Compare performance metrics between old and new implementations

7. **Test Helper Migration**
   - [ ] Create or update test helpers for the new module structure
   - [ ] Ensure all test utilities work with new modules

## Progress Tracking

| Category                      | Status | Notes                                      |
| ----------------------------- | ------ | ------------------------------------------ |
| Module Coverage Documentation | ✅     | Completed in `killmail_module_coverage.md` |
| Core Module Tests             | ✅     | Data, Context, Validator tests passing     |
| Processing Module Tests       | 🔄     | Tests created but have mock issues         |
| Utilities Module Tests        | 🔄     | DataAccess tests passing, others pending   |
| Queries Module Tests          | ❌     | Not started                                |
| Metrics Module Tests          | ❌     | Low priority                               |
| Integration Tests             | ❌     | Not started                                |

## Approach

1. Fix the most critical mock issues first (NotificationDeterminer, ApiProcessor)
2. Complete tests for remaining medium-priority modules
3. Create integration tests for key workflows
4. Address low-priority module tests as time permits
