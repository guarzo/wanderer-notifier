# Phase 5 Implementation Plan: Gradual Transition to New Architecture

This document outlines the detailed task list for completing Phase 5 of the killmail refactoring plan. Phase 5 focuses on gradually transitioning caller code to use the new modules directly rather than relying on the legacy interface.

## Overview

Now that we have:

1. Created specialized modules with clear responsibilities
2. Implemented backward compatibility in the legacy interface
3. Updated the Pipeline to use the new modules
4. Created comprehensive tests and documentation

We can begin the gradual transition of caller code to use the new modules directly. This approach ensures:

- We don't break existing functionality
- We make changes incrementally
- We have time to verify each change works correctly

## Detailed Task List

### 1. Codebase Analysis

- [ ] **1.1 Find all references to the Killmail module**

  - Use static analysis tools to find all places where `WandererNotifier.Killmail` is imported or referenced
  - Create a list of files and functions that need to be updated

- [ ] **1.2 Categorize references by purpose**

  - Group the references by functionality (data extraction, validation, database queries)
  - Prioritize groups based on frequency, complexity, and risk

- [ ] **1.3 Create a dependency graph**
  - Identify dependencies between modules to determine the best order for updates
  - Calculate a risk score for each module based on its dependencies and complexity

### 2. Update High-Level Components

- [ ] **2.1 Update the zkill websocket processing**

  - Update the `Api.ZKill.Websocket` module to use `KillmailData` and `Pipeline` directly
  - Add proper error handling using the structured approach

- [ ] **2.2 Update notification determination**

  - Refactor `Notifications.Determiner.Kill` to use `Extractor` for accessing killmail data
  - Update tests to ensure notifications still work correctly

- [ ] **2.3 Update web controllers**
  - Identify controllers that work with killmail data
  - Update these to use `KillmailQueries` and `KillmailData` directly

### 3. Update Data Processing Components

- [ ] **3.1 Update Enrichment Callers**

  - Replace direct calls to `Killmail.get_system_id` etc. with `Extractor` equivalents
  - Update tests to verify that enrichment still works correctly

- [ ] **3.2 Update Persistence Code**

  - Identify code that persists killmails to the database
  - Update to use `KillmailData` and appropriate validators

- [ ] **3.3 Update Notification Rendering**
  - Update notification templates/rendering to use `Extractor` for data access
  - Ensure notifications still render correctly with the new structure

### 4. Update Utility & Support Code

- [ ] **4.1 Update Logging**

  - Update logging code to use `Extractor.debug_data` for consistent debugging
  - Review all log messages to ensure they're updated with the new terminology

- [ ] **4.2 Update CLI Commands**

  - Update any CLI commands or scripts that process killmails
  - Add validation using the new `Validator` module

- [ ] **4.3 Update Background Tasks**
  - Update any scheduled tasks or background processes that handle killmails
  - Verify they work correctly with the new architecture

### 5. Testing & Verification

- [ ] **5.1 Create integration tests**

  - Create integration tests that verify the entire killmail pipeline works
  - Ensure these tests use the new modules directly

- [ ] **5.2 Verify backward compatibility**

  - Run existing tests to ensure backward compatibility still works
  - Identify any regressions and fix them

- [ ] **5.3 Performance testing**
  - Conduct performance testing to ensure the new architecture doesn't impact performance
  - Document any performance improvements

### 6. Documentation & Knowledge Transfer

- [ ] **6.1 Update documentation**

  - Ensure all existing documentation is updated to reference the new modules
  - Add additional examples for common use cases

- [ ] **6.2 Create migration guide**

  - Develop a guide for other team members to follow when updating their code
  - Include common patterns and examples

- [ ] **6.3 Code review guidelines**
  - Create guidelines for code reviews to ensure new code uses the new architecture
  - Include a checklist of common issues to look for

### 7. Final Cleanup

- [ ] **7.1 Add deprecation warnings**

  - Add explicit deprecation warnings to the legacy Killmail module functions
  - Include guidance on which new module to use instead

- [ ] **7.2 Remove temporary code**

  - Remove any temporary code or workarounds added during the refactoring
  - Update tests to reflect these changes

- [ ] **7.3 Final audit**
  - Conduct a final audit of the codebase to ensure all references are updated
  - Document any remaining technical debt for future phases

## Timeline and Milestones

### Milestone 1: Analysis Complete

- Complete tasks 1.1-1.3
- Produce a detailed transition plan with prioritized modules

### Milestone 2: Core Components Updated

- Complete tasks 2.1-2.3
- Most critical components now use the new architecture directly

### Milestone 3: All Components Updated

- Complete tasks 3.1-4.3
- All components now use the new architecture directly

### Milestone 4: Verification Complete

- Complete tasks 5.1-5.3
- All tests pass and performance is verified

### Milestone 5: Documentation Complete

- Complete tasks 6.1-7.3
- Project is fully transitioned to the new architecture

## Risk Mitigation

1. **Incremental Changes**: Update one module at a time, with thorough testing after each change
2. **Feature Flags**: Consider using feature flags to easily rollback changes if issues arise
3. **Dual Implementation**: For critical paths, consider running both old and new implementations in parallel and comparing results
4. **Monitoring**: Add additional logging and monitoring during the transition to quickly identify issues
5. **Rollback Plan**: Have a clear rollback plan for each change to quickly restore functionality if needed
