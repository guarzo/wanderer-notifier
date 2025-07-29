# Codebase Reorganization Plan

## Executive Summary

After analyzing the current codebase structure, I've identified significant opportunities for improvement in organization, naming consistency, and reducing directory sprawl. This plan outlines a comprehensive reorganization strategy to create a more maintainable and intuitive codebase structure.

## Current Issues Identified

### 1. Inconsistent Architectural Patterns
- **Mixed organization**: Domain-driven design (`domains/`) mixed with technical layers (`infrastructure/`, `shared/`)
- **Misplaced domains**: `map/` directory contains domain logic but isn't under `domains/`
- **Unclear boundaries**: Confusion between `contexts/` and `domains/` for business logic
- **Application layer confusion**: Both `application/` directory and domain services handling similar concerns

### 2. Directory and File Sprawl
- **Empty directories**: `domains/tracking/clients/` and `domains/notifications/determiner/` are empty
- **Deep nesting**: Paths like `infrastructure/adapters/entities/` and `application/services/application/` go 4-5 levels deep
- **Fragmented files**: Some directories have too many files without logical grouping

### 3. Naming Inconsistencies
- **Mixed conventions**: Some files use descriptive suffixes (`_client.ex`, `_service.ex`), others don't
- **Ambiguous names**: Files like `test.ex` in domains provide unclear context
- **Inconsistent patterns**: No clear naming standard across modules

### 4. Duplicated Concerns
- **HTTP utilities**: Rate limiting and retry logic scattered across multiple locations
- **Cache implementations**: Both domain-specific and infrastructure cache handling
- **Configuration**: Multiple configuration approaches and files

### 5. Test Structure Issues
- **Misaligned organization**: Tests don't mirror main codebase structure consistently
- **Inconsistent naming**: Test files don't always match source file patterns

## Recommended New Structure

```
lib/wanderer_notifier/
├── core/                              # Core application logic
│   ├── application.ex                 # Main application module
│   ├── supervisors/                   # Application supervisors
│   │   ├── main_supervisor.ex
│   │   ├── killmail_supervisor.ex
│   │   └── external_services_supervisor.ex
│   └── services/                      # Cross-domain application services
│       ├── notification_orchestrator.ex
│       ├── dependency_manager.ex
│       └── stats_collector.ex
├── domains/                           # Business domains (DDD approach)
│   ├── killmail/                      # Killmail processing domain
│   │   ├── entities/
│   │   │   ├── killmail.ex
│   │   │   └── enriched_killmail.ex
│   │   ├── services/
│   │   │   ├── killmail_processor.ex
│   │   │   ├── websocket_client.ex
│   │   │   ├── fallback_handler.ex
│   │   │   └── wanderer_kills_client.ex
│   │   ├── pipeline/
│   │   │   ├── pipeline.ex
│   │   │   ├── pipeline_worker.ex
│   │   │   └── enrichment_service.ex
│   │   └── utils/
│   │       ├── item_processor.ex
│   │       ├── stream_utils.ex
│   │       └── json_encoders.ex
│   ├── tracking/                      # Character and system tracking
│   │   ├── entities/
│   │   │   ├── character.ex
│   │   │   └── system.ex
│   │   ├── services/
│   │   │   ├── map_tracking_service.ex
│   │   │   ├── character_tracker.ex
│   │   │   └── system_tracker.ex
│   │   ├── clients/
│   │   │   ├── sse_client.ex
│   │   │   ├── sse_parser.ex
│   │   │   └── map_client.ex
│   │   └── handlers/
│   │       ├── character_event_handler.ex
│   │       ├── system_event_handler.ex
│   │       └── shared_event_logic.ex
│   ├── notifications/                 # Notification handling
│   │   ├── entities/
│   │   │   └── notification.ex
│   │   ├── services/
│   │   │   ├── notification_service.ex
│   │   │   ├── deduplication_service.ex
│   │   │   └── notification_determiner.ex
│   │   ├── formatters/
│   │   │   ├── killmail_formatter.ex
│   │   │   ├── system_formatter.ex
│   │   │   ├── character_formatter.ex
│   │   │   └── formatter_utils.ex
│   │   └── channels/
│   │       └── discord/
│   │           ├── discord_client.ex
│   │           ├── component_builder.ex
│   │           ├── feature_detector.ex
│   │           └── constants.ex
│   └── license/                       # License management
│       ├── entities/
│       │   └── license.ex
│       └── services/
│           ├── license_service.ex
│           └── license_validator.ex
├── infrastructure/                    # Technical infrastructure
│   ├── http/                         # HTTP client infrastructure
│   │   ├── client.ex                 # Main HTTP client
│   │   ├── middleware/
│   │   │   ├── rate_limiter.ex
│   │   │   ├── retry_middleware.ex
│   │   │   └── telemetry_middleware.ex
│   │   └── utils/
│   │       ├── headers.ex
│   │       ├── response_handler.ex
│   │       └── validation.ex
│   ├── cache/                        # Caching infrastructure
│   │   ├── cache_service.ex
│   │   ├── cache_config.ex
│   │   └── cache_keys.ex
│   ├── adapters/                     # External service adapters
│   │   ├── esi/
│   │   │   ├── esi_client.ex
│   │   │   ├── esi_service.ex
│   │   │   └── entities/
│   │   │       ├── character.ex
│   │   │       ├── corporation.ex
│   │   │       ├── alliance.ex
│   │   │       └── solar_system.ex
│   │   └── janice/
│   │       └── janice_client.ex
│   ├── messaging/                    # Message handling infrastructure
│   │   ├── message_tracker.ex
│   │   ├── connection_monitor.ex
│   │   └── health_checker.ex
│   └── persistence/                  # Data persistence (if needed)
│       └── storage_adapter.ex
├── shared/                           # Shared utilities and cross-cutting concerns
│   ├── config/
│   │   ├── config_provider.ex
│   │   ├── environment.ex
│   │   └── validation.ex
│   ├── utils/
│   │   ├── error_handler.ex
│   │   ├── validation_utils.ex
│   │   ├── time_utils.ex
│   │   ├── batch_processor.ex
│   │   └── startup.ex
│   ├── types/
│   │   ├── constants.ex
│   │   └── common_types.ex
│   └── telemetry/
│       ├── telemetry_manager.ex
│       ├── metrics_collector.ex
│       ├── performance_monitor.ex
│       └── event_analytics.ex
├── schedulers/                       # Background job scheduling
│   ├── base_scheduler.ex
│   ├── service_status_scheduler.ex
│   └── cleanup_scheduler.ex
└── web/                              # Web interface (if keeping)
    ├── controllers/
    ├── views/
    └── templates/
```

## Migration Strategy

### Phase 1: Foundation (Low Risk)
1. **Create new directory structure** without moving files
2. **Standardize naming conventions** for new files
3. **Remove empty directories** (`domains/tracking/clients/`, `domains/notifications/determiner/`)
4. **Consolidate duplicate utilities** (rate limiters, retry logic)

### Phase 2: Domain Consolidation (Medium Risk)
1. **Move `map/` directory** into `domains/tracking/clients/`
2. **Merge `contexts/` logic** into appropriate domains
3. **Reorganize `application/` directory** into `core/`
4. **Consolidate cache implementations**

### Phase 3: Infrastructure Cleanup (Medium Risk)
1. **Restructure `infrastructure/adapters/`** to be service-specific
2. **Consolidate HTTP utilities** into single coherent module
3. **Reorganize shared utilities** for better discoverability
4. **Standardize all module naming**

### Phase 4: Test Alignment (Low Risk)
1. **Reorganize test structure** to mirror main codebase
2. **Standardize test naming** patterns
3. **Create test utilities** in shared locations
4. **Update test documentation**

## File Naming Standards

### Modules
- **Services**: `*_service.ex` (e.g., `notification_service.ex`)
- **Clients**: `*_client.ex` (e.g., `discord_client.ex`)
- **Handlers**: `*_handler.ex` (e.g., `character_event_handler.ex`)
- **Entities**: Plain names (e.g., `killmail.ex`, `character.ex`)
- **Utilities**: `*_utils.ex` (e.g., `formatter_utils.ex`)
- **Behaviours**: `*_behaviour.ex` (e.g., `cache_behaviour.ex`)

### Directories
- Use **singular nouns** for single-concern directories (`cache/`, `config/`)
- Use **plural nouns** for collections (`entities/`, `services/`, `handlers/`)
- Use **descriptive names** that clearly indicate purpose (`formatters/` not `format/`)

## Benefits of This Reorganization

### 1. Improved Maintainability
- **Clear domain boundaries** make it easier to understand and modify business logic
- **Consistent naming** reduces cognitive load when navigating code
- **Logical grouping** makes finding related files intuitive

### 2. Better Testability
- **Aligned test structure** makes it easier to find and maintain tests
- **Clear separation of concerns** enables better unit testing
- **Reduced dependencies** between modules improve test isolation

### 3. Enhanced Developer Experience
- **Predictable structure** helps new developers onboard faster
- **Consistent patterns** reduce decision fatigue when creating new files
- **Clear ownership** makes it obvious where new features should be added

### 4. Reduced Technical Debt
- **Eliminated duplication** reduces maintenance overhead
- **Consistent architecture** prevents architectural drift
- **Clear boundaries** prevent circular dependencies

## Implementation Timeline

- **Week 1**: Phase 1 (Foundation) - Low risk changes
- **Week 2**: Phase 2 (Domain Consolidation) - Update imports and tests
- **Week 3**: Phase 3 (Infrastructure Cleanup) - Careful refactoring with tests
- **Week 4**: Phase 4 (Test Alignment) - Update test structure

## Risk Mitigation

1. **Incremental changes** with full test coverage after each phase
2. **Branch-based implementation** to allow easy rollback
3. **Automated testing** after each file move to catch import issues
4. **Documentation updates** to reflect new structure
5. **Team review** at each phase completion

## Next Steps

1. **Get team approval** for this reorganization plan
2. **Create feature branch** for the reorganization work  
3. **Start with Phase 1** (lowest risk) changes
4. **Update CLAUDE.md** to reflect new structure as changes are made
5. **Update development documentation** and onboarding guides

This reorganization will significantly improve code maintainability, developer experience, and architectural consistency while reducing technical debt and file sprawl.