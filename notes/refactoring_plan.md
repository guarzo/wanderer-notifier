# Refactoring Plan

## Phase 1: Initial Analysis ✅

- Analyze the current architecture ✅
- Identify the main components ✅
- Document component dependencies ✅
- Identify any circular dependencies ✅

## Phase 2: Namespace Organization ✅

- Create new directory structure ✅
- Define clear namespace hierarchy ✅
- Document the namespace conventions ✅

## Phase 2.5: Proxy Modules Implementation ✅

- Create proxy modules for existing modules ✅
  - License proxy for Core.License (GenServer calls) ✅
  - Features proxy for Core.Features ✅
  - KillProcessor proxy for Services.KillProcessor ✅
  - TPSChartScheduler proxy for Services.TPSChartScheduler ✅
  - Maintenance proxy for Services.Maintenance ✅
  - Service proxy for Services.Service ✅
  - SystemTracker proxy for Services.SystemTracker ✅
  - CharTracker proxy for Services.CharTracker ✅
- Update application.ex to use proxy modules ✅
- Update references in API client modules ✅

## Phase 3: Core Implementation ✅

- Implement Core.License module ✅
- Implement Core.Config ✅
- Implement Core.Features ✅
- Implement Core.Stats ✅

## Phase 4: Services Implementation ✅

- Implement Services.Service ✅
- Implement Services.KillProcessor ✅
- Implement Services.TPSChartScheduler ✅
- Implement Services.Maintenance ✅

## Phase 5: API Implementation ✅

- Implement API.ZKill ✅
- Implement API.Map ✅
- Implement API.ESI ✅

## Phase 6: Data Implementation ✅

- Implement Data.SystemTracker ✅
- Implement Data.CharTracker ✅
- Implement Data.Cache ✅

## Phase 7: Notifiers Implementation ✅

- Implement Notifiers.Discord ✅
- Implement Notifiers.Slack ✅
- Implement Notifiers.Factory ✅

## Directory Structure

```
lib/wanderer_notifier/
├── api/                # API clients for external services
│   ├── http/           # Basic HTTP client functionality 
│   ├── esi/            # EVE Swagger Interface (ESI) API
│   ├── map/            # Map API for systems and characters
│   └── zkill/          # zKillboard API
├── core/               # Core functionality
│   ├── config.ex       # Configuration management
│   ├── features.ex     # Feature flags and license features
│   ├── license.ex      # License validation and management
│   └── stats.ex        # Statistics tracking
├── data/               # Data structures and storage
│   ├── cache/          # Cache implementation
│   │   └── repository.ex # Cache repository
│   ├── character.ex    # Character data structure
│   ├── system.ex       # System data structure
│   └── killmail.ex     # Killmail data structure
├── notifiers/          # Notification services
│   ├── discord.ex      # Discord notification methods
│   ├── slack.ex        # Slack notification methods
│   ├── factory.ex      # Notifier factory for creating notifiers
│   └── behaviour.ex    # Notifier behaviour
├── services/           # Business logic and services
│   ├── char_tracker.ex     # Character tracking
│   ├── kill_processor.ex   # Kill processing logic
│   ├── maintenance.ex      # Maintenance tasks
│   ├── service.ex          # Main service
│   ├── system_tracker.ex   # System tracking
│   └── tps_chart_scheduler.ex # TPS chart scheduling
├── web/                # Web server and API
│   ├── controllers/    # API controllers
│   ├── router.ex       # Phoenix router
│   └── server.ex       # Web server
├── application.ex      # OTP Application
└── helpers/            # Helper modules
```

## Proxy Pattern

To facilitate gradual migration of code without breaking existing functionality, we've implemented a proxy pattern:

1. Original modules like `WandererNotifier.License` now act as proxies that delegate to the new implementation (e.g., `WandererNotifier.Core.License`).
2. All existing code can continue to reference the original module names.
3. New code should use the new namespaced modules directly.
4. Once all code has been migrated to use the new modules, the proxy modules can be removed.

## Refactoring Complete ✅

All planned refactoring tasks have been completed. The codebase now follows a structured namespace organization with clear separation of concerns. 