# WandererNotifier Architecture

This document describes the architectural patterns and design decisions used in the WandererNotifier application.

## Overview

WandererNotifier is an Elixir/OTP application that monitors EVE Online killmail data and sends Discord notifications for significant in-game events. The application follows a domain-driven, event-driven architecture built on real-time data streams with clear separation of concerns and fault tolerance.

## Core Design Principles

### 1. Real-Time Event-Driven Architecture
- WebSocket connections for real-time pre-enriched killmail data
- Server-Sent Events (SSE) for live map synchronization
- Event-driven processing with minimal polling
- Fault-tolerant supervision trees for connection reliability

### 2. Behavior-Driven Design
- All major components define behaviors (protocols) for their interfaces
- Implementations are swappable via configuration
- Facilitates testing through mock implementations
- Clear separation between interface and implementation

### 3. Separation of Concerns
- GenServers handle only state management and message passing
- Business logic is extracted into pure functional modules
- External service communication is isolated in client modules
- Context modules provide domain boundaries

### 4. Configuration Management
- Centralized configuration through `WandererNotifier.Config` module
- Environment variables are accessed only through the Config module
- Runtime and compile-time configuration are clearly separated
- Feature flags for dynamic behavior control

## High-Level Data Flow

### Real-Time Processing Pipeline
1. **WebSocket Client** (`killmail/websocket_client.ex`) - Receives pre-enriched killmail data from WandererKills service
2. **SSE Client** (`map/sse_client.ex`) - Processes real-time map events for system and character tracking
3. **Event Processing** (`map/event_processor.ex`) - Handles SSE events through dedicated event handlers
4. **Killmail Pipeline** (`killmail/pipeline.ex`) - Processes killmails through supervised workers
5. **Notification System** (`notifications/`) - Determines eligibility, applies license limits, and formats messages
6. **Discord Delivery** (`notifiers/discord/`) - Sends rich embed or text notifications to configured channels

### Key Services
- **WebSocket Infrastructure**: Real-time connection to WandererKills service for pre-enriched killmail data
- **SSE Infrastructure**: Complete Server-Sent Events system with connection management, parsing, and event handling for real-time map updates
- **Discord Bot Services**: Full Discord integration with slash command registration, event consumption, and interaction handling
- **Cache Layer**: Multi-adapter caching system (Cachex/ETS) with unified key management and configurable TTLs
- **License Service**: Controls feature availability (premium embeds vs free text notifications) with license limiting
- **Telemetry System**: Comprehensive application metrics and structured logging
- **HTTP Client**: Centralized HTTP client with retry logic, rate limiting, and structured error handling

## Module Organization

### `/lib/wanderer_notifier/`

#### Root Level Modules
- **application.ex** - Main OTP application module
- **command_log.ex** - Command logging functionality
- **constants.ex** - Application-wide constants
- **http.ex** - Main HTTP client module
- **notification_service.ex** - Legacy notification service
- **persistent_values.ex** - Persistent state storage
- **telemetry.ex** - Application telemetry and metrics

#### `contexts/` - Domain Contexts
- **external_adapters.ex** - External service adapters context
- **killmail.ex** - Killmail context module

#### `discord/` - Discord Bot Infrastructure
- **command_registrar.ex** - Discord slash command registration
- **consumer.ex** - Discord event consumer

#### `supervisors/` - Supervision Trees
- **external_adapters_supervisor.ex** - External adapters supervision
- **killmail_supervisor.ex** - Killmail processing supervision

#### `api/` - Web API Layer
- **api_pipeline.ex** - API request processing pipeline
- **helpers.ex** - Shared API utilities
- **controllers/** - HTTP request handlers
  - **controller_helpers.ex** - Shared controller utilities
  - **dashboard_controller.ex** - Dashboard endpoint handler
  - **health_controller.ex** - Health check endpoints
  - **system_info.ex** - System information endpoint

#### `cache/` - Caching Layer
- **adapter.ex** - Cache adapter interface
- **cache_behaviour.ex** - Cache interface definition
- **cache_helper.ex** - High-level caching utilities
- **cache_key.ex** - Cache key data structure
- **config.ex** - Cache-specific configuration
- **ets_cache.ex** - ETS-based cache implementation
- **key_generator.ex** - Cache key generation logic
- **keys.ex** - Centralized cache key generation

#### `config/` - Configuration Management
- **config.ex** - Main configuration interface
- **config_behaviour.ex** - Configuration behavior definition
- **env_provider.ex** - Environment variable provider
- **helpers.ex** - Configuration helper utilities
- **provider.ex** - Runtime configuration provider
- **system_env_provider.ex** - System environment provider
- **utils.ex** - Configuration parsing utilities
- **version.ex** - Version information

#### `core/` - Core Application Services
- **dependencies.ex** - Centralized dependency injection
- **stats.ex** - Application statistics tracking
- **application/** - Application lifecycle management
  - **service.ex** - Main application GenServer
  - **api.ex** - Public API for configuration access

#### `esi/` - EVE Swagger Interface Integration
- **client.ex** - Low-level ESI API client
- **client_behaviour.ex** - ESI client behavior
- **service.ex** - High-level ESI service layer
- **service_behaviour.ex** - ESI service behavior
- **service_stub.ex** - ESI service stub for testing
- **entities/** - Domain models for ESI data
  - **alliance.ex** - Alliance information
  - **character.ex** - Character information
  - **corporation.ex** - Corporation information
  - **solar_system.ex** - Solar system information

#### `http/` - HTTP Client and Utilities
- **headers.ex** - Common HTTP headers
- **http_behaviour.ex** - HTTP client behavior
- **response_handler.ex** - Standardized response handling
- **validation.ex** - JSON/HTTP validation
- **utils/** - HTTP utilities
  - **json_utils.ex** - JSON encoding/decoding
  - **rate_limiter.ex** - Rate limiting
  - **retry.ex** - Retry logic

#### `killmail/` - Killmail Processing
- **killmail.ex** - Killmail data structure
- **pipeline.ex** - Processing pipeline
- **pipeline_worker.ex** - Pipeline worker process
- **processor.ex** - Individual killmail processing
- **enrichment.ex** - Data enrichment
- **cache.ex** - Killmail-specific caching
- **websocket_client.ex** - WebSocket client for real-time killmail data
- **wanderer_kills_client.ex** - WandererKills API client
- **notification.ex** - Killmail notification logic
- **notification_checker.ex** - Notification eligibility checking
- **context.ex** - Killmail processing context
- **supervisor.ex** - Killmail supervision tree
- **json_encoders.ex** - JSON encoding for killmails
- **schema.ex** - Killmail data schema

#### `license/` - License Management
- **client.ex** - License API client
- **service.ex** - License validation service
- **validation.ex** - License validation logic

#### `logger/` - Logging Infrastructure
- **api_logger_macros.ex** - Logging macros
- **emojis.ex** - Emoji constants for logging
- **error_logger.ex** - Error-specific logging
- **logger.ex** - Main logger module
- **logger_behaviour.ex** - Logger behavior interface
- **messages.ex** - Log message templates
- **metadata_keys.ex** - Structured logging metadata
- **structured_logger.ex** - Structured logging implementation

#### `map/` - Map Integration
- **sse_client.ex** - Server-Sent Events client for real-time map updates
- **sse_connection.ex** - SSE connection management
- **sse_parser.ex** - SSE data parsing
- **sse_supervisor.ex** - SSE supervision tree
- **event_processor.ex** - Map event processing
- **initializer.ex** - Map initialization
- **map_character.ex** - Character domain model
- **map_system.ex** - System domain model
- **map_util.ex** - Map utilities
- **system_static_info.ex** - Static system information
- **tracking_behaviour.ex** - Tracking behavior interface
- **clients/** - Map API clients
  - **base_map_client.ex** - Shared client logic
  - **characters_client.ex** - Character tracking
  - **systems_client.ex** - System tracking
- **event_handlers/** - Event handling
  - **character_handler.ex** - Character event handling
  - **system_handler.ex** - System event handling

#### `notifications/` - Notification System
- **notification_service.ex** - Main notification service
- **killmail_notification.ex** - Killmail notification logic
- **discord_notifier.ex** - Discord notification service
- **discord_notifier_behaviour.ex** - Discord notifier behavior
- **dispatcher_behaviour.ex** - Notification dispatcher behavior
- **factory.ex** - Notification factory
- **killmail_notification_behaviour.ex** - Killmail notification behavior
- **license_limiter.ex** - License-based notification limiting
- **neo_client.ex** - Nostrum-based Discord client
- **utils.ex** - Notification utilities
- **deduplication/** - Duplicate prevention
  - **cache_impl.ex** - Cache-based deduplication
  - **deduplication.ex** - Deduplication logic
  - **deduplication_behaviour.ex** - Deduplication behavior
- **determiner/** - Notification eligibility
  - **character.ex** - Character notification determination
  - **kill.ex** - Kill notification determination
  - **kill_behaviour.ex** - Kill determination behavior
  - **system.ex** - System notification determination
- **formatters/** - Message formatting
  - **character.ex** - Character message formatting
  - **character_utils.ex** - Character formatting utilities
  - **common.ex** - Common formatting utilities
  - **killmail.ex** - Killmail message formatting
  - **plain_text.ex** - Plain text formatting
  - **status.ex** - Status message formatting
  - **system.ex** - System message formatting
- **types/** - Notification type definitions
  - **notification.ex** - Notification type definition

#### `notifiers/` - Notification Delivery
- **test.ex** - Test notifier
- **test_notifier.ex** - Test notification implementation
- **discord/** - Discord integration
  - **notifier.ex** - Main Discord notifier
  - **neo_client.ex** - Nostrum-based client
  - **component_builder.ex** - Discord UI components
  - **constants.ex** - Discord constants
  - **discord_behaviour.ex** - Discord behavior interface
  - **feature_flags.ex** - Discord feature flags

#### `schedulers/` - Background Tasks
- **supervisor.ex** - Scheduler supervision tree
- **base_scheduler.ex** - Common scheduler logic
- **registry.ex** - Scheduler registry
- **scheduler.ex** - Main scheduler interface
- **service_status_scheduler.ex** - Service status monitoring

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

### Real-Time Optimization
- WebSocket connections eliminate polling overhead
- SSE streams provide immediate map updates
- Pre-enriched data reduces ESI API calls
- Connection pooling and supervision for reliability

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
│   └── ServiceStatusScheduler
├── Killmail.Supervisor
│   ├── WebSocketClient
│   └── PipelineWorker
├── Map.SSE.Supervisor
│   └── SSEClient
├── ExternalAdapters.Supervisor
├── Discord.Consumer
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
- Real-time connection status

## Configuration

### Environment Variables
The application supports comprehensive configuration through environment variables:

#### Required
- `DISCORD_BOT_TOKEN` - Discord bot authentication
- `DISCORD_APPLICATION_ID` - Discord application ID
- `DISCORD_CHANNEL_ID` - Primary notification channel
- `MAP_URL`, `MAP_NAME`, `MAP_API_KEY` - Map API configuration
- `LICENSE_KEY` - License for premium features

#### Optional Features
- Feature flags: `*_NOTIFICATIONS_ENABLED`, `PRIORITY_SYSTEMS_ONLY`, etc.
- Service URLs: `WEBSOCKET_URL`, `WANDERER_KILLS_URL`
- Channel routing: `DISCORD_*_CHANNEL_ID` variants
- Advanced configuration: Cache, SSE, and performance tuning options

### Configuration Layers
1. Compile-time configuration (`config/config.exs`)
2. Runtime configuration (`config/runtime.exs`)
3. Environment variables (highest priority)
4. Default values in code

### Legacy Support
Maintains backward compatibility with `WANDERER_` prefixed environment variables through the release overlay system.

## Future Improvements

### Planned Enhancements
1. Circuit breaker pattern for external services
2. Event sourcing for killmail history
3. Enhanced metrics collection and monitoring
4. WebSocket connection pooling
5. Multi-guild Discord bot support

### Architecture Evolution
The application has evolved significantly from a polling-based system to a real-time event-driven architecture:

- **From ZKillboard/RedisQ to WandererKills/WebSocket** - Eliminated polling overhead
- **Added SSE Infrastructure** - Real-time map synchronization
- **Enhanced Discord Integration** - Full bot capabilities with slash commands
- **Improved Supervision** - More granular fault tolerance
- **Advanced Caching** - Multi-adapter system with intelligent key management

The modular design supports continued evolution while maintaining backward compatibility and operational stability.