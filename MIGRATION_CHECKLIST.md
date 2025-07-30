# Migration Tracking Checklist

This checklist tracks the progress of the 8-sprint codebase reorganization from the current structure to a clean domain-driven design.

## Sprint 1: Foundation Setup (Weeks 1-2) ✅ COMPLETED

### Week 1 Tasks ✅
- [x] **T1.1** Create new directory structure (empty directories)
  - [x] Created `core/` directory hierarchy  
  - [x] Created updated `domains/` subdirectories
  - [x] Created reorganized `infrastructure/` structure
  - [x] Created new `shared/` organization
- [x] **T1.2** Document new naming conventions
  - [x] Updated CLAUDE.md with new structure
  - [x] Created naming standards reference
  - [x] Documented file organization principles
- [x] **T1.3** Create utility scripts for migration
  - [x] Created `validate_imports.exs` for import validation
  - [x] Created `detect_cycles.exs` for dependency checking
  - [x] Created `test_coverage_check.exs` for coverage tracking

### Week 2 Tasks ✅  
- [x] **T1.4** Remove empty directories
  - [x] Deleted `domains/tracking/clients/` (empty)
  - [x] Deleted `domains/notifications/determiner/` (empty)
- [x] **T1.5** Standardize existing file names
  - [x] Renamed `test.ex` → `test_notifier.ex`
  - [x] Renamed `service.ex` → `license_service.ex`
  - [x] Updated all imports and references
- [x] **T1.6** Create migration tracking checklist
  - [x] Created comprehensive checklist with all sprint tasks

**Sprint 1 Status**: ✅ COMPLETED - Foundation established successfully

---

## Sprint 2: Shared Utilities Consolidation (Weeks 3-4) 🔄 PENDING

### Week 1 Tasks (Week 3)
- [ ] **T2.1** Consolidate configuration management
  - [ ] Move `shared/config_provider.ex` → `shared/config/config_provider.ex`
  - [ ] Move `shared/config/` files into new structure
  - [ ] Update all imports for configuration files
- [ ] **T2.2** Organize shared types and constants
  - [ ] Move `shared/types/constants.ex` to new location
  - [ ] Consolidate any scattered constant definitions
  - [ ] Create common type definitions file
- [ ] **T2.3** Update telemetry organization
  - [ ] Move telemetry files from `application/telemetry/` → `shared/telemetry/`
  - [ ] Consolidate telemetry concerns
  - [ ] Update telemetry imports across codebase

### Week 2 Tasks (Week 4)
- [ ] **T2.4** Consolidate utility modules
  - [ ] Move all `shared/utils/` files to new structure
  - [ ] Ensure no duplication of utility functions
  - [ ] Update imports for utility modules
- [ ] **T2.5** Standardize error handling
  - [ ] Ensure single error handling approach
  - [ ] Move error handling to `shared/utils/error_handler.ex`
  - [ ] Update all modules to use consistent error handling
- [ ] **T2.6** Validation & testing
  - [ ] Run full test suite
  - [ ] Update test imports
  - [ ] Verify no circular dependencies

**Sprint 2 Status**: 🔄 PENDING

---

## Sprint 3: Infrastructure Reorganization (Weeks 5-6) 🔄 PENDING

### Week 1 Tasks (Week 5)
- [ ] **T3.1** Consolidate HTTP utilities
  - [ ] Move duplicate rate limiting logic to single location
  - [ ] Consolidate retry logic in `infrastructure/http/middleware/`
  - [ ] Move all HTTP utilities to `infrastructure/http/utils/`
  - [ ] Remove duplicated HTTP helper functions
- [ ] **T3.2** Organize middleware properly
  - [ ] Ensure middleware in `infrastructure/http/middleware/`
  - [ ] Standardize middleware naming (`*_middleware.ex`)
  - [ ] Update HTTP client to use consolidated middleware
- [ ] **T3.3** Reorganize external adapters
  - [ ] Move ESI adapter files to `infrastructure/adapters/esi/`
  - [ ] Move Janice client to `infrastructure/adapters/janice/`
  - [ ] Organize adapter entities properly

### Week 2 Tasks (Week 6)
- [ ] **T3.4** Consolidate cache implementations
  - [ ] Move cache logic to `infrastructure/cache/`
  - [ ] Ensure single cache interface
  - [ ] Remove any duplicated cache concerns from domains
- [ ] **T3.5** Organize messaging infrastructure
  - [ ] Consolidate messaging files in `infrastructure/messaging/`
  - [ ] Ensure proper separation from domain logic
  - [ ] Update imports across codebase
- [ ] **T3.6** Testing & validation
  - [ ] Update infrastructure tests
  - [ ] Verify adapter functionality
  - [ ] Run integration tests

**Sprint 3 Status**: 🔄 PENDING

---

## Sprint 4: Core Application Layer (Weeks 7-8) 🔄 PENDING

