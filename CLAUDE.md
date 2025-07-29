# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Wanderer Notifier is an Elixir/OTP application that monitors EVE Online killmail data and sends Discord notifications for significant in-game events. It integrates with an external WandererKills service via WebSocket for real-time pre-enriched killmail data, EVE Swagger Interface (ESI) for additional data enrichment when needed, and Wanderer map APIs via Server-Sent Events (SSE) to track wormhole systems and character activities in real-time.

## Common Development Commands

### Build & Compile

```bash
make compile           # Compile the project
make compile.strict    # Compile with warnings as errors
make deps.get         # Fetch dependencies
make deps.update      # Update all dependencies
make clean            # Clean build artifacts
```

### Testing

```bash
make test             # Run tests using custom script
make test.killmail    # Run specific module tests (replace 'killmail' with module name)
make test.all         # Run all tests with trace
make test.watch       # Run tests in watch mode
make test.cover       # Run tests with coverage
```

### Development

```bash
make s                # Clean, compile, and start interactive shell
make format           # Format code using Mix format
make server-status    # Check web server connectivity
```

### Docker & Production

```bash
make docker.build     # Build Docker image
make docker.test      # Test Docker image
make release          # Build production release
docker-compose up -d  # Run locally with Docker
```

## High-Level Architecture

The application follows a refactored, domain-driven design with these core components:

### Current Module Structure (Post-Reorganization Sprint 1)
```
lib/wanderer_notifier/
├── core/                             # Application layer concerns
│   ├── supervisors/                  # Application supervisors
│   └── services/                     # Cross-domain services
├── domains/                          # Business logic domains (DDD approach)
│   ├── killmail/                     # Killmail processing domain
│   │   ├── entities/                 # Killmail domain entities
│   │   ├── services/                 # Processing and client services
│   │   ├── pipeline/                 # Pipeline and enrichment logic
│   │   └── utils/                    # Domain-specific utilities
│   ├── tracking/                     # Character and system tracking
│   │   ├── entities/                 # Character and System entities
│   │   ├── services/                 # Tracking services
│   │   ├── clients/                  # SSE and map clients
│   │   └── handlers/                 # Event handlers
│   ├── notifications/                # Notification handling
│   │   ├── entities/                 # Notification entities
│   │   ├── services/                 # Notification logic
│   │   ├── formatters/               # Message formatters
│   │   └── channels/discord/         # Discord integration
│   └── license/                      # License management
│       ├── entities/                 # License entities
│       └── services/                 # License validation
├── infrastructure/                   # Technical infrastructure
│   ├── http/                         # HTTP client with middleware
│   │   ├── middleware/               # Rate limiting, retry, telemetry
│   │   └── utils/                    # HTTP utilities
│   ├── cache/                        # Caching infrastructure
│   ├── adapters/                     # External service adapters
│   │   ├── esi/                      # EVE Swagger Interface
│   │   └── janice/                   # Janice pricing
│   ├── messaging/                    # Message handling
│   └── persistence/                  # Data persistence (future)
├── shared/                           # Cross-cutting concerns
│   ├── config/                       # Configuration management
│   ├── utils/                        # Shared utilities
│   ├── types/                        # Common types and constants
│   └── telemetry/                    # Monitoring and metrics
└── schedulers/                       # Background job scheduling
```

## File Naming Standards

### Module Types
- **Services**: `*_service.ex` (e.g., `notification_service.ex`, `license_service.ex`)
- **Clients**: `*_client.ex` (e.g., `discord_client.ex`, `sse_client.ex`)
- **Handlers**: `*_handler.ex` (e.g., `character_event_handler.ex`)
- **Entities**: Plain names (e.g., `killmail.ex`, `character.ex`, `system.ex`)
- **Utilities**: `*_utils.ex` (e.g., `formatter_utils.ex`, `http_utils.ex`)
- **Behaviours**: `*_behaviour.ex` (e.g., `cache_behaviour.ex`)
- **Middleware**: `*_middleware.ex` (e.g., `retry_middleware.ex`)
- **Formatters**: `*_formatter.ex` (e.g., `killmail_formatter.ex`)

### Directory Conventions
- **Singular nouns** for single-concern directories (`cache/`, `config/`)
- **Plural nouns** for collections (`entities/`, `services/`, `handlers/`)
- **Descriptive names** that clearly indicate purpose (`formatters/` not `format/`)
- **Domain grouping** under `domains/` for business logic
- **Technical grouping** under `infrastructure/` for technical concerns
```

### Data Flow
1. **WebSocket Client** (`lib/wanderer_notifier/domains/killmail/websocket_client.ex`) - Connects to external WandererKills service for real-time pre-enriched killmail data
2. **Fallback Handler** (`lib/wanderer_notifier/domains/killmail/fallback_handler.ex`) - Automatically switches to HTTP API when WebSocket connection fails, ensuring data continuity
3. **WandererKills API** (`lib/wanderer_notifier/domains/killmail/wanderer_kills_api.ex`) - Type-safe HTTP client for WandererKills API with bulk loading support
4. **SSE Client** (`lib/wanderer_notifier/map/sse_client.ex`) - Real-time connection to map API for system and character updates
5. **Unified Tracking Client** (`lib/wanderer_notifier/domains/tracking/clients/unified_client.ex`) - Single client handling both characters and systems with entity context switching
6. **Killmail Pipeline** (`lib/wanderer_notifier/domains/killmail/pipeline.ex`) - Processes flattened killmail data with string key normalization
7. **ESI Adapters** (`lib/wanderer_notifier/infrastructure/adapters/`) - Provides additional enrichment using unified HTTP client
8. **Shared Event Logic** (`lib/wanderer_notifier/domains/tracking/handlers/shared_event_logic.ex`) - Common event processing patterns for all tracking domains
9. **Unified Notification Formatter** (`lib/wanderer_notifier/domains/notifications/formatters/unified.ex`) - Single formatter handling all notification types
10. **Discord Notifiers** (`lib/wanderer_notifier/domains/notifications/notifiers/discord/`) - Sends formatted notifications to Discord channels

### Domain-Driven Design Principles
The reorganized codebase follows DDD patterns for better maintainability:

- **Domain Boundaries**: Clear separation between killmail, tracking, notifications, and license domains
- **Entity Organization**: Domain entities grouped in `entities/` subdirectories
- **Service Layer**: Business logic encapsulated in domain services
- **Infrastructure Separation**: Technical concerns isolated from business logic
- **Shared Kernel**: Common utilities and types in `shared/` directory
- **Consistent Structure**: All domains follow the same organizational pattern

### Key Infrastructure Components (Post-Sprint 2 Simplification)
- **Unified HTTP Client** (`lib/wanderer_notifier/infrastructure/http.ex`): Single module handling all external HTTP requests with:
  - Service-specific configurations (ESI, WandererKills, License, Map, Streaming)
  - Built-in authentication (Bearer, API Key, Basic)
  - Middleware pipeline (Telemetry, RateLimiter, Retry, CircuitBreaker)
  - Automatic JSON encoding/decoding
- **Simplified Cache System**: Reduced from 15 modules to 3 core modules:
  - `Cache.ex`: Direct Cachex wrapper for all cache operations
  - `ConfigSimple.ex`: Simple TTL configuration (24h for entities, 1h for systems, 30m for killmails)
  - `KeysSimple.ex`: Consistent key generation (e.g., "esi:character:123")
- **Configuration Management** (`lib/wanderer_notifier/shared/config/`): Macro-based configuration with validation and feature flags
- **Error Handling** (`lib/wanderer_notifier/shared/utils/error_handler.ex`): Centralized error handling with retry mechanisms
- **Logging System** (`lib/wanderer_notifier/shared/logger/`): Simplified logging with category support and metadata handling
- **Schedulers** (`lib/wanderer_notifier/schedulers/`): Background tasks for periodic updates with registry-based management
- **License Service**: Controls feature availability (premium embeds vs free text notifications)

### Configuration
- Environment variables are loaded without the WANDERER_ prefix (e.g., `DISCORD_BOT_TOKEN` instead of `WANDERER_DISCORD_BOT_TOKEN`)
- Configuration layers: `config/config.exs` (compile-time) → `config/runtime.exs` (runtime with env vars)
- Local development uses `.env` file via Dotenvy
- **WebSocket Configuration**: `WEBSOCKET_URL` (default: "ws://host.docker.internal:4004") for killmail processing
- **WandererKills Configuration**: `WANDERER_KILLS_URL` (default: "http://host.docker.internal:4004")
- **SSE Configuration**: Automatically configured from MAP_URL/MAP_NAME/MAP_API_KEY for real-time map events
- **Discord Configuration**: `DISCORD_BOT_TOKEN` and `DISCORD_APPLICATION_ID` required for slash commands
- **Core Services**: Killmail processing via WebSocket and map synchronization via SSE are always enabled

### Testing Approach
- Heavy use of Mox for behavior-based mocking
- Test modules follow the same structure as implementation modules
- Mock implementations in `test/support/mocks/`
- Fixture data in `test/support/fixtures/`
- **Test Coverage Progress**: Significantly improved from 19.5% to 150+ comprehensive tests
- **Test Suite Status**: Reduced failures from 185 → 10 (94.6% improvement)
- **Infrastructure Testing**: Complete test coverage for HTTP client, cache system, license service
- **Integration Tests**: Full flow testing from WebSocket/SSE to Discord delivery
- **Unit Tests**: Comprehensive testing of individual modules and functions with proper mocking

## Development Standards

### Quality Gates (Mandatory)
Every code change must pass these quality checks before committing:
1. **`make compile`** - No compilation errors allowed
2. **`make test`** - All tests must pass (100%)
3. **`mix credo --strict`** - No credo issues allowed
4. **`mix dialyzer`** - No dialyzer warnings allowed

### Commit Standards
- **Frequency**: Minimum 2-3 commits per day, ideally after each task completion
- **Message format**: `[Sprint X.Y] Description of change`  
- **Never**: Leave broken code uncommitted overnight
- **Quality first**: Fix all quality issues before continuing to next task

### Migration Progress
The codebase is currently undergoing a structured 8-sprint reorganization:
- **Sprint 1** (Weeks 1-2): Foundation setup and directory structure ✅
- **Sprint 2** (Weeks 3-4): Shared utilities consolidation
- **Sprint 3** (Weeks 5-6): Infrastructure reorganization  
- **Sprint 4** (Weeks 7-8): Core application layer
- **Sprint 5** (Weeks 9-10): Killmail domain reorganization
- **Sprint 6** (Weeks 11-12): Tracking domain and map integration
- **Sprint 7** (Weeks 13-14): Notifications domain
- **Sprint 8** (Weeks 15-16): Testing alignment and documentation

## Important Patterns

### Error Handling
- Functions return `{:ok, result}` or `{:error, reason}` tuples
- Use pattern matching for control flow
- Errors are logged via centralized Logger module

### HTTP Client Usage (Simplified in Sprint 2)
All HTTP requests go through the unified `WandererNotifier.Infrastructure.Http` module which provides:
- Service-specific configurations with predefined settings
- Built-in authentication support (Bearer tokens, API keys)
- Automatic retries with exponential backoff
- Rate limiting enforced per service
- Middleware pipeline: Telemetry → RateLimiter → Retry → CircuitBreaker
- Consistent error handling

Example usage:
```elixir
# Single request/5 interface for all HTTP methods
Http.request(:get, url, [], nil, service: :esi)
Http.request(:post, url, [], body, service: :wanderer_kills, auth: [type: :bearer, token: token])

# Legacy convenience methods (deprecated, use request/5)
Http.get(url, [], service: :esi)

# POST with authentication
Http.post(url, body, [], 
  service: :license,
  auth: [type: :bearer, token: api_token]
)

# With custom options
Http.get(url, [], [
  service: :wanderer_kills,
  timeout: 20_000,
  retry_count: 5
])
```

Service configurations:
- `:esi` - 30s timeout, 3 retries, 20 req/s rate limit
- `:wanderer_kills` - 15s timeout, 2 retries, 10 req/s rate limit  
- `:license` - 10s timeout, 1 retry, 1 req/s rate limit
- `:map` - 45s timeout, 2 retries, no rate limit
- `:streaming` - Infinite timeout, no retries, no middleware

### Caching Strategy (Simplified in Sprint 2)
Direct cache access via `WandererNotifier.Infrastructure.Cache`:
- Character/corporation/alliance data: 24-hour TTL
- System information: 1-hour TTL
- Notification deduplication: 30-minute window
- Direct Cachex access without abstraction layers
- Simple key generation via `KeysSimple` module

Example usage:
```elixir
# Domain-specific helpers
Cache.get_character(character_id)
Cache.put_system(system_id, system_data)

# Generic operations with TTL
Cache.get("custom:key")
Cache.put("custom:key", value, :timer.hours(1))

# Key generation
alias WandererNotifier.Infrastructure.Cache.KeysSimple, as: Keys
key = Keys.character(123)  # "esi:character:123"
```

### Feature Flags

Features can be toggled via environment variables ending in `_ENABLED`:

- `NOTIFICATIONS_ENABLED` - Master toggle for all notifications (default: true)
- `KILL_NOTIFICATIONS_ENABLED` - Enable/disable kill notifications (default: true)
- `SYSTEM_NOTIFICATIONS_ENABLED` - Enable/disable system notifications (default: true)
- `CHARACTER_NOTIFICATIONS_ENABLED` - Enable/disable character notifications (default: true)
- `ENABLE_STATUS_MESSAGES` - Enable/disable startup status messages (default: false)
- `TRACK_KSPACE_ENABLED` - Enable/disable K-Space system tracking (default: true)
- `PRIORITY_SYSTEMS_ONLY` - Only send notifications for priority systems (default: false)