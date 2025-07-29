# Codebase Reorganization Implementation Plan - Sprint Schedule

## Overview

This document provides a detailed 8-sprint (16-week) implementation plan to reorganize the Wanderer Notifier codebase. Each sprint is 2 weeks long and builds incrementally on previous work to minimize risk and ensure continuous delivery.

## Sprint Planning Principles

- **Incremental delivery**: Each sprint delivers working, testable changes
- **Risk mitigation**: Low-risk changes first, complex refactoring last  
- **Continuous testing**: Full test suite must pass after each sprint
- **Quality gates**: No compilation, test, credo, or dialyzer issues after each task
- **Regular commits**: Commit working changes frequently (multiple times per day)
- **Documentation driven**: Update docs as structure changes

---

## Sprint 1: Foundation Setup (Weeks 1-2)
**Theme**: Establish new structure and standards without breaking changes

### Sprint Goal
Create the new directory structure and establish naming conventions without moving existing files.

### Tasks

#### Week 1: Structure Creation
- [ ] **T1.1** Create new directory structure (empty directories)
  - Create `lib/wanderer_notifier/core/` hierarchy
  - Create updated `domains/` subdirectories  
  - Create reorganized `infrastructure/` structure
  - Create new `shared/` organization
- [ ] **T1.2** Document new naming conventions
  - Update CLAUDE.md with new structure
  - Create naming standards reference
  - Document file organization principles
- [ ] **T1.3** Create utility scripts for migration
  - Script to validate import paths
  - Script to detect circular dependencies
  - Script to verify test coverage after moves

#### Week 2: Standards & Cleanup
- [ ] **T1.4** Remove empty directories
  - Delete `domains/tracking/clients/` (empty)
  - Delete `domains/notifications/determiner/` (empty)
  - Clean up any other empty directories
- [ ] **T1.5** Standardize existing file names (rename only)
  - Rename ambiguous files like `test.ex` → `notification_test_helpers.ex`
  - Standardize service files to `*_service.ex` pattern
  - Update imports for renamed files
- [ ] **T1.6** Create migration tracking
  - Create checklist of all files to move
  - Document current vs. target locations
  - Set up automated tests for each module

### Acceptance Criteria
- [ ] New directory structure exists alongside current structure
- [ ] All existing tests pass
- [ ] No broken imports from file renames
- [ ] Migration scripts are functional
- [ ] Documentation reflects naming standards

### ⚠️ CRITICAL QUALITY CHECKS
**After EVERY task completion:**
- [ ] **`make compile`** - No compilation errors
- [ ] **`make test`** - All tests pass (100%)
- [ ] **`mix credo --strict`** - No credo issues
- [ ] **`mix dialyzer`** - No dialyzer warnings
- [ ] **Commit changes** with descriptive message

**Daily commits required** - Never end a day without committing working code

---

## Sprint 2: Shared Utilities Consolidation (Weeks 3-4)
**Theme**: Consolidate and organize shared utilities without domain logic changes

### Sprint Goal
Move and consolidate shared utilities, configuration, and cross-cutting concerns into the new `shared/` structure.

### Tasks

#### Week 1: Configuration & Types
- [ ] **T2.1** Consolidate configuration management
  - Move `shared/config_provider.ex` → `shared/config/config_provider.ex`
  - Move `shared/config/` files into new structure
  - Update all imports for configuration files
- [ ] **T2.2** Organize shared types and constants
  - Move `shared/types/constants.ex` to new location
  - Consolidate any scattered constant definitions
  - Create common type definitions file
- [ ] **T2.3** Update telemetry organization
  - Move telemetry files from `application/telemetry/` → `shared/telemetry/`
  - Consolidate telemetry concerns
  - Update telemetry imports across codebase

#### Week 2: Utilities & Error Handling
- [ ] **T2.4** Consolidate utility modules
  - Move all `shared/utils/` files to new structure
  - Ensure no duplication of utility functions
  - Update imports for utility modules
