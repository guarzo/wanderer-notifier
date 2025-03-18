# Wanderer Notifier Refactoring Plan

## Overview
This document outlines a comprehensive refactoring plan for the Wanderer Notifier application to improve code organization, reduce duplication, remove unused code, and enhance overall readability.

## Task List

### Phase 1: Core Structure Reorganization ✅
- [x] Create new directory structure
- [x] Move files to appropriate locations
- [x] Update module names to match new structure
- [x] Fix remaining import issues
- [x] Update application startup code

### Phase 2: HTTP Client Unification ✅
- [x] Create unified HTTP client
- [x] Implement consistent error handling and retry logic
- [x] Migrate all API clients to use the unified client
- [x] Remove duplicate HTTP-related code

### Phase 2.5: Proxy Module Implementation ✅
- [x] Create proxy modules for compatibility
- [x] Implement Service proxy
- [x] Implement Service.KillProcessor proxy
- [x] Implement Service.TPSChartScheduler proxy
- [x] Implement Maintenance.Scheduler proxy
- [x] Fix circular dependencies
- [x] Implement License proxy for GenServer calls
- [x] Implement Features proxy

### Phase 3: Notification System Refactoring
- [ ] Consolidate notification templates
- [ ] Create reusable notification components
- [ ] Streamline notifier interface
- [ ] Separate notification content from delivery mechanism
- [ ] Improve notification formatting

### Phase 4: Data Enrichment Refactoring
- [ ] Create dedicated enrichment services
- [ ] Implement improved caching strategies
- [ ] Consolidate duplicate enrichment code
- [ ] Optimize API calls

### Phase 5: Clean-up and Optimization
- [ ] Remove unused functions
- [ ] Simplify complex logic
- [ ] Improve error handling
- [ ] Add better documentation
- [ ] Update tests

## Implemented Directory Structure

```
lib/
  wanderer_notifier/
    application.ex
    core/
      config.ex         # Core configuration
      features.ex       # Feature flags
      license.ex        # License management
      stats.ex          # Statistics tracking
    data/
      killmail.ex       # Killmail data structure
      system.ex         # System data structure
      character.ex      # Character data structure
    api/
      http/
        client.ex       # Unified HTTP client
      esi/
        client.ex       # ESI API client
        service.ex      # ESI data service
      zkill/
        client.ex       # zKill API client
        service.ex      # zKill data service
        websocket.ex    # zKill WebSocket client
      map/
        client.ex       # Map API client
    notifiers/
      behaviour.ex      # Notification behavior
      factory.ex        # Notification factory
      discord.ex        # Discord notification
      slack.ex          # Slack notification
    services/           # Implementation of all service modules
      kill_processor.ex # Kill processing service
      service.ex        # Main service implementation
      tps_chart_scheduler.ex # TPS chart scheduling service
      maintenance/
        scheduler.ex    # Maintenance scheduler implementation
    service/            # Proxy modules for backward compatibility
      kill_processor.ex # Proxy to Services.KillProcessor
      tps_chart_scheduler.ex # Proxy to Services.TPSChartScheduler
    maintenance/        # Proxy modules for backward compatibility
      scheduler.ex      # Proxy to Services.Maintenance.Scheduler
    license.ex          # Proxy to Core.License
    features.ex         # Proxy to Core.Features
    service.ex          # Proxy module to Services.Service
``` 

## Proxy Pattern Implementation

To facilitate code migration without breaking existing functionality, we've implemented a proxy pattern where original module names forward calls to their new implementations. This allows for:

1. Gradual migration of code to the new structure
2. Minimal disruption to existing functionality
3. Clear separation between old and new implementations

Each proxy module follows a consistent pattern:
- Keeps the original module name in the original location
- Delegates all method calls to the new implementation
- Maintains the same function signatures and behavior

This approach allows us to move forward with refactoring while maintaining compatibility with existing code. Once all code is updated to use the new module structure, these proxy modules can be phased out. 