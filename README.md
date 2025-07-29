# Wanderer Notifier

Wanderer Notifier is a sophisticated Elixir/OTP application that provides real-time EVE Online killmail monitoring and Discord notifications. It uses WebSocket connections for real-time killmail data and Server-Sent Events (SSE) for live map updates, tracking ship destructions in specific systems and sending rich, detailed notifications to Discord channels.

## Features

- **Real-Time Kill Monitoring:** Receives pre-enriched killmail data via WebSocket connection to WandererKills service
- **Live Map Synchronization:** Uses Server-Sent Events (SSE) for real-time system and character updates from the Wanderer map
- **Rich Discord Notifications:** Sends beautifully formatted embed notifications with ship thumbnails, character portraits, and kill details
- **Character & System Tracking:** Monitor specific characters and wormhole systems for targeted notifications with real-time updates
- **Multi-Channel Support:** Route different notification types (kills, character tracking, system updates) to separate Discord channels
- **Discord Slash Commands:** Full Discord bot integration with slash commands to manage priority systems and check bot status
- **Priority Systems:** Mark critical systems for special notifications with targeted mentions, with priority-only mode support
- **Voice Participant Notifications:** Target only active voice channel users instead of @here mentions for better notification targeting
- **License-Based Features:** Premium subscribers get rich embed notifications; free tier gets text-based alerts
- **Simplified Cache System:** Direct Cachex integration with domain-specific helpers and consistent key generation
- **Data Enrichment:** Integrates with EVE's ESI API for additional enrichment when needed (most data comes pre-enriched)
- **Map Integration:** Real-time SSE connection to Wanderer map API for immediate system and character tracking updates
- **Event-Driven Architecture:** Built on real-time data streams with minimal polling for maximum responsiveness
- **Robust Supervision:** Built on Elixir's OTP supervision trees with granular fault tolerance and automatic recovery
- **Production Ready:** Comprehensive logging, telemetry, Docker deployment, health checks, and operational monitoring
- **Comprehensive Testing:** Extensive test suite with 150+ tests covering core functionality, mocking, and integration scenarios

## Notification System

The application provides several types of Discord notifications:

1. **Kill Notifications**

   - Real-time alerts for ship destructions in tracked systems
   - Rich embed format with detailed information:
     - System location and kill value
     - Victim details (character, corporation, ship type)
     - Final blow attacker information
     - Top damage dealer (if different)
   - Visual elements including ship thumbnails and corporation icons
   - Direct links to zKillboard

2. **System Notifications**

   - Alerts when new systems are added to tracking
   - System identification and zKillboard links
   - Distinctive orange color scheme for easy identification

3. **Character Notifications**

   - Notifications for newly tracked characters
   - Character portraits and corporation affiliations
   - Links to character profiles
   - Green color scheme for visual distinction

4. **Service Status Updates**
   - System startup confirmations
   - Connection status monitoring
   - Error reporting and diagnostic information

## Kill Notifications

The notifier supports configurable kill notifications based on tracked systems and tracked characters. Notifications can be sent to separate channels:

- **System kill notifications**: Sent to `DISCORD_SYSTEM_KILL_CHANNEL_ID` when a kill happens in a tracked system
- **Character kill notifications**: Sent to `DISCORD_CHARACTER_KILL_CHANNEL_ID` when tracked characters are involved in a kill
  - Green color: When tracked characters are attackers (successful kills)
  - Red color: When tracked characters are victims (losses)

If a kill involves both tracked systems and tracked characters, notifications will be sent to both channels. This allows for more targeted monitoring of activity.

## Discord Slash Commands

The notifier supports Discord slash commands for managing your notification preferences directly from Discord:

### Available Commands

- **`/notifier status`** - Shows the current bot status including:
  - Number of priority systems configured
  - Priority-only mode status
  - Total commands executed and unique users
  - Feature status (system, character, and kill notifications)
  - Tracking status for systems and characters

- **`/notifier system <system_name> [action]`** - Manage system tracking and priority:
  - `add-priority`: Add a system to your priority list for @here mentions
  - `remove-priority`: Remove a system from the priority list
  - `track`: Start tracking a system (coming soon)
  - `untrack`: Stop tracking a system (coming soon)

### Priority Systems

Priority systems receive special treatment in notifications:
- System notifications in priority systems include targeted mentions (@here or voice participants)
- Ensures critical systems get immediate attention
- Priority status persists between bot restarts
- Can be configured to only send notifications for priority systems using `PRIORITY_SYSTEMS_ONLY=true`

### Voice Participant Notifications

For more targeted notifications, the system can now notify only users actively in Discord voice channels:

- **Smart Targeting**: Only mentions users currently in voice channels (excludes AFK channel)
- **Fallback Support**: Optionally falls back to @here if no voice participants are found
- **Priority Integration**: Works seamlessly with priority systems for enhanced notifications
- **Configurable**: Disabled by default, requires Discord Guild ID to enable

## Requirements

- Elixir (>= 1.18 required)
- Erlang/OTP (compatible version)
- [Docker](https://www.docker.com/) (recommended for deployment)
- Discord Bot Token (with proper permissions)
- Wanderer map access and API token
- Valid license key for premium features

## Quick Start with Docker

The simplest way to get started is using Docker and docker-compose:

1. **Clone the repository:**

   ```bash
   git clone https://github.com/yourusername/wanderer-notifier.git
   cd wanderer-notifier
   ```

2. **Configure environment:**

   ```bash
   cp .env.example .env
   ```

   Edit `.env` file with your Discord bot token and other configuration.

3. **Start the application:**

   ```bash
   docker-compose up -d
   ```

4. **Check logs:**
   ```bash
   docker-compose logs -f
   ```

## Manual Installation

If you prefer to run without Docker:

1. **Clone the repository:**

   ```bash
   git clone https://github.com/yourusername/wanderer-notifier.git
   cd wanderer-notifier
   ```

2. **Setup Environment Variables:**
   Create a `.env` file using the provided `.env.example` as a template.

3. **Install Dependencies:**

   ```bash
   mix deps.get
   ```

4. **Compile the Project:**

   ```bash
   mix compile
   ```

5. **Run the Application:**
   ```bash
   mix run --no-halt
   ```

## Configuration

All configuration is managed through environment variables in the `.env` file. A template is provided as `.env.example`.

### Configuration Validation

On startup, the application validates all configuration settings. If there are issues with your configuration, detailed error messages will be displayed in the logs to help you resolve them.

### Simplified Environment Variables

Environment variables now use simplified naming without redundant prefixes for cleaner configuration.

### Key Configuration Options

1. **Discord Configuration**
   - `DISCORD_BOT_TOKEN`: Your Discord bot's authentication token (required)
   - `DISCORD_APPLICATION_ID`: Discord application ID for slash commands (optional)
   - `DISCORD_CHANNEL_ID`: Main Discord channel ID for notifications (required)
   - `DISCORD_SYSTEM_KILL_CHANNEL_ID`: Channel for system-based kill notifications (optional)
   - `DISCORD_CHARACTER_KILL_CHANNEL_ID`: Channel for character-based kill notifications (optional)
   - `DISCORD_SYSTEM_CHANNEL_ID`: Channel for system tracking notifications (optional)
   - `DISCORD_CHARACTER_CHANNEL_ID`: Channel for character tracking notifications (optional)

2. **Map API Configuration**
   - `MAP_URL`: Base URL for the Wanderer map API (required, e.g., "https://wanderer.ltd")
   - `MAP_NAME`: Slug of your specific map (required)
   - `MAP_API_KEY`: Authentication token for map API access (required)

3. **License Configuration**
   - `LICENSE_KEY`: Your license key for accessing premium features (required)

4. **Feature Control Flags**
   - `NOTIFICATIONS_ENABLED`: Master switch for all notifications (default: true)
   - `KILL_NOTIFICATIONS_ENABLED`: Enable killmail notifications (default: true)
   - `SYSTEM_NOTIFICATIONS_ENABLED`: Enable system notifications (default: true)
   - `CHARACTER_NOTIFICATIONS_ENABLED`: Enable character notifications (default: true)
   - `ENABLE_STATUS_MESSAGES`: Enable startup and status notifications (default: false)
   - `PRIORITY_SYSTEMS_ONLY`: Only send notifications for priority systems (default: false)

5. **Voice Participant Notifications**
   - `DISCORD_GUILD_ID`: Discord server/guild ID for voice participant queries (required for voice notifications)
   - `VOICE_PARTICIPANT_NOTIFICATIONS_ENABLED`: Target only active voice channel users (default: false)
   - `FALLBACK_TO_HERE_ENABLED`: Fallback to @here if no voice participants found (default: true)

6. **Service URLs (Optional)**
   - `WEBSOCKET_URL`: WebSocket URL for killmail data (default: "ws://host.docker.internal:4004")
   - `WANDERER_KILLS_URL`: Base URL for WandererKills API (default: "http://host.docker.internal:4004")

7. **Additional Configuration**
   - `CHARACTER_EXCLUDE_LIST`: Comma-separated character IDs to exclude from tracking

## Development

### Using the Dev Container

This project includes a development container configuration for VS Code:

1. Install the [Remote - Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Open the repository in VS Code
3. When prompted, reopen the project in the container

### Makefile Commands

The Makefile provides shortcuts for common tasks:

- **Compile:** `make compile`
- **Clean:** `make clean`
- **Test:** `make test`
- **Format:** `make format`
- **Interactive Shell:** `make shell`
- **Run Application:** `make run`
- **Get Dependencies:** `make deps.get`
- **Update Dependencies:** `make deps.update`

## Architecture

Wanderer Notifier follows a mature, domain-driven architecture built on Elixir/OTP principles with real-time data streams. The codebase has been extensively refactored into a production-ready architecture with consolidated services and unified infrastructure.

### Core Architecture Principles

- **Domain-Driven Design**: Clear separation between business domains (killmail, notifications, tracking, license)
- **Unified Infrastructure**: Single HTTP client and cache module with service-specific configurations
- **Application Service Consolidation**: Centralized service handling dependency injection, metrics, and coordination
- **Context Layer**: Cross-domain coordination for API, notification, and processing concerns
- **Event-Driven Architecture**: Event sourcing capabilities with extensible handlers and processing pipeline
- **Real-Time Processing**: Advanced WebSocket and SSE connections with health monitoring
- **Multi-Phase Initialization**: Sophisticated startup process with infrastructure, foundation, integration, and processing phases

### Real-Time Data Flow

1. **Application Service** (`lib/wanderer_notifier/application/services/application_service/`): Consolidated service coordinating all application operations with dependency injection and metrics tracking

2. **Service Initializer** (`lib/wanderer_notifier/application/initialization/service_initializer.ex`): Multi-phase startup process ensuring reliable system initialization

3. **WebSocket Client** (`lib/wanderer_notifier/domains/killmail/websocket_client.ex`): Maintains persistent connection to WandererKills service for pre-enriched killmail data

4. **SSE Client** (`lib/wanderer_notifier/map/sse_client.ex`): Real-time Server-Sent Events connection with advanced connection monitoring and health tracking

5. **Processing Context** (`lib/wanderer_notifier/contexts/processing_context/`): Coordinates killmail processing across domains

6. **Event Sourcing** (`lib/wanderer_notifier/event_sourcing/`): Event-driven architecture with extensible handlers for future capabilities

7. **Notification Context** (`lib/wanderer_notifier/contexts/notification_context/`): Coordinates notification processing across domains

8. **Discord Integration** (`lib/wanderer_notifier/domains/notifications/discord/`): Discord bot integration with slash commands and rich notifications

### Module Organization

The refactored codebase follows a mature, layered architecture:

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
│   │   ├── services/                 # Processing services
│   │   ├── pipeline/                 # Processing pipeline
│   │   └── utils/                    # Domain utilities
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
├── infrastructure/                   # Technical infrastructure
│   ├── http.ex                       # Unified HTTP client
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

### Key Infrastructure Components (Post-Consolidation)

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

- **Supervision Tree**: Robust fault tolerance with granular supervisor hierarchies and automatic recovery

### Technology Stack

- **Elixir 1.18+** with OTP supervision trees for fault tolerance

- **Nostrum** for Discord bot functionality and slash commands

- **HTTPoison/Req** for HTTP API interactions with retry logic

- **Cachex/ETS** for multi-adapter caching with TTL management

- **Jason** for high-performance JSON encoding/decoding

- **WebSockex** for persistent WebSocket connections

- **Server-Sent Events** for real-time map synchronization

- **Mox** for behavior-based testing and mocking

- **Docker** for containerized deployment and development

## Development & Testing

### Recent Architectural Improvements

The codebase has undergone extensive refactoring and modernization, evolving into a mature production-ready architecture:

#### Application Service Consolidation (Sprint 4+)
- **Application Service**: Consolidated all application-level concerns into a single `ApplicationService` with specialized sub-modules for dependency injection, metrics, and notification coordination
- **Multi-Phase Initialization**: Sophisticated startup process with infrastructure → foundation → integration → processing phases
- **Context Layer**: Added cross-domain coordination layer for API, notification, and processing concerns
- **Event Sourcing**: Implemented event-driven architecture foundation with extensible handlers and processing pipeline

#### Infrastructure Unification
- **HTTP Client**: Single module with service-specific configurations for ESI, WandererKills, License, Map, and Streaming services
- **Cache System**: Consolidated from multiple modules to single unified cache with domain-specific helpers
- **Real-Time Integration**: Advanced SSE client with connection monitoring and health tracking for map integration
- **Configuration Management**: Comprehensive system with validation, feature flags, and environment-based configuration

#### Code Quality & Testing Improvements
- **Comprehensive Test Coverage**: Expanded to 150+ tests covering all architectural layers and integration scenarios
- **Test Failure Reduction**: Systematically reduced test failures from 185 → 10 (94.6% improvement)
- **Production Readiness**: Enhanced error handling, logging, telemetry, and operational monitoring
- **Mock Standardization**: Unified test mocking approach with consistent behavior-based testing

#### Testing Commands

Run the full test suite:
```bash
mix test
```

Run tests with coverage:
```bash
mix test --cover
```

Run specific test categories:
```bash
mix test.killmail    # Killmail-related tests
mix test.all         # All tests with trace output
```

Run tests in watch mode:
```bash
mix test.watch
```

#### Code Quality Tools

Format code:
```bash
mix format
```

Build and compile:
```bash
make compile         # Standard compilation
make compile.strict  # Warnings as errors
```

Clean and restart:
```bash
make s              # Clean, compile, and start shell
```

## License

This project is licensed according to the terms in the LICENSE file.

## Support

If you encounter issues or have questions, please open an issue on the project repository.

## Notes

mix archive.install hex bunt