- [ ] **T2.5** Standardize error handling
  - Ensure single error handling approach
  - Move error handling to `shared/utils/error_handler.ex`
  - Update all modules to use consistent error handling
- [ ] **T2.6** Validation & testing
  - Run full test suite
  - Update test imports
  - Verify no circular dependencies

### Acceptance Criteria
- [ ] All shared utilities are in `shared/` directory
- [ ] No duplication of utility functions
- [ ] All imports updated and working
- [ ] Full test suite passes
- [ ] Configuration management is consolidated

### ⚠️ CRITICAL QUALITY CHECKS
**After EVERY task completion:**
- [ ] **`make compile`** - No compilation errors
- [ ] **`make test`** - All tests pass (100%)
- [ ] **`mix credo --strict`** - No credo issues
- [ ] **`mix dialyzer`** - No dialyzer warnings
- [ ] **Commit changes** with descriptive message

**Daily commits required** - Test each utility module individually after move

---

## Sprint 3: Infrastructure Reorganization (Weeks 5-6)
**Theme**: Reorganize infrastructure layer and consolidate HTTP/cache concerns

### Sprint Goal
Restructure infrastructure directory and consolidate scattered HTTP and caching logic.

### Tasks

#### Week 1: HTTP Client Consolidation
- [ ] **T3.1** Consolidate HTTP utilities
  - Move duplicate rate limiting logic to single location
  - Consolidate retry logic in `infrastructure/http/middleware/`
  - Move all HTTP utilities to `infrastructure/http/utils/`
  - Remove duplicated HTTP helper functions
- [ ] **T3.2** Organize middleware properly
  - Ensure middleware in `infrastructure/http/middleware/`
  - Standardize middleware naming (`*_middleware.ex`)
  - Update HTTP client to use consolidated middleware
- [ ] **T3.3** Reorganize external adapters
  - Move ESI adapter files to `infrastructure/adapters/esi/`
  - Move Janice client to `infrastructure/adapters/janice/`
  - Organize adapter entities properly

#### Week 2: Cache & Messaging
- [ ] **T3.4** Consolidate cache implementations
  - Move cache logic to `infrastructure/cache/`
  - Ensure single cache interface
  - Remove any duplicated cache concerns from domains
- [ ] **T3.5** Organize messaging infrastructure
  - Consolidate messaging files in `infrastructure/messaging/`
  - Ensure proper separation from domain logic
  - Update imports across codebase
- [ ] **T3.6** Testing & validation
  - Update infrastructure tests
  - Verify adapter functionality
  - Run integration tests

### Acceptance Criteria
- [ ] HTTP client logic is consolidated
- [ ] No duplicate rate limiting or retry logic
- [ ] External adapters are properly organized
- [ ] Cache implementation is unified
- [ ] All infrastructure tests pass

### ⚠️ CRITICAL QUALITY CHECKS
**After EVERY task completion:**
- [ ] **`make compile`** - No compilation errors
- [ ] **`make test`** - All tests pass (100%)
- [ ] **`mix credo --strict`** - No credo issues
- [ ] **`mix dialyzer`** - No dialyzer warnings
- [ ] **Commit changes** with descriptive message

**Daily commits required** - Run integration tests, verify external service connectivity

---

## Sprint 4: Core Application Layer (Weeks 7-8)
**Theme**: Reorganize application layer and supervisor structure

### Sprint Goal
Move application-level concerns to `core/` directory and establish proper supervisor hierarchy.

### Tasks

#### Week 1: Application Structure
- [ ] **T4.1** Create core application structure
  - Move `application.ex` organization to `core/`
  - Create `core/supervisors/` with proper hierarchy
  - Move application services to `core/services/`
- [ ] **T4.2** Reorganize supervisors
  - Move supervisor files to `core/supervisors/`
  - Rename for clarity (`main_supervisor.ex`, etc.)
  - Update supervisor hierarchy and dependencies
