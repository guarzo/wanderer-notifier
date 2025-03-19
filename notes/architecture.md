# Wanderer Notifier Architecture

## System Architecture

Wanderer Notifier follows a modular OTP-based architecture with clear separation of concerns. The application is structured as a supervision tree with multiple GenServer processes managing different aspects of the system.

### Supervision Structure

```
WandererNotifier.Supervisor
├── WandererNotifier.Core.License
├── WandererNotifier.License (proxy)
├── WandererNotifier.Core.Stats
├── WandererNotifier.Data.Cache.Repository
├── WandererNotifier.Service
├── WandererNotifier.Maintenance
├── WandererNotifier.Web.Server
└── WandererNotifier.CorpTools.ActivityChartScheduler (conditional)
```

## Module Organization

The application follows a carefully designed namespace hierarchy that separates functionality into logical domains:

### Core (`WandererNotifier.Core.*`)

Contains the fundamental building blocks of the application:

- **License**: Manages license validation and feature access control
- **Config**: Centralizes configuration management with sensible defaults
- **Features**: Controls feature flags and access based on license tier
- **Stats**: Tracks application statistics for monitoring

### Services (`WandererNotifier.Services.*`)

Implements the primary business logic:

- **Service**: Main service coordinating WebSocket connections and message handling
- **KillProcessor**: Processes kill notifications from zKillboard
- **SystemTracker**: Tracks EVE Online solar systems, particularly wormholes
- **CharTracker**: Tracks EVE Online characters
- **Maintenance**: Manages periodic maintenance tasks
- **TPSChartScheduler**: Schedules generation and sending of TPS charts

### API (`WandererNotifier.Api.*`)

Manages external API integrations:

- **Http.Client**: Generic HTTP client functionality
- **ZKill**: Integration with zKillboard's API and WebSocket
- **ESI**: Integration with EVE Online's Swagger Interface
- **Map**: Integration with the Wanderer map API

### Data (`WandererNotifier.Data.*`)

Defines data structures and storage:

- **Killmail**: Data structure for EVE Online killmails
- **System**: Data structure for EVE Online solar systems
- **Character**: Data structure for EVE Online characters
- **Cache.Repository**: Cache implementation using Cachex

### Notifiers (`WandererNotifier.Notifiers.*`)

Handles sending notifications to different channels:

- **Discord**: Discord notification formatting and sending
- **Slack**: Slack notification formatting and sending
- **Factory**: Factory for creating the appropriate notifier based on configuration
- **Behaviour**: Behaviour definition for notifier implementations

### Web (`WandererNotifier.Web.*`)

Provides web interface and API:

- **Server**: Phoenix web server
- **Controllers**: API controllers
- **Router**: Phoenix router

## Data Flow

1. **Kill Notification Flow**:
   - zKillboard WebSocket → ZKill.Websocket → Service → KillProcessor → Notifier → Discord/Slack

2. **System Tracking Flow**:
   - Map API → Api.Map.Client → SystemTracker → Cache.Repository → Notifier → Discord/Slack

3. **Character Tracking Flow**:
   - Map API → Api.Map.Client → CharTracker → Cache.Repository → Notifier → Discord/Slack

4. **TPS Chart Flow**:
   - TPSChartScheduler → CorpTools.Client → TPSChartAdapter → Notifier → Discord

5. **License Validation Flow**:
   - Application → License → LicenseManager.Client → License Manager API → Features

## Proxy Pattern Implementation

To facilitate gradual migration of code without breaking existing functionality, the application employs a proxy pattern:

1. Original modules (e.g., `WandererNotifier.License`) act as proxies that delegate to the new implementation (e.g., `WandererNotifier.Core.License`).
2. All existing code can continue to reference the original module names.
3. New code uses the new namespaced modules directly.
4. Once all code has been migrated, the proxy modules can be removed.

## Process Model

The application uses multiple GenServer processes to handle different responsibilities:

- **License**: Manages license validation and periodic refreshing
- **Stats**: Tracks application statistics
- **Cache.Repository**: Manages caching with periodic checks
- **Service**: Manages WebSocket connections and message routing
- **Maintenance**: Handles periodic maintenance tasks
- **TPSChartScheduler**: Schedules chart generation and distribution

## Error Handling

The application uses a "let it crash" philosophy with proper supervision:

1. **Supervision**: All critical processes are supervised for automatic restart
2. **Retries**: Network operations use retry with exponential backoff
3. **Logging**: Extensive logging for debugging and monitoring
4. **Graceful Degradation**: Features degrade gracefully when dependencies are unavailable

## Deployment Considerations

- **Environment Configuration**: The application supports different environments (development, production) with appropriate configuration
- **Containerization**: Designed to run well in containerized environments
- **License Management**: External license validation service requirement
- **Cache Persistence**: Cache data can be persisted to disk for continuity
- **API Tokens**: Requires various API tokens for external service access 