### Week 1 Tasks (Week 7)
- [ ] **T4.1** Create core application structure
  - [ ] Move `application.ex` organization to `core/`
  - [ ] Create `core/supervisors/` with proper hierarchy
  - [ ] Move application services to `core/services/`
- [ ] **T4.2** Reorganize supervisors
  - [ ] Move supervisor files to `core/supervisors/`
  - [ ] Rename for clarity (`main_supervisor.ex`, etc.)
  - [ ] Update supervisor hierarchy and dependencies
- [ ] **T4.3** Consolidate application services
  - [ ] Move cross-domain services to `core/services/`
  - [ ] Remove duplicate service concerns
  - [ ] Update service imports and dependencies

### Week 2 Tasks (Week 8)
- [ ] **T4.4** Organize dependency management
  - [ ] Move dependency management to `core/services/`
  - [ ] Consolidate service startup logic
  - [ ] Update application startup sequence
- [ ] **T4.5** Consolidate stats and monitoring
  - [ ] Move stats collection to appropriate location
  - [ ] Ensure proper separation of concerns
  - [ ] Update telemetry integration
- [ ] **T4.6** Scheduler organization
  - [ ] Verify scheduler organization is correct
  - [ ] Update scheduler imports
  - [ ] Test background job functionality

**Sprint 4 Status**: 🔄 PENDING

---

## Sprint 5: Domains - Killmail Processing (Weeks 9-10) 🔄 PENDING

### Week 1 Tasks (Week 9)
- [ ] **T5.1** Organize killmail entities
  - [ ] Create `domains/killmail/entities/` structure
  - [ ] Move and organize killmail entity files
  - [ ] Ensure proper entity definitions
- [ ] **T5.2** Reorganize killmail services
  - [ ] Move killmail processing services to `domains/killmail/services/`
  - [ ] Organize WebSocket and HTTP clients properly
  - [ ] Move fallback handler to services
- [ ] **T5.3** Create pipeline organization
  - [ ] Move pipeline files to `domains/killmail/pipeline/`
  - [ ] Organize pipeline workers and enrichment
  - [ ] Update pipeline imports and dependencies

### Week 2 Tasks (Week 10)
- [ ] **T5.4** Organize killmail utilities
  - [ ] Move utilities to `domains/killmail/utils/`
  - [ ] Consolidate item processing and stream utilities
  - [ ] Remove any utility duplication
- [ ] **T5.5** Update killmail integration
  - [ ] Update imports across codebase
  - [ ] Verify killmail processing functionality
  - [ ] Test WebSocket and fallback mechanisms
- [ ] **T5.6** Context migration
  - [ ] Move relevant context logic into domain
  - [ ] Remove old context files if empty
  - [ ] Update context imports

**Sprint 5 Status**: 🔄 PENDING

---

## Sprint 6: Domains - Tracking & Map Integration (Weeks 11-12) 🔄 PENDING

### Week 1 Tasks (Week 11)
- [ ] **T6.1** Move map directory to tracking
  - [ ] Move `map/` → `domains/tracking/clients/`
  - [ ] Update map-related imports
  - [ ] Preserve SSE and tracking functionality
- [ ] **T6.2** Organize tracking services
  - [ ] Move tracking clients to proper location
  - [ ] Organize character and system tracking services
  - [ ] Consolidate tracking logic
- [ ] **T6.3** Update tracking entities
  - [ ] Ensure tracking entities are properly organized
  - [ ] Move character and system entities to `entities/`
  - [ ] Update entity imports and usage

### Week 2 Tasks (Week 12)
- [ ] **T6.4** Consolidate tracking handlers
  - [ ] Organize event handlers in `handlers/`
  - [ ] Ensure shared event logic is properly used
  - [ ] Update handler imports and dependencies
- [ ] **T6.5** Update tracking clients
  - [ ] Consolidate SSE and map clients
  - [ ] Ensure proper client organization
  - [ ] Test real-time tracking functionality
- [ ] **T6.6** Integration testing
  - [ ] Test character tracking
  - [ ] Test system tracking
  - [ ] Verify SSE connectivity and parsing

**Sprint 6 Status**: 🔄 PENDING

---

## Sprint 7: Domains - Notifications (Weeks 13-14) 🔄 PENDING

### Week 1 Tasks (Week 13)
- [ ] **T7.1** Organize notification entities
  - [ ] Create proper entity organization
  - [ ] Move notification entities to `entities/`
  - [ ] Update entity imports and usage
- [ ] **T7.2** Reorganize notification services
  - [ ] Move services to `domains/notifications/services/`
  - [ ] Consolidate notification logic
  - [ ] Organize deduplication and determination services
- [ ] **T7.3** Organize formatters
  - [ ] Move formatters to `domains/notifications/formatters/`
  - [ ] Consolidate formatter logic by type
  - [ ] Create shared formatter utilities

### Week 2 Tasks (Week 14)
- [ ] **T7.4** Reorganize Discord integration
  - [ ] Move Discord code to `domains/notifications/channels/discord/`
  - [ ] Organize Discord client and components
  - [ ] Update Discord imports and dependencies
- [ ] **T7.5** Consolidate notification logic
  - [ ] Remove duplicate notification concerns
  - [ ] Ensure proper service organization
  - [ ] Update notification processing pipeline
- [ ] **T7.6** Testing & validation
  - [ ] Test notification formatting
  - [ ] Test Discord delivery
  - [ ] Verify notification deduplication

**Sprint 7 Status**: 🔄 PENDING

---

## Sprint 8: Testing & Documentation (Weeks 15-16) 🔄 PENDING

### Week 1 Tasks (Week 15)
- [ ] **T8.1** Reorganize test directory structure
  - [ ] Mirror main codebase structure in tests
  - [ ] Move test files to match source organization
  - [ ] Update test imports and dependencies
- [ ] **T8.2** Standardize test naming
  - [ ] Ensure tests follow naming conventions
  - [ ] Update test file names for consistency
  - [ ] Organize test utilities and helpers
- [ ] **T8.3** Update test utilities
  - [ ] Move test utilities to proper shared locations
  - [ ] Consolidate test helpers and factories
  - [ ] Remove duplicate test setup code

### Week 2 Tasks (Week 16)
- [ ] **T8.4** Update all documentation
  - [ ] Update CLAUDE.md with final structure
  - [ ] Update README and developer guides
  - [ ] Document new organizational patterns
- [ ] **T8.5** Final cleanup and validation
  - [ ] Remove any remaining old directories
  - [ ] Clean up any leftover files
  - [ ] Run full test suite and fix any issues
- [ ] **T8.6** Performance validation
  - [ ] Run benchmarks to ensure no performance regression
  - [ ] Validate startup time and memory usage
  - [ ] Test production build process

**Sprint 8 Status**: 🔄 PENDING

---

## Quality Gates Checklist

Every task must pass these mandatory checks:

### ✅ Compilation
- [ ] `make compile` - No compilation errors allowed
- [ ] No module import issues
- [ ] All syntax is valid

### ✅ Testing  
- [ ] `make test` - All tests must pass (100%)
- [ ] No broken test imports
- [ ] Test coverage maintained or improved

### ✅ Code Quality
- [ ] `mix credo --strict` - No credo issues allowed
- [ ] Code follows established patterns
- [ ] Consistent formatting applied

### ✅ Type Checking
- [ ] `mix dialyzer` - No dialyzer warnings allowed
- [ ] Type specifications are correct
- [ ] No type mismatches

### ✅ Commit Standards
- [ ] Regular commits (minimum 2-3 per day)
- [ ] Descriptive commit messages with format: `[Sprint X.Y] Description`
- [ ] All quality gates pass before committing
- [ ] No broken code left uncommitted overnight

---

## Progress Summary

- **✅ Sprint 1**: Foundation Setup - COMPLETED
- **🔄 Sprint 2**: Shared Utilities Consolidation - PENDING  
- **🔄 Sprint 3**: Infrastructure Reorganization - PENDING
- **🔄 Sprint 4**: Core Application Layer - PENDING
- **🔄 Sprint 5**: Domains - Killmail Processing - PENDING
- **🔄 Sprint 6**: Domains - Tracking & Map Integration - PENDING
- **🔄 Sprint 7**: Domains - Notifications - PENDING
- **🔄 Sprint 8**: Testing & Documentation - PENDING

**Overall Progress**: 1/8 sprints completed (12.5%)

---

## File Movement Tracking

### Files Successfully Moved/Renamed
- `lib/wanderer_notifier/domains/notifications/test.ex` → `test_notifier.ex` ✅
- `lib/wanderer_notifier/domains/license/service.ex` → `license_service.ex` ✅

### Directories Successfully Removed
- `lib/wanderer_notifier/domains/tracking/clients/` (was empty) ✅
- `lib/wanderer_notifier/domains/notifications/determiner/` (was empty) ✅

### New Directory Structure Created
- `lib/wanderer_notifier/core/` hierarchy ✅
- `lib/wanderer_notifier/infrastructure/` reorganization ✅
- `lib/wanderer_notifier/shared/` structure ✅
- Updated `lib/wanderer_notifier/domains/` subdirectories ✅

### Baseline Metrics Established
- **Total files**: 171 Elixir files
- **Test coverage**: 18.8% (112 files without direct test coverage)
- **Quality status**: All tests passing, minimal credo/dialyzer issues

---

## Next Steps

1. **Begin Sprint 2** - Start with shared utilities consolidation
2. **Monitor quality gates** - Ensure all checks pass after each task
3. **Regular commits** - Maintain commit discipline throughout migration
4. **Update this checklist** - Mark completed tasks as we progress

This migration will significantly improve code maintainability, developer experience, and architectural consistency while reducing technical debt.