- [ ] **T4.3** Consolidate application services
  - Move cross-domain services to `core/services/`
  - Remove duplicate service concerns
  - Update service imports and dependencies

#### Week 2: Dependencies & Stats
- [ ] **T4.4** Organize dependency management
  - Move dependency management to `core/services/`
  - Consolidate service startup logic
  - Update application startup sequence
- [ ] **T4.5** Consolidate stats and monitoring
  - Move stats collection to appropriate location
  - Ensure proper separation of concerns
  - Update telemetry integration
- [ ] **T4.6** Scheduler organization
  - Verify scheduler organization is correct
  - Update scheduler imports
  - Test background job functionality

### Acceptance Criteria
- [ ] Application layer is organized in `core/`
- [ ] Supervisor hierarchy is clear and functional
- [ ] Application startup works correctly
- [ ] Background schedulers function properly
- [ ] Service dependencies are managed correctly

### ⚠️ CRITICAL QUALITY CHECKS
**After EVERY task completion:**
- [ ] **`make compile`** - No compilation errors
- [ ] **`make test`** - All tests pass (100%)
- [ ] **`mix credo --strict`** - No credo issues
- [ ] **`mix dialyzer`** - No dialyzer warnings
- [ ] **Commit changes** with descriptive message

**Daily commits required** - Test application startup, supervisor restarts after each change

---

## Sprint 5: Domains - Killmail Processing (Weeks 9-10)
**Theme**: Reorganize killmail domain with proper internal structure

### Sprint Goal
Reorganize the killmail domain to follow the new domain structure patterns.

### Tasks

#### Week 1: Killmail Entities & Services
- [ ] **T5.1** Organize killmail entities
  - Create `domains/killmail/entities/` structure
  - Move and organize killmail entity files
  - Ensure proper entity definitions
- [ ] **T5.2** Reorganize killmail services
  - Move killmail processing services to `domains/killmail/services/`
  - Organize WebSocket and HTTP clients properly
  - Move fallback handler to services
- [ ] **T5.3** Create pipeline organization
  - Move pipeline files to `domains/killmail/pipeline/`
  - Organize pipeline workers and enrichment
  - Update pipeline imports and dependencies

#### Week 2: Killmail Utils & Integration
- [ ] **T5.4** Organize killmail utilities
  - Move utilities to `domains/killmail/utils/`
  - Consolidate item processing and stream utilities
  - Remove any utility duplication
- [ ] **T5.5** Update killmail integration
  - Update imports across codebase
  - Verify killmail processing functionality
  - Test WebSocket and fallback mechanisms
- [ ] **T5.6** Context migration
  - Move relevant context logic into domain
  - Remove old context files if empty
  - Update context imports

### Acceptance Criteria
- [ ] Killmail domain follows new structure
- [ ] Killmail processing functionality works
- [ ] WebSocket and fallback mechanisms function
- [ ] No broken imports or circular dependencies
- [ ] Killmail tests pass

### ⚠️ CRITICAL QUALITY CHECKS
**After EVERY task completion:**
- [ ] **`make compile`** - No compilation errors
- [ ] **`make test`** - All tests pass (100%)
- [ ] **`mix credo --strict`** - No credo issues
- [ ] **`mix dialyzer`** - No dialyzer warnings
- [ ] **Commit changes** with descriptive message

**Daily commits required** - Test killmail processing end-to-end after each move

---

## Sprint 6: Domains - Tracking & Map Integration (Weeks 11-12)
**Theme**: Consolidate tracking domain and integrate map functionality

### Sprint Goal
Move map functionality into tracking domain and organize all tracking concerns properly.

### Tasks

#### Week 1: Map to Tracking Migration
- [ ] **T6.1** Move map directory to tracking
  - Move `map/` → `domains/tracking/clients/`
  - Update map-related imports
  - Preserve SSE and tracking functionality
- [ ] **T6.2** Organize tracking services
  - Move tracking clients to proper location
  - Organize character and system tracking services
  - Consolidate tracking logic
