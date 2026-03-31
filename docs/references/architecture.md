# Architecture Reference

## Module Structure (Post-Sprint 4+ Consolidation)

```
lib/wanderer_notifier/
├── application/                      # Application coordination layer
│   ├── services/application_service/ # Consolidated application service
│   │   ├── dependency_manager.ex     # Dependency injection system
│   │   ├── metrics_tracker.ex        # Application metrics
│   │   ├── notification_coordinator.ex # Notification processing
│   │   └── state.ex                  # Application state management
│   └── initialization/
│       └── service_initializer.ex    # Multi-phase startup process
├── contexts/                         # Cross-domain coordination
│   ├── api_context/                  # API layer coordination
│   ├── notification_context/         # Notification handling
│   └── processing_context/           # Killmail processing coordination
├── domains/                          # Business logic domains (DDD)
│   ├── killmail/                     # Killmail processing domain
│   │   ├── entities/                 # Killmail domain entities
│   │   ├── services/                 # Processing and client services
│   │   ├── pipeline/                 # Pipeline and enrichment logic
│   │   └── utils/                    # Domain-specific utilities
│   ├── tracking/                     # Character and system tracking
│   │   ├── entities/                 # Character and System entities
│   │   ├── services/                 # Tracking services
│   │   └── handlers/                 # Event handlers
│   │       ├── character_handler.ex  # Character event handling
│   │       ├── system_handler.ex     # System event handling
│   │       ├── generic_event_handler.ex # Shared handler logic
│   │       ├── shared_event_logic.ex # Common event utilities
│   │       └── event_handler_behaviour.ex # Handler behaviour
│   ├── notifications/                # Notification handling
│   │   ├── entities/                 # Notification entities
│   │   ├── services/                 # Notification logic
│   │   ├── formatters/               # Message formatters
│   │   └── discord/                  # Discord integration
│   │       ├── notifier.ex           # Main notification dispatcher
│   │       ├── neo_client.ex         # Discord API client
│   │       ├── channel_resolver.ex   # Channel routing logic
│   │       ├── enrichment_helper.ex  # System name enrichment
│   │       ├── component_builder.ex  # UI component construction
│   │       ├── feature_flags.ex      # Feature flag checks
│   │       ├── constants.ex          # Discord constants
│   │       ├── connection_health.ex  # Connection monitoring
│   │       └── discord_behaviour.ex  # Behaviour definition
│   └── license/                      # License management
│       ├── license.ex                # License entity
│       ├── license_service.ex        # License business logic
│       ├── license_validator.ex      # Pure validation functions
│       └── license_client.ex         # HTTP client for license API
├── infrastructure/                   # Technical infrastructure
│   ├── http.ex                       # Unified HTTP client with middleware
│   ├── cache.ex                      # Main cache interface
│   ├── cache/                        # Cache submodules
│   │   ├── keys.ex                   # Centralized cache key generation
│   │   ├── ttl_config.ex             # TTL configuration
│   │   └── deduplication.ex          # Notification deduplication
│   ├── adapters/                     # External service adapters
│   │   ├── esi/                      # EVE Swagger Interface
│   │   └── janice/                   # Janice pricing
│   └── messaging/                    # Message handling
├── map/                              # Real-time map integration
│   ├── sse_client.ex                 # Server-Sent Events client
│   ├── connection_monitor.ex         # Connection health monitoring
│   └── schemas/                      # Map data schemas
├── shared/                           # Cross-cutting concerns
│   ├── config/                       # Configuration management
│   ├── utils/                        # Shared utilities
│   ├── types/                        # Common types and constants
│   └── telemetry/                    # Monitoring and metrics
└── schedulers/                       # Background job scheduling
```

## Data Flow

1. **Application Service** (`lib/wanderer_notifier/application/services/application_service/`) - Consolidated service coordinating all application operations with dependency injection and metrics tracking
2. **Service Initializer** (`lib/wanderer_notifier/application/initialization/service_initializer.ex`) - Multi-phase startup process (infrastructure -> foundation -> integration -> processing)
3. **WebSocket Client** (`lib/wanderer_notifier/domains/killmail/websocket_client.ex`) - Connects to external WandererKills service for real-time pre-enriched killmail data
4. **SSE Client** (`lib/wanderer_notifier/map/sse_client.ex`) - Real-time Server-Sent Events connection to map API for system and character updates with connection monitoring
5. **Processing Context** (`lib/wanderer_notifier/contexts/processing_context/`) - Coordinates killmail processing across domains
6. **Killmail Pipeline** (`lib/wanderer_notifier/domains/killmail/pipeline/`) - Processes killmail data through supervised workers
7. **ESI Adapters** (`lib/wanderer_notifier/infrastructure/adapters/`) - Provides additional enrichment using unified HTTP client
8. **Notification Context** (`lib/wanderer_notifier/contexts/notification_context/`) - Coordinates notification processing across domains
9. **Notification Formatters** (`lib/wanderer_notifier/domains/notifications/formatters/`) - Domain-specific message formatting
10. **Discord Integration** (`lib/wanderer_notifier/domains/notifications/discord/`) - Discord bot integration with slash commands and rich notifications

## Domain-Driven Design Principles

- **Domain Boundaries**: Clear separation between killmail, tracking, notifications, and license domains
- **Entity Organization**: Domain entities grouped in `entities/` subdirectories
- **Service Layer**: Business logic encapsulated in domain services
- **Infrastructure Separation**: Technical concerns isolated from business logic
- **Shared Kernel**: Common utilities and types in `shared/` directory
- **Consistent Structure**: All domains follow the same organizational pattern

## Key Infrastructure Components

- **Unified HTTP Client** (`infrastructure/http.ex`): Single module for all external HTTP requests with service-specific configs, built-in auth, middleware pipeline (Telemetry -> RateLimiter -> Retry -> CircuitBreaker)
- **Cache System** (`infrastructure/cache.ex`): Cachex wrapper with `cache/keys.ex` (key generation), `cache/ttl_config.ex` (TTL config), `cache/deduplication.ex` (dedup logic)
- **Simple Dependency Resolution** (`shared/dependencies.ex`): Lightweight function-based DI
- **Lightweight Application Service** (`application/services/simple_application_service.ex`): Minimal coordinator
- **Modular Metrics & Health** (`shared/metrics.ex`, `shared/health.ex`): Agent-based metrics and process-based health checks
- **Multi-Phase Initialization** (`application/initialization/service_initializer.ex`): Infrastructure -> foundation -> integration -> processing phases
- **Real-Time Map Integration** (`map/`): SSE client with connection monitoring
- **Simplified Configuration** (`shared/config.ex`): Direct `Application.get_env` access
- **Schedulers** (`schedulers/`): Background tasks for periodic updates

## File Naming Standards

### Module Types
- **Services**: `*_service.ex` (e.g., `notification_service.ex`)
- **Clients**: `*_client.ex` (e.g., `discord_client.ex`)
- **Handlers**: `*_handler.ex` (e.g., `character_event_handler.ex`)
- **Entities**: Plain names (e.g., `killmail.ex`, `character.ex`)
- **Utilities**: `*_utils.ex` in `utils/` directories
- **Behaviours**: `*_behaviour.ex`
- **Middleware**: `*_middleware.ex`
- **Formatters**: `*_formatter.ex`

### Directory Conventions
- **Singular nouns** for single-concern directories (`cache/`, `config/`)
- **Plural nouns** for collections (`entities/`, `services/`, `handlers/`)
- **Domain grouping** under `domains/` for business logic
- **Technical grouping** under `infrastructure/` for technical concerns
