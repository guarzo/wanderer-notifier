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

The application follows a domain-driven design with these core components:

### Data Flow
1. **WebSocket Client** (`lib/wanderer_notifier/killmail/websocket_client.ex`) - Connects to external WandererKills service for real-time pre-enriched killmail data
2. **SSE Client** (`lib/wanderer_notifier/map/sse_client.ex`) - Real-time connection to map API for system and character updates
3. **Killmail Pipeline** (`lib/wanderer_notifier/killmail/pipeline.ex`) - Processes both pre-enriched WebSocket killmails and legacy ZKillboard data
4. **ESI Service** (`lib/wanderer_notifier/esi/`) - Provides legacy enrichment for ZKillboard data (bypassed for WebSocket killmails)
5. **Map Integration** (`lib/wanderer_notifier/map/`) - Tracks wormhole systems and character locations via SSE real-time events
6. **Notification System** (`lib/wanderer_notifier/notifications/`) - Determines notification eligibility and formats messages
7. **Discord Notifier** (`lib/wanderer_notifier/notifiers/discord/`) - Sends formatted notifications to Discord channels

### Key Services
- **WebSocket Client**: Real-time connection to WandererKills service for pre-enriched killmail data
- **SSE Client**: Real-time Server-Sent Events connection to map API for system/character updates
- **WandererKills HTTP Client** (`lib/wanderer_notifier/killmail/wanderer_kills_client.ex`): REST API client for recent kills lookup
- **Cache Layer**: Uses Cachex to minimize API calls with configurable TTLs  
- **Schedulers** (`lib/wanderer_notifier/schedulers/`): Background tasks for periodic updates
- **License Service**: Controls feature availability (premium embeds vs free text notifications)
- **HTTP Client**: Centralized HTTP client with retry logic and rate limiting

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

## Important Patterns

### Error Handling
- Functions return `{:ok, result}` or `{:error, reason}` tuples
- Use pattern matching for control flow
- Errors are logged via centralized Logger module

### HTTP Client Usage
All HTTP requests go through the centralized `WandererNotifier.Http` module which provides:
- Automatic retries with exponential backoff
- Rate limiting
- Consistent error handling
- Request/response logging

### Caching Strategy
- Character/corporation/alliance data: 24-hour TTL
- System information: 1-hour TTL
- Notification deduplication: 30-minute window
- Use `WandererNotifier.Cache` module for all cache operations

### Feature Flags

Features can be toggled via environment variables ending in `_ENABLED`:

- `NOTIFICATIONS_ENABLED` - Master toggle for all notifications (default: true)
- `KILL_NOTIFICATIONS_ENABLED` - Enable/disable kill notifications (default: true)
- `SYSTEM_NOTIFICATIONS_ENABLED` - Enable/disable system notifications (default: true)
- `CHARACTER_NOTIFICATIONS_ENABLED` - Enable/disable character notifications (default: true)
- `ENABLE_STATUS_MESSAGES` - Enable/disable startup status messages (default: false)
- `TRACK_KSPACE_ENABLED` - Enable/disable K-Space system tracking (default: true)
- `PRIORITY_SYSTEMS_ONLY` - Only send notifications for priority systems (default: false)