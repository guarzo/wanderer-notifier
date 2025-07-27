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

Wanderer Notifier follows a clean, domain-driven architecture built on Elixir/OTP principles with real-time data streams. The codebase has been refactored for better modularity, testability, and maintainability.

### Core Architecture Principles

- **Domain-Driven Design**: Clear separation between business domains (killmail, notifications, map tracking)
- **Unified Infrastructure**: Consolidated HTTP clients, cache systems, and shared utilities
- **Real-Time Processing**: Event-driven architecture with WebSocket and SSE connections
- **Robust Error Handling**: Comprehensive error handling and retry mechanisms
- **Testable Design**: Behavior-based testing with comprehensive mock support

### Real-Time Data Flow

1. **WebSocket Client** (`lib/wanderer_notifier/domains/killmail/websocket_client.ex`): Maintains persistent connection to WandererKills service for pre-enriched killmail data with automatic fallback handling

2. **Fallback Handler** (`lib/wanderer_notifier/domains/killmail/fallback_handler.ex`): Automatically switches to HTTP API when WebSocket connection fails, ensuring continuity

3. **SSE Client** (`lib/wanderer_notifier/map/sse_client.ex`): Real-time Server-Sent Events connection for immediate map updates (systems and characters)

4. **Killmail Pipeline** (`lib/wanderer_notifier/domains/killmail/pipeline.ex`): Processes incoming kills through supervised workers with filtering and notification stages

5. **ESI Integration** (`lib/wanderer_notifier/infrastructure/adapters/`): Provides additional enrichment when needed using unified HTTP client

6. **Notification Engine** (`lib/wanderer_notifier/domains/notifications/`): Determines eligibility, applies license limits, and formats messages based on tracking rules

7. **Discord Infrastructure** (`lib/wanderer_notifier/domains/notifications/notifiers/discord/`): Full bot integration with slash command registration and event consumption

8. **Discord Delivery**: Sends rich embed or text notifications to configured channels with multi-channel routing

### Module Organization

The refactored codebase follows a clear module hierarchy:

```
lib/wanderer_notifier/
├── domains/                          # Business logic domains
│   ├── killmail/                     # Killmail processing domain
│   │   ├── websocket_client.ex       # Real-time data ingestion
│   │   ├── fallback_handler.ex       # HTTP fallback mechanism  
│   │   ├── pipeline.ex               # Kill processing pipeline
│   │   ├── killmail.ex               # Flattened killmail struct (195 lines)
│   │   └── wanderer_kills_api.ex     # WandererKills API client
│   ├── tracking/                     # Unified tracking domain
│   │   ├── clients/
│   │   │   └── unified_client.ex     # Single client for characters + systems
│   │   ├── handlers/
│   │   │   ├── shared_event_logic.ex # Common event processing patterns
│   │   │   ├── character_handler.ex  # Character-specific event handling
│   │   │   └── system_handler.ex     # System-specific event handling
│   │   └── entities/
│   │       ├── character.ex          # Character entity with Access behavior
│   │       └── system.ex             # System entity with validation
│   ├── notifications/                # Notification handling domain
│   │   ├── notifiers/discord/        # Discord-specific notifiers
│   │   ├── formatters/
│   │   │   ├── unified.ex            # Single formatter for all types
│   │   │   └── utilities.ex          # Shared formatting utilities
│   │   └── determiners/              # Notification logic
│   └── license/                      # License management domain
├── infrastructure/                   # Shared infrastructure
│   ├── adapters/                     # External service adapters (ESI)
│   ├── cache/                        # Simplified caching system (3 modules)
│   │   ├── cache.ex                  # Direct Cachex wrapper
│   │   ├── config_simple.ex          # Simple TTL configuration
│   │   └── keys_simple.ex            # Consistent key generation
│   ├── http/
│   │   └── http.ex                   # Single HTTP client with request/5
│   └── messaging/                    # Event handling infrastructure
├── map/                              # Map tracking via SSE
│   ├── sse_client.ex                 # SSE connection management
│   ├── sse_parser.ex                 # Event parsing and handling
│   └── tracking_behaviours.ex        # Tracking behavior contracts
├── schedulers/                       # Background task scheduling
├── shared/                           # Shared utilities and services
│   ├── config/                       # Configuration management
│   ├── logger/                       # Simplified logging system  
│   └── utils/                        # Common utilities
└── contexts/                         # Application context layer
```

### Key Infrastructure Components (Simplified in Sprint 2)

- **Unified HTTP Client** (`lib/wanderer_notifier/infrastructure/http/http.ex`): Single module handling all external HTTP requests with:
  - Service-specific configurations (ESI, WandererKills, License, Map, Streaming)
  - Built-in authentication (Bearer, API Key, Basic)
  - Middleware pipeline (Telemetry, RateLimiter, Retry, CircuitBreaker)
  - Automatic JSON encoding/decoding

- **Simplified Cache System**: Reduced from 15 modules to 3 core modules:
  - `Cache.ex`: Direct Cachex wrapper for all cache operations
  - `ConfigSimple.ex`: Simple TTL configuration (24h for entities, 1h for systems, 30m for killmails)
  - `KeysSimple.ex`: Consistent key generation (e.g., "esi:character:123")

- **Unified Tracking Client** (`lib/wanderer_notifier/domains/tracking/clients/unified_client.ex`): Single client handling both characters and systems with:
  - Process dictionary for entity context switching
  - Shared caching and HTTP request logic
  - Entity-specific batch processing and validation

- **Flattened Data Structures**: Simplified from complex nested schemas to direct field access:
  - `Killmail` struct: 195 lines (reduced from 338) with flattened victim fields
  - String-based keys throughout with normalization at entry points
  - Removed 1,454 lines of unused Ecto schemas

- **Configuration Management** (`lib/wanderer_notifier/shared/config/`): Map-based configuration with validation and feature flags

- **Shared Event Logic** (`lib/wanderer_notifier/domains/tracking/handlers/shared_event_logic.ex`): Common event processing patterns reducing code duplication across tracking domains

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

### Recent Improvements (Sprint 2)

The codebase has undergone significant architectural refactoring and modernization:

#### Unified Architecture (Sprint 2)
- **Unified Tracking Client**: Merged character and system clients into a single, configurable client with entity context switching
- **Simplified HTTP Infrastructure**: Consolidated from multiple HTTP modules to a single `request/5` interface with service-specific configurations
- **Flattened Data Structures**: Simplified Killmail schema from nested Access behavior to direct field access, reducing from 338 to 195 lines
- **Standardized Data Processing**: Eliminated dual string/atom key support, normalizing all data to string keys at entry points
- **Consolidated Notification Formatters**: Unified all notification types into two main modules with shared utilities

#### Infrastructure Simplification
- **HTTP Client Unification**: Single service with predefined configurations for ESI, WandererKills, License, Map, and Streaming services
- **Data Format Standardization**: Consistent string-based data handling throughout the pipeline with normalization at boundaries
- **Schema Reorganization**: Removed 1,454 lines of unused Ecto schemas and flattened remaining structures
- **Event Handler Consolidation**: Shared event processing logic reducing code duplication across tracking domains

#### Code Quality & Testing Improvements
- **Comprehensive Test Coverage**: Expanded to 150+ tests covering unified architecture, tracking domains, and formatters
- **Test Failure Reduction**: Systematically reduced test failures from 185 → 10 (94.6% improvement)
- **Simplified Cache System**: Streamlined from 15 modules to 3 core modules with direct Cachex access
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