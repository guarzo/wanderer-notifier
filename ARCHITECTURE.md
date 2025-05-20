# Wanderer Notifier Architecture

## Overview

Wanderer Notifier is a notification service for EVE Online players, designed to monitor and alert players about game events. The application has been refactored to use a domain-driven design approach with clear module boundaries and responsibilities.

## Directory Structure

The codebase is organized by domain contexts:

```
lib/wanderer_notifier/
├── application.ex            # Application entry point
├── api/                      # HTTP interface
│   ├── pipeline.ex
│   └── controllers/          # API endpoints
├── cache/                    # Cache contracts & implementations
│   ├── behaviour.ex
│   ├── cachex.ex
│   └── key.ex                # Unified cache key generator
├── clients/                  # External API clients
│   ├── http/                 # HTTP client interface
│   └── esi/                  # EVE Swagger Interface client
├── config/                   # Runtime configs per context
│   ├── http.ex               # HTTP-related settings
│   ├── websocket.ex          # WebSocket connection settings
│   ├── notification.ex       # Notification delivery settings
│   ├── esi.ex                # ESI API connection settings
│   ├── license.ex            # License validation settings
│   └── utils.ex              # Common configuration utilities
├── common/                   # Shared helpers & types
│   ├── tracking_utils.ex
│   └── error_helpers.ex      # Error handling utilities
├── killmail/                 # Killmail business logic
├── mapping/                  # Map-related logic
├── license/                  # License business logic
├── notifications/            # Notification services
├── scheduling/               # Background jobs
└── logger/                   # Logging infrastructure
```

## Data Flows

### Killmail Pipeline

1. **Source**: ZKillboard WebSocket feed
2. **Processing**:
   - Killmail data is received via WebSocket
   - Processed by `WandererNotifier.Killmail.Processor`
   - Enriched with ESI data
   - Stored in cache
3. **Notification**:
   - Killmail is evaluated for notification by `WandererNotifier.Notifications.Determiner`
   - If criteria are met, notification is formatted and sent via appropriate channels

### Map Data Pipeline

1. **Source**: EVE Online map data via API
2. **Processing**:
   - System and character data is fetched from ESI
   - Data is transformed and stored in cache
3. **Usage**:
   - Used for determining relevance of killmails
   - Accessible via API endpoints for client applications

## Scheduler Mechanism

The application uses multiple schedulers to handle periodic tasks:

1. **Registry**: `WandererNotifier.Schedulers.Registry` discovers all scheduler modules
2. **Supervisor**: `WandererNotifier.Schedulers.Supervisor` manages scheduler lifecycle
3. **Execution**: Schedulers run at specified intervals or times using either:
   - Interval-based execution (e.g., every 5 minutes)
   - Time-based execution (e.g., at 12:00 daily)

Key schedulers include:
- `CharacterUpdateScheduler`: Updates tracked character data
- `SystemUpdateScheduler`: Updates tracked solar system data
- `ServiceStatusScheduler`: Generates periodic service status reports

## Configuration Sources

The application uses a layered configuration approach:

1. **Compile-time configuration**:
   - Defined in `config/config.exs`
   - Environment-specific overrides in `config/dev.exs`, `config/prod.exs`, etc.

2. **Runtime configuration**:
   - Environment variables used in `config/runtime.exs`
   - Prefix: `WANDERER_*` (e.g., `WANDERER_MAP_TOKEN`)
   - Feature flags: `WANDERER_FEATURE_*` (e.g., `WANDERER_FEATURE_TRACK_KSPACE`)

3. **Modular configuration access**:
   - Domain-specific config modules in `lib/wanderer_notifier/config/`
   - Each module handles a specific configuration domain (HTTP, WebSocket, etc.)
   - Common utilities in `WandererNotifier.Config.Utils`

## License Management

License validation is handled through:
1. License key retrieved from configuration
2. Periodic validation with license server
3. Feature enabling/disabling based on license status

## Notification System

The notification system supports multiple channels and formats:
1. **Discord**: Main notification channel via webhooks and bot API
2. **API**: Notification data accessible via REST API
3. **Feature Flags**: Fine-grained control of notification types and frequency 