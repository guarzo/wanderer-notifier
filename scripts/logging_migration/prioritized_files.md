# Prioritized Files for Logging Migration

This document outlines the files that require updates to conform to the standardized logging patterns, prioritized by impact and complexity.

## Phase 1: High Priority Files (Core Components)

These files have the most significant impact on the system and should be updated first.

### Critical Core Components

1. **wanderer_notifier/core/application/service.ex**

   - Issues: 88 pattern opportunities (KV logging for boolean flags)
   - Notes: Central service component, high visibility

2. **wanderer_notifier/release.ex**

   - Issues: 38 direct Logger calls, missing alias
   - Notes: Used during deployment and runtime management

3. **wanderer_notifier/application.ex**
   - Issues: Direct Logger calls, startup logging
   - Notes: Application entry point, ideal for startup phase tracking

### High-Usage Services

1. **wanderer_notifier/api/zkill/websocket.ex**

   - Issues: WebSocket logging can be improved with category-specific methods
   - Notes: Central component for kill data

2. **wanderer_notifier/processing/killmail/processor.ex**

   - Issues: Multiple pattern opportunities, high-volume processing
   - Notes: Good candidate for batch logging

3. **wanderer_notifier/data/cache/cachex_impl.ex**
   - Issues: 12 direct Logger calls, 27 pattern opportunities
   - Notes: Cache operations are high volume, good batch logging candidate

## Phase 2: Medium Priority Files (API and Processing)

These files handle key business logic and would benefit from standardized logging.

### API Clients

1. **wanderer_notifier/api/map/characters_client.ex**

   - Issues: 74 pattern opportunities
   - Notes: API client with potential for structured logging

2. **wanderer_notifier/api/map/systems_client.ex**

   - Issues: Multiple logging opportunities
   - Notes: API client with similar patterns to characters client

3. **wanderer_notifier/api/esi/client.ex**

   - Issues: API logging patterns
   - Notes: External API client

4. **wanderer_notifier/api/zkill/client.ex**
   - Issues: API logging patterns
   - Notes: External API client

### Processing Logic

1. **wanderer_notifier/processing/killmail/comparison.ex**

   - Issues: 49 pattern opportunities
   - Notes: Complex processing logic

2. **wanderer_notifier/processing/killmail/enrichment.ex**

   - Issues: Multiple logging opportunities
   - Notes: Data enrichment logic

3. **wanderer_notifier/processing/killmail/notification.ex**
   - Issues: Notification-related logging
   - Notes: User-facing outputs

## Phase 3: Lower Priority Files (Supporting Components)

These files are still important but can be addressed after the higher priority items.

### Chart Service

1. **wanderer_notifier/chart_service/chart_service_manager.ex**

   - Issues: 74 direct Logger calls, 71 pattern opportunities
   - Notes: UI component, less critical path

2. **wanderer_notifier/chart_service/chart_config.ex**
   - Issues: Logging patterns
   - Notes: Configuration-related logging

### Schedulers

1. **wanderer_notifier/schedulers/base_scheduler.ex**

   - Issues: Logging patterns
   - Notes: Good template for other schedulers

2. **wanderer_notifier/schedulers/character_update_scheduler.ex**

   - Issues: Scheduler-specific logging
   - Notes: Periodic task

3. **wanderer_notifier/schedulers/system_update_scheduler.ex**
   - Issues: Scheduler-specific logging
   - Notes: Periodic task

### Resources and Data

1. **wanderer_notifier/resources/tracked_character.ex**

   - Issues: 70 pattern opportunities
   - Notes: Data storage layer

2. **wanderer_notifier/data/repository.ex**
   - Issues: Database-related logging
   - Notes: Data access layer

## Implementation Approach

For each file:

1. **Fix module declaration**

   - Add proper alias: `alias WandererNotifier.Logger.Logger, as: AppLogger`
   - Remove direct `require Logger` if not needed

2. **Convert direct Logger calls**

   - Replace with equivalent AppLogger functions

3. **Apply category-specific methods**

   - Update to use the appropriate category-specific helper function

4. **Implement key-value logging**

   - Identify boolean flags and configuration values
   - Convert to appropriate key-value function

5. **Identify batch logging opportunities**
   - Focus on high-volume, repetitive log messages
   - Consider initializing batch logger in startup phase
