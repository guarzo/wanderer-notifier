# Service Module Refactoring Tasks

## Overview

Reorganize files from the `services` module to more appropriate locations within the existing module structure.

## Tasks

### 1. Move API Clients to Api namespace

- [x] **ZKillboard API**

  - ~Move `lib/wanderer_notifier/services/zkillboard_api.ex` to `lib/wanderer_notifier/api/zkillboard/client.ex`~
  - ~Rename module to `WandererNotifier.Api.ZKill.Client`~
  - ~Update all references throughout the codebase~
  - **COMPLETED**: Modified approach - discovered an existing `WandererNotifier.Api.ZKill.Client` module, so made `ZKillboardApi` a wrapper that delegates to the existing implementation. Added deprecation warnings to encourage migration to the proper module.

- [x] **Character Kills Service**
  - Move `lib/wanderer_notifier/services/character_kills_service.ex` to `lib/wanderer_notifier/api/character/kills_service.ex`
  - Rename module to `WandererNotifier.Api.Character.KillsService`
  - Update all references
  - **COMPLETED**: Moved implementation to new file and created a wrapper module in the original location for backward compatibility with deprecation warnings.

### 2. Create Processing namespace for data processing

- [x] **Kill Processor**

  - Move `lib/wanderer_notifier/services/kill_processor.ex` to `lib/wanderer_notifier/processing/killmail/processor.ex`
  - Rename module to `WandererNotifier.Processing.Killmail.Processor`
  - Update all references
  - **COMPLETED**: Split the large module into multiple focused modules:
    - Processor: Main coordination and entry points
    - Stats: Statistics tracking
    - Cache: Cache management
    - Enrichment: Data enrichment
    - Notification: Notification handling
    - Created a wrapper in the original location for backward compatibility.

- [x] **Killmail Comparison**
  - Move `lib/wanderer_notifier/services/killmail_comparison.ex` to `lib/wanderer_notifier/processing/killmail/comparison.ex`
  - Rename module to `WandererNotifier.Processing.Killmail.Comparison`
  - Update all references
  - **COMPLETED**: Moved implementation to the new module and created a backward compatibility wrapper in the original location. Updated alias to use `WandererNotifier.Api.ZKill.Client` directly.

### 3. Move persistence logic to Resources

- [x] **Killmail Persistence**

  - Move `lib/wanderer_notifier/services/killmail_persistence.ex` to `lib/wanderer_notifier/resources/killmail_service.ex`
  - Rename module to `WandererNotifier.Resources.KillmailService`
  - Update all references
  - **COMPLETED**: Created a new service interface in the Resources namespace that delegates to the existing `KillmailPersistence` module. Added deprecation notices to the original module.

- [x] **Kill Tracking History**
  - Move `lib/wanderer_notifier/services/kill_tracking_history.ex` to `lib/wanderer_notifier/resources/kill_history_service.ex`
  - Rename module to `WandererNotifier.Resources.KillHistoryService`
  - Update all references
  - **COMPLETED**: Created a new service interface in the Resources namespace that provides the same functionality. Added deprecation notices to the original module to encourage users to switch to the new implementation.

### 4. Move notification logic to Notifiers

- [x] **Notification Determiner**
  - Move `lib/wanderer_notifier/services/notification_determiner.ex` to `lib/wanderer_notifier/notifiers/determiner.ex`
  - Rename module to `WandererNotifier.Notifiers.Determiner`
  - Update all references
  - **COMPLETED**: Created a new module in the Notifiers namespace with the same functionality, and updated the original module to include deprecation notices and delegate to the new implementation.

### 5. Move maintenance to Core

- [x] **Maintenance Service**

  - Move `lib/wanderer_notifier/services/maintenance.ex` to `lib/wanderer_notifier/core/maintenance/service.ex`
  - Rename module to `WandererNotifier.Core.Maintenance.Service`
  - Update all references
  - **COMPLETED**: Created new module in the Core namespace and created a wrapper module in the original location for backward compatibility with deprecation warnings.

- [x] **Maintenance Scheduler**
  - Move `lib/wanderer_notifier/services/maintenance/scheduler.ex` to `lib/wanderer_notifier/core/maintenance/scheduler.ex`
  - Rename module to `WandererNotifier.Core.Maintenance.Scheduler`
  - Update all references
  - **COMPLETED**: Created new module in the Core namespace and created a wrapper module in the original location for backward compatibility with deprecation warnings.

### 6. Review Main Service

- [ ] **Service Module**
  - Review `lib/wanderer_notifier/services/service.ex`
  - Consider renaming to `ApplicationService` or similar for clarity
  - Consider moving to core
  - Update any necessary references

## Implementation Strategy

1. Start with simpler, less interconnected services first
2. For each service:
   - Create new directory structure if needed
   - Move file with proper module rename
   - Update all references/imports in the codebase
   - Test functionality
3. Keep thorough notes on changes made
4. Test application thoroughly after completing refactoring