- [ ] **T6.3** Update tracking entities
  - Ensure tracking entities are properly organized
  - Move character and system entities to `entities/`
  - Update entity imports and usage

#### Week 2: Tracking Integration
- [ ] **T6.4** Consolidate tracking handlers
  - Organize event handlers in `handlers/`
  - Ensure shared event logic is properly used
  - Update handler imports and dependencies
- [ ] **T6.5** Update tracking clients
  - Consolidate SSE and map clients
  - Ensure proper client organization
  - Test real-time tracking functionality
- [ ] **T6.6** Integration testing
  - Test character tracking
  - Test system tracking
  - Verify SSE connectivity and parsing

### Acceptance Criteria
- [ ] Map functionality is integrated into tracking domain
- [ ] Character and system tracking works
- [ ] SSE connectivity functions properly
- [ ] Real-time events are processed correctly
- [ ] No broken imports or functionality

### ⚠️ CRITICAL QUALITY CHECKS
**After EVERY task completion:**
- [ ] **`make compile`** - No compilation errors
- [ ] **`make test`** - All tests pass (100%)
- [ ] **`mix credo --strict`** - No credo issues
- [ ] **`mix dialyzer`** - No dialyzer warnings
- [ ] **Commit changes** with descriptive message

**Daily commits required** - Test SSE connectivity and real-time event processing after each change

---

## Sprint 7: Domains - Notifications (Weeks 13-14)
**Theme**: Reorganize notifications domain and Discord integration

### Sprint Goal
Reorganize the notifications domain with proper internal structure and clean Discord integration.

### Tasks

#### Week 1: Notification Structure
- [ ] **T7.1** Organize notification entities
  - Create proper entity organization
  - Move notification entities to `entities/`
  - Update entity imports and usage
- [ ] **T7.2** Reorganize notification services
  - Move services to `domains/notifications/services/`
  - Consolidate notification logic
  - Organize deduplication and determination services
- [ ] **T7.3** Organize formatters
  - Move formatters to `domains/notifications/formatters/`
  - Consolidate formatter logic by type
  - Create shared formatter utilities

#### Week 2: Discord & Channels
- [ ] **T7.4** Reorganize Discord integration
  - Move Discord code to `domains/notifications/channels/discord/`
  - Organize Discord client and components
  - Update Discord imports and dependencies
- [ ] **T7.5** Consolidate notification logic
  - Remove duplicate notification concerns
  - Ensure proper service organization
  - Update notification processing pipeline
- [ ] **T7.6** Testing & validation
  - Test notification formatting
  - Test Discord delivery
  - Verify notification deduplication

### Acceptance Criteria
- [ ] Notifications domain is properly organized
- [ ] Discord integration works correctly
- [ ] Notification formatting functions properly
- [ ] Notification deduplication works
- [ ] No broken notification delivery

### ⚠️ CRITICAL QUALITY CHECKS
**After EVERY task completion:**
- [ ] **`make compile`** - No compilation errors
- [ ] **`make test`** - All tests pass (100%)
- [ ] **`mix credo --strict`** - No credo issues
- [ ] **`mix dialyzer`** - No dialyzer warnings
- [ ] **Commit changes** with descriptive message

**Daily commits required** - Test notification delivery end-to-end after each change

---

## Sprint 8: Testing & Documentation (Weeks 15-16)
**Theme**: Align test structure and complete documentation

### Sprint Goal
Reorganize test structure to mirror new codebase organization and update all documentation.

### Tasks

#### Week 1: Test Structure Alignment
- [ ] **T8.1** Reorganize test directory structure
  - Mirror main codebase structure in tests
  - Move test files to match source organization
  - Update test imports and dependencies
- [ ] **T8.2** Standardize test naming
  - Ensure tests follow naming conventions
  - Update test file names for consistency
  - Organize test utilities and helpers
- [ ] **T8.3** Update test utilities
  - Move test utilities to proper shared locations
  - Consolidate test helpers and factories
  - Remove duplicate test setup code

#### Week 2: Documentation & Cleanup
- [ ] **T8.4** Update all documentation
  - Update CLAUDE.md with final structure
  - Update README and developer guides
  - Document new organizational patterns
- [ ] **T8.5** Final cleanup and validation
  - Remove any remaining old directories
  - Clean up any leftover files
  - Run full test suite and fix any issues
- [ ] **T8.6** Performance validation
  - Run benchmarks to ensure no performance regression
  - Validate startup time and memory usage
  - Test production build process

### Acceptance Criteria
- [ ] Test structure mirrors main codebase
- [ ] All tests pass with new structure
- [ ] Documentation is complete and accurate
- [ ] No old directories or files remain
- [ ] Performance is maintained or improved
- [ ] Production build works correctly

### ⚠️ CRITICAL QUALITY CHECKS
**After EVERY task completion:**
- [ ] **`make compile`** - No compilation errors
- [ ] **`make test`** - All tests pass (100%)
- [ ] **`mix credo --strict`** - No credo issues
- [ ] **`mix dialyzer`** - No dialyzer warnings
- [ ] **Commit changes** with descriptive message

**Daily commits required** - Run complete test suite and performance benchmarks

---

## Success Metrics

### Per Sprint
- [ ] All tests pass
- [ ] No broken imports
- [ ] Functionality works as expected
- [ ] Documentation is updated
- [ ] Code coverage maintained or improved

### Final Success Criteria
- [ ] **Maintainability**: Clear domain boundaries and consistent structure
- [ ] **Testability**: Test structure mirrors source structure
- [ ] **Performance**: No regression in startup time or memory usage
- [ ] **Functionality**: All features work exactly as before
- [ ] **Documentation**: Complete and accurate documentation
- [ ] **Developer Experience**: Improved code navigation and understanding

## Quality Management

### MANDATORY Quality Gates (Every Task)
1. **`make compile`** - Must compile without errors
2. **`make test`** - All tests must pass (100%)
3. **`mix credo --strict`** - No credo issues allowed
4. **`mix dialyzer`** - No dialyzer warnings allowed
5. **Git commit** - Commit working changes with descriptive messages

### Commit Strategy
- **Minimum**: 2-3 commits per day
- **Ideal**: Commit after each successful task completion
- **Message format**: `[Sprint X.Y] Description of change`
- **Never**: Leave broken code uncommitted overnight

### Critical Path Dependencies
- Sprint 1-2: Foundation must be solid before proceeding
- Sprint 3: Infrastructure changes affect all subsequent sprints
- Sprint 5-7: Domain reorganization must be done in dependency order
- Sprint 8: Final validation ensures nothing is broken

### Daily Development Routine
1. **Morning**: Run full quality gate (`compile`, `test`, `credo`, `dialyzer`)
2. **After each task**: Run quality gates before committing
3. **End of day**: Ensure all changes are committed and working
4. **Sprint review**: Demo working functionality, verify all quality gates pass

### Quality Enforcement
- **No exceptions**: Quality gates must pass before any commit
- **Fix immediately**: Any quality issues must be resolved before continuing
- **Test coverage**: Maintain or improve existing test coverage
- **Documentation**: Update inline docs when moving/changing modules

## Post-Implementation

### Immediate Follow-up (Week 17)
- [ ] Monitor production deployment
- [ ] Address any performance issues
- [ ] Update team onboarding documentation
- [ ] Conduct retrospective on reorganization process

### Long-term Benefits Tracking (Months 1-3)
- [ ] Measure developer onboarding time improvement
- [ ] Track code navigation efficiency
- [ ] Monitor technical debt reduction
- [ ] Assess maintenance effort reduction

This implementation plan provides a structured, low-risk approach to completing the codebase reorganization while maintaining continuous delivery and minimizing disruption to ongoing development work.