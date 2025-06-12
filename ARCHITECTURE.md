# WandererNotifier Architecture

This document describes the architectural patterns and design decisions used in the WandererNotifier application.

## Overview

WandererNotifier is an Elixir/OTP application that monitors EVE Online killmail data and sends Discord notifications for significant in-game events. The application follows a modular, behavior-driven architecture with clear separation of concerns.

## Core Design Principles

### 1. Behavior-Driven Design
- All major components define behaviors (protocols) for their interfaces
- Implementations are swappable via configuration
- Facilitates testing through mock implementations

### 2. Separation of Concerns
- GenServers handle only state management and message passing
- Business logic is extracted into pure functional modules
- External service communication is isolated in client modules

### 3. Configuration Management
- Centralized configuration through `WandererNotifier.Config` module
- Environment variables are accessed only through the Config module
- Runtime and compile-time configuration are clearly separated

## Module Organization

### `/lib/wanderer_notifier/`

#### `api/` - Web API Layer
- **controllers/** - HTTP request handlers
- **helpers.ex** - Shared API utilities

#### `cache/` - Caching Layer
- **cache_behaviour.ex** - Cache interface definition
- **cache_helper.ex** - High-level caching utilities
- **config.ex** - Cache-specific configuration
- **keys.ex** - Centralized cache key generation

#### `config/` - Configuration Management
- **config.ex** - Main configuration interface
- **config_behaviour.ex** - Configuration behavior definition
- **utils.ex** - Configuration parsing utilities
- **provider.ex** - Runtime configuration provider

#### `core/` - Core Application Services
- **application/** - Application lifecycle management
  - **service.ex** - Main application GenServer
  - **api.ex** - Public API for configuration access
- **dependencies.ex** - Centralized dependency injection
- **stats.ex** - Application statistics tracking

#### `esi/` - EVE Swagger Interface Integration
- **client.ex** - Low-level ESI API client
- **service.ex** - High-level ESI service layer
- **entities/** - Domain models for ESI data

#### `http/` - HTTP Client and Utilities
- **http_behaviour.ex** - HTTP client behavior
- **headers.ex** - Common HTTP headers
- **response_handler.ex** - Standardized response handling
- **validation.ex** - JSON/HTTP validation
- **utils/** - HTTP utilities
  - **json_utils.ex** - JSON encoding/decoding
  - **rate_limiter.ex** - Rate limiting
  - **retry.ex** - Retry logic

#### `killmail/` - Killmail Processing
- **killmail.ex** - Killmail data structure
- **pipeline.ex** - Processing pipeline
- **processor.ex** - Individual killmail processing
- **enrichment.ex** - Data enrichment
- **cache.ex** - Killmail-specific caching
- **redisq_client.ex** - RedisQ WebSocket client
- **zkill_client.ex** - ZKillboard API client

#### `license/` - License Management
- **service.ex** - License validation service
- **client.ex** - License API client
- **validation.ex** - License validation logic

#### `logger/` - Logging Infrastructure
- **logger.ex** - Main logger module
- **error_logger.ex** - Error-specific logging
- **api_logger_macros.ex** - Logging macros
- **messages.ex** - Log message templates
- **metadata_keys.ex** - Structured logging metadata

#### `map/` - Map Integration
- **clients/** - Map API clients
  - **base_map_client.ex** - Shared client logic
  - **characters_client.ex** - Character tracking
  - **systems_client.ex** - System tracking
- **map_character.ex** - Character domain model
- **map_system.ex** - System domain model

#### `notifications/` - Notification System
- **notification_service.ex** - Main notification service
- **killmail_notification.ex** - Killmail notification logic
- **deduplication/** - Duplicate prevention
- **determiner/** - Notification eligibility
- **formatters/** - Message formatting
- **types/** - Notification type definitions

#### `notifiers/` - Notification Delivery
- **discord/** - Discord integration
  - **notifier.ex** - Main Discord notifier
  - **neo_client.ex** - Nostrum-based client
  - **component_builder.ex** - Discord UI components

#### `schedulers/` - Background Tasks
- **supervisor.ex** - Scheduler supervision tree
- **base_scheduler.ex** - Common scheduler logic
- **character_update_scheduler.ex** - Character updates
- **system_update_scheduler.ex** - System updates

#### `utils/` - Shared Utilities
- **error_handler.ex** - Error handling utilities
- **time_utils.ex** - Time/date utilities

#### `web/` - Web Server
- **router.ex** - HTTP routing
- **server.ex** - Web server GenServer

## Design Patterns

### Dependency Injection

The application uses a standardized dependency injection pattern through the `WandererNotifier.Core.Dependencies` module.

**Centralized Dependencies (PREFERRED)**
```elixir
# All modules should use the centralized Dependencies module
defp esi_service, do: WandererNotifier.Core.Dependencies.esi_service()
defp http_client, do: WandererNotifier.Core.Dependencies.http_client()
defp config_module, do: WandererNotifier.Core.Dependencies.config_module()
```

**Available Dependencies:**
- `esi_service()` - ESI API service
- `esi_client()` - Low-level ESI client
- `http_client()` - HTTP client implementation
- `config_module()` - Configuration module
- `system_module()` - System tracking module
- `character_module()` - Character tracking module
- `killmail_pipeline()` - Killmail processing pipeline
- `deduplication_module()` - Duplicate detection
- `cache_name()` - Cache instance name

**Testing:**
```elixir
# In tests, override dependencies via application env
test "with mock ESI service" do
  Application.put_env(:wanderer_notifier, :esi_service, MockESIService)
  
  # Test code here - will use MockESIService
  
  # Cleanup is automatic with ExUnit's setup
end
```

**Legacy Patterns (being phased out):**
```elixir
# Direct Application.get_env calls (DEPRECATED)
Application.get_env(:wanderer_notifier, :http_client, WandererNotifier.Http)

# Through Config module (acceptable for non-injectable dependencies)
Config.discord_channel_id()
```

### Error Handling
```elixir
# Consistent error tuples
{:ok, result} | {:error, reason}

# Centralized error formatting
ErrorHandler.format_error_reason(:timeout)
# => "Request timed out"

# With pipelines for error propagation
with {:ok, data} <- fetch_data(),
     {:ok, enriched} <- enrich_data(data),
     {:ok, _} <- send_notification(enriched) do
  :ok
else
  {:error, reason} -> 
    ErrorHandler.log_error_with_context(reason, "Pipeline failed", %{step: :notification})
end
```

### Caching Strategy
```elixir
# Centralized cache helper usage
CacheHelper.fetch_with_cache(
  cache_name,
  CacheKeys.character(character_id),
  fn -> fetch_character_from_api(character_id) end,
  ttl: :timer.hours(24)
)
```

### Configuration Access
```elixir
# All configuration through Config module
Config.discord_channel_id()
Config.feature_enabled?(:killmail_notifications)
Config.parse_int(env_value, default)
```

### GenServer Patterns
```elixir
# Separation of concerns
defmodule MyService do
  use GenServer
  
  # GenServer only handles state and messages
  def handle_call(:process, _from, state) do
    result = MyService.Logic.process(state.data)
    {:reply, result, state}
  end
end

defmodule MyService.Logic do
  # Pure business logic
  def process(data) do
    # Complex processing here
  end
end
```

## Testing Strategy

### Behavior-Based Mocking
```elixir
# Define behavior
defmodule MyBehaviour do
  @callback fetch(id :: term()) :: {:ok, term()} | {:error, term()}
end

# Use Mox for testing
Mox.defmock(MyMock, for: MyBehaviour)

# Configure in tests
setup do
  stub(MyMock, :fetch, fn _id -> {:ok, %{}} end)
  :ok
end
```

### Test Helpers
```elixir
# Centralized test utilities
use WandererNotifier.Test.Support.TestHelpers

setup do
  setup_mox_defaults()
  setup_tracking_mocks(tracked_systems: [30000142])
  :ok
end
```

## Performance Considerations

### Compile-Time Optimization
- Configuration values that don't change are resolved at compile time
- Module references for performance-critical paths use compile-time injection

### Caching
- Multi-level caching with appropriate TTLs
- Character/Corp/Alliance data: 24-hour TTL
- System information: 1-hour TTL
- Deduplication: 30-minute window

### Rate Limiting
- Centralized rate limiting for all external API calls
- Exponential backoff with jitter
- Respects rate limit headers

## Security

### Environment Variables
- Sensitive data only in environment variables
- No secrets in code or configuration files
- Environment variables accessed only through Config module

### API Token Management
- Tokens stored securely in environment
- Token validation through dedicated modules
- No token logging

## Future Improvements

### Planned Enhancements
1. Circuit breaker pattern for external services
2. Event sourcing for killmail history
3. Metrics collection and monitoring
4. WebSocket connection pooling

### Technical Debt & Coupling Analysis

**Major Coupling Concerns Identified:**
1. **Notification Formatters** - Heavy cross-module dependencies to Map, ESI, and Killmail modules
2. **Map Clients** - Circular dependencies with Notification Determiners  
3. **Cross-Domain References** - Direct module references instead of behavior-based interfaces

**Recommended Coupling Reductions:**
1. **Extract Formatter Interfaces** - Create behavior definitions for formatters to reduce direct dependencies
2. **Event-Driven Architecture** - Replace direct calls between Map and Notifications with event publishing
3. **Repository Pattern** - Abstract data access through repository interfaces instead of direct module calls
4. **Dependency Inversion** - Use the new `Dependencies` module consistently across all modules

**Completed Improvements:**
1. ✅ Centralized dependency injection through `WandererNotifier.Core.Dependencies`
2. ✅ Unified HTTP response handling
3. ✅ Consolidated caching patterns
4. ✅ Standardized HTTP headers

## Deployment

### Docker Support
- Dockerfile provided for containerized deployment
- Environment-based configuration
- Health check endpoints

### Supervision Tree
```
Application
├── Stats
├── License.Service
├── Schedulers.Supervisor
│   ├── CharacterUpdateScheduler
│   ├── SystemUpdateScheduler
│   └── ServiceStatusScheduler
├── RedisQClient
├── Web.Server
└── Core.Application.Service
```

## Monitoring

### Health Checks
- `/health` - Basic health check
- `/ready` - Readiness check including external services

### Logging
- Structured logging with metadata
- Different log levels for different components
- Error aggregation support

### Statistics
- Kill processing metrics
- Notification delivery stats
- API call performance tracking