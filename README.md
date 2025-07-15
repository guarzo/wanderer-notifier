# Wanderer Notifier

Wanderer Notifier is a sophisticated Elixir/OTP application that provides real-time EVE Online killmail monitoring and Discord notifications. It uses WebSocket connections for real-time killmail data and Server-Sent Events (SSE) for live map updates, tracking ship destructions in specific systems and sending rich, detailed notifications to Discord channels.

## Features

- **Real-Time Kill Monitoring:** Receives pre-enriched killmail data via WebSocket connection to WandererKills service
- **Live Map Synchronization:** Uses Server-Sent Events (SSE) for real-time system and character updates from the Wanderer map
- **Rich Discord Notifications:** Sends beautifully formatted embed notifications with ship thumbnails, character portraits, and kill details
- **Character & System Tracking:** Monitor specific characters and wormhole systems for targeted notifications with real-time updates
- **Multi-Channel Support:** Route different notification types (kills, character tracking, system updates) to separate Discord channels
- **Discord Slash Commands:** Full Discord bot integration with slash commands to manage priority systems and check bot status
- **Priority Systems:** Mark critical systems for special notifications with @here mentions, with priority-only mode support
- **License-Based Features:** Premium subscribers get rich embed notifications; free tier gets text-based alerts
- **Advanced Caching:** Multi-adapter caching system (Cachex/ETS) with intelligent TTL management and unified key generation
- **Data Enrichment:** Integrates with EVE's ESI API for additional enrichment when needed (most data comes pre-enriched)
- **Map Integration:** Real-time SSE connection to Wanderer map API for immediate system and character tracking updates
- **Event-Driven Architecture:** Built on real-time data streams with minimal polling for maximum responsiveness
- **Robust Supervision:** Built on Elixir's OTP supervision trees with granular fault tolerance and automatic recovery
- **Production Ready:** Comprehensive logging, telemetry, Docker deployment, health checks, and operational monitoring

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
- Kill notifications in priority systems include @here mentions
- Ensures critical systems get immediate attention
- Priority status persists between bot restarts
- Can be configured to only send notifications for priority systems using `PRIORITY_SYSTEMS_ONLY=true`

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

5. **Service URLs (Optional)**
   - `WEBSOCKET_URL`: WebSocket URL for killmail data (default: "ws://host.docker.internal:4004")
   - `WANDERER_KILLS_URL`: Base URL for WandererKills API (default: "http://host.docker.internal:4004")

6. **Additional Configuration**
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

Wanderer Notifier follows a domain-driven, event-driven architecture built on Elixir/OTP principles with real-time data streams:

### Real-Time Data Flow

1. **WebSocket Client**: Maintains persistent connection to WandererKills service for pre-enriched killmail data

2. **SSE Client**: Real-time Server-Sent Events connection for immediate map updates (systems and characters)

3. **Event Processing**: Handles SSE events through dedicated event handlers for real-time map synchronization

4. **Killmail Pipeline**: Processes incoming kills through supervised workers with filtering and notification stages

5. **ESI Integration**: Provides additional enrichment when needed (most data comes pre-enriched from WandererKills)

6. **Notification Engine**: Determines eligibility, applies license limits, and formats messages based on tracking rules

7. **Discord Infrastructure**: Full bot integration with slash command registration and event consumption

8. **Discord Delivery**: Sends rich embed or text notifications to configured channels with multi-channel routing

### Key Components

- **Supervision Tree**: Robust fault tolerance with granular supervisor hierarchies and automatic recovery

- **WebSocket Infrastructure**: Real-time killmail processing with connection management and supervised workers

- **SSE Infrastructure**: Complete Server-Sent Events system with connection management, parsing, and event handling

- **Discord Bot Services**: Full Discord integration with slash command registration, event consumption, and interaction handling

- **Cache System**: Multi-adapter caching (Cachex/ETS) with unified key management and intelligent TTL strategies

- **HTTP Client**: Centralized client with retry logic, rate limiting, structured logging, and response handling

- **Schedulers**: Background tasks with registry-based management for service monitoring and maintenance

- **License Service**: Controls premium features, notification formatting, and license-based limiting

- **Telemetry System**: Comprehensive application metrics, structured logging, and operational monitoring

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

## License

This project is licensed according to the terms in the LICENSE file.

## Support

If you encounter issues or have questions, please open an issue on the project repository.

## Notes

mix archive.install hex bunt