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

### Current Module Structure (Post-Sprint 4+ Consolidation)
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
│   ├── notifications/                # Notification handling
│   │   ├── entities/                 # Notification entities
│   │   ├── services/                 # Notification logic
│   │   ├── formatters/               # Message formatters
│   │   └── discord/                  # Discord integration
│   └── license/                      # License management
│       ├── entities/                 # License entities
│       └── services/                 # License validation
├── infrastructure/                   # Technical infrastructure
│   ├── http.ex                       # Unified HTTP client with middleware
│   ├── cache.ex                      # Simplified caching (single module)
│   ├── adapters/                     # External service adapters
│   │   ├── esi/                      # EVE Swagger Interface
│   │   └── janice/                   # Janice pricing
│   └── messaging/                    # Message handling
├── map/                              # Real-time map integration
│   ├── sse_client.ex                 # Server-Sent Events client
│   ├── connection_monitor.ex         # Connection health monitoring
│   └── schemas/                      # Map data schemas
├── event_sourcing/                   # Event-driven architecture
│   ├── event.ex                      # Event definitions
│   ├── handlers/                     # Event handlers
│   └── pipeline.ex                   # Event processing pipeline
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
- **Utilities**: `*_utils.ex` in `utils/` directories (e.g., `formatter_utils.ex`, `http_utils.ex`)
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
1. **Application Service** (`lib/wanderer_notifier/application/services/application_service/`) - Consolidated service coordinating all application operations with dependency injection and metrics tracking
2. **Service Initializer** (`lib/wanderer_notifier/application/initialization/service_initializer.ex`) - Multi-phase startup process (infrastructure → foundation → integration → processing)
3. **WebSocket Client** (`lib/wanderer_notifier/domains/killmail/websocket_client.ex`) - Connects to external WandererKills service for real-time pre-enriched killmail data
4. **SSE Client** (`lib/wanderer_notifier/map/sse_client.ex`) - Real-time Server-Sent Events connection to map API for system and character updates with connection monitoring
5. **Processing Context** (`lib/wanderer_notifier/contexts/processing_context/`) - Coordinates killmail processing across domains
6. **Killmail Pipeline** (`lib/wanderer_notifier/domains/killmail/pipeline/`) - Processes killmail data through supervised workers
7. **Event Sourcing** (`lib/wanderer_notifier/event_sourcing/`) - Event-driven architecture for extensible processing
8. **ESI Adapters** (`lib/wanderer_notifier/infrastructure/adapters/`) - Provides additional enrichment using unified HTTP client
9. **Notification Context** (`lib/wanderer_notifier/contexts/notification_context/`) - Coordinates notification processing across domains
10. **Notification Formatters** (`lib/wanderer_notifier/domains/notifications/formatters/`) - Domain-specific message formatting
11. **Discord Integration** (`lib/wanderer_notifier/domains/notifications/discord/`) - Discord bot integration with slash commands and rich notifications

### Domain-Driven Design Principles
The reorganized codebase follows DDD patterns for better maintainability:

- **Domain Boundaries**: Clear separation between killmail, tracking, notifications, and license domains
- **Entity Organization**: Domain entities grouped in `entities/` subdirectories
- **Service Layer**: Business logic encapsulated in domain services
- **Infrastructure Separation**: Technical concerns isolated from business logic
- **Shared Kernel**: Common utilities and types in `shared/` directory
- **Consistent Structure**: All domains follow the same organizational pattern

### Key Infrastructure Components (Post-Sprint 4+ Consolidation)
- **Unified HTTP Client** (`lib/wanderer_notifier/infrastructure/http.ex`): Single module handling all external HTTP requests with:
  - Service-specific configurations (ESI, WandererKills, License, Map, Streaming)
  - Built-in authentication (Bearer, API Key, Basic)
  - Middleware pipeline (Telemetry, RateLimiter, Retry, CircuitBreaker)
  - Automatic JSON encoding/decoding
- **Simplified Cache System**: Consolidated to single module:
  - `infrastructure/cache.ex`: Direct Cachex wrapper with domain-specific helpers and consistent key generation
- **Application Service** (`lib/wanderer_notifier/application/services/application_service/`): Consolidated service handling:
  - Dependency injection via `DependencyManager`
  - Application metrics via `MetricsTracker`
  - Notification coordination via `NotificationCoordinator`
  - State management via `State` module
- **Multi-Phase Initialization** (`lib/wanderer_notifier/application/initialization/service_initializer.ex`): Sophisticated startup process with infrastructure, foundation, integration, and processing phases
- **Context Layer** (`lib/wanderer_notifier/contexts/`): Cross-domain coordination for API, notification, and processing concerns
- **Event Sourcing** (`lib/wanderer_notifier/event_sourcing/`): Event-driven architecture with extensible handlers and processing pipeline
- **Real-Time Map Integration** (`lib/wanderer_notifier/map/`): Advanced SSE client with connection monitoring and health tracking
- **Configuration Management** (`lib/wanderer_notifier/shared/config/`): Comprehensive configuration with validation and feature flags
- **Unified Utilities** (`lib/wanderer_notifier/shared/utils/`): Consolidated error handling, time utilities, and validation
- **Schedulers** (`lib/wanderer_notifier/schedulers/`): Background tasks for periodic updates with registry-based management

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

### Development Environment Setup

#### Option 1: Dev Container (Recommended)
1. Install [Remote - Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Open the repository in VS Code
3. When prompted, reopen the project in the container
4. All dependencies and tools are pre-configured

#### Option 2: Local Development
```bash
# Clone and setup
git clone https://github.com/yourusername/wanderer-notifier.git
cd wanderer-notifier
make deps.get
cp .env.example .env
# Edit .env with your configuration
make compile
make s  # Interactive shell
```

### Debugging and Development Commands
```bash
# Interactive Development
make s
# In IEx:
iex> WandererNotifier.Config.discord_channel_id()
iex> :observer.start()  # GUI monitoring tool

# Check configuration
iex> WandererNotifier.Config.validate_all()

# Inspect cache state  
iex> Cachex.stats(:wanderer_cache)

# Monitor connections
iex> GenServer.call(WandererNotifier.Killmail.WebSocketClient, :status)
iex> GenServer.call(WandererNotifier.Map.SSEClient, :status)
```

### Architecture Evolution Status
The codebase has completed the major reorganization phases and evolved beyond the original 8-sprint plan:

### Completed Major Phases ✅
- **Sprint 1-3**: Foundation, shared utilities, and infrastructure consolidation ✅
- **Sprint 4+**: Core application layer with `ApplicationService` consolidation ✅
- **Infrastructure Unification**: Single HTTP client and cache module ✅
- **Domain Organization**: All business domains properly structured ✅
- **Context Layer**: Cross-domain coordination added ✅
- **Event Sourcing**: Event-driven architecture foundation ✅
- **Real-Time Integration**: Advanced SSE client with monitoring ✅

### Current Architecture State
The application now represents a mature, production-ready architecture with:
- Consolidated `ApplicationService` handling dependency injection, metrics, and coordination
- Multi-phase initialization system for reliable startup
- Context layer for cross-domain operations
- Event sourcing capabilities for future extensibility
- Advanced real-time data integration via SSE
- Unified infrastructure with simplified HTTP and cache systems

## Important Patterns

### Error Handling
- Functions return `{:ok, result}` or `{:error, reason}` tuples
- Use pattern matching for control flow
- Errors are logged via centralized Logger module

### HTTP Client Usage (Unified Infrastructure)
All HTTP requests go through the unified `WandererNotifier.Infrastructure.Http` module which provides:
- Service-specific configurations with predefined settings
- Built-in authentication support (Bearer tokens, API keys)
- Automatic retries with exponential backoff
- Rate limiting enforced per service
- Middleware pipeline: Telemetry → RateLimiter → Retry → CircuitBreaker
- Consistent error handling

Example usage:
```elixir
# Primary request interface for all HTTP methods
Http.request(:get, url, [], nil, service: :esi)
Http.request(:post, url, [], body, service: :wanderer_kills, auth: [type: :bearer, token: token])

# Convenience methods
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

### Caching Strategy (Unified Infrastructure)
Direct cache access via `WandererNotifier.Infrastructure.Cache`:
- Character/corporation/alliance data: 24-hour TTL
- System information: 1-hour TTL
- Notification deduplication: 30-minute window
- Direct Cachex access with domain-specific helpers
- Consistent key generation built into cache module

Example usage:
```elixir
# Domain-specific helpers with automatic key generation
Cache.get_character(character_id)
Cache.put_system(system_id, system_data)
Cache.get_killmail(killmail_id)

# Generic operations with TTL
Cache.get("custom:key")
Cache.put("custom:key", value, :timer.hours(1))

# Cache module handles all key generation internally
# Keys follow pattern: "namespace:type:id" (e.g., "esi:character:123")
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