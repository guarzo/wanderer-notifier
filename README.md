# Wanderer Notifier

Wanderer Notifier is a sophisticated Elixir/OTP application that provides real-time EVE Online killmail monitoring and Discord notifications. It connects to ZKillboard's RedisQ API to track ship destructions in specific systems and sends rich, detailed notifications to Discord channels.

## Features

- **Real-Time Kill Monitoring:** Consumes live killmail data via ZKillboard's RedisQ API
- **Rich Discord Notifications:** Sends beautifully formatted embed notifications with ship thumbnails, character portraits, and kill details
- **Character & System Tracking:** Monitor specific characters and wormhole systems for targeted notifications
- **Multi-Channel Support:** Route different notification types (kills, character tracking, system updates) to separate Discord channels
- **License-Based Features:** Premium subscribers get rich embed notifications; free tier gets text-based alerts
- **Advanced Caching:** Multi-adapter caching system (Cachex/ETS) with intelligent TTL management
- **Data Enrichment:** Integrates with EVE's ESI API to fetch detailed character, corporation, and alliance information
- **Map Integration:** Connects to Wanderer map API for system and character tracking
- **Robust Architecture:** Built on Elixir's OTP supervision trees for fault tolerance and reliability
- **Production Ready:** Comprehensive logging, telemetry, Docker deployment, and health checks

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
   - `DISCORD_CHANNEL_ID`: Main Discord channel ID for notifications (required)
   - `DISCORD_SYSTEM_KILL_CHANNEL_ID`: Channel for system-based kill notifications (optional)
   - `DISCORD_CHARACTER_KILL_CHANNEL_ID`: Channel for character-based kill notifications (optional)
   - `DISCORD_SYSTEM_CHANNEL_ID`: Channel for system tracking notifications (optional)
   - `DISCORD_CHARACTER_CHANNEL_ID`: Channel for character tracking notifications (optional)

2. **Map API Configuration**
   - `MAP_URL`: Base URL for the Wanderer map API (required, e.g., "https://wanderer.ltd")
   - `MAP_NAME`: Name of your specific map (required)
   - `MAP_API_KEY`: Authentication token for map API access (required)

3. **License Configuration**
   - `LICENSE_KEY`: Your license key for accessing premium features (required)

4. **Feature Control Flags**
   - `NOTIFICATIONS_ENABLED`: Master switch for all notifications (default: true)
   - `KILLMAIL_NOTIFICATION_ENABLED`: Enable killmail notifications (default: true)
   - `SYSTEM_NOTIFICATION_ENABLED`: Enable system notifications (default: true)
   - `CHARACTER_NOTIFICATION_ENABLED`: Enable character notifications (default: true)
   - `DISABLE_STATUS_MESSAGES`: Disable startup and status notifications (default: false)

5. **Tracking Configuration**
   - `TRACK_KSPACE_ENABLED`: Include K-Space systems in tracking (default: true)
   - `SYSTEM_TRACKING_ENABLED`: Enable background system updates (default: true)
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

Wanderer Notifier follows a domain-driven, event-driven architecture built on Elixir/OTP principles:

### Core Data Flow
1. **RedisQ Consumer**: Polls ZKillboard's RedisQ API for new killmail events
2. **Killmail Pipeline**: Processes incoming kills through enrichment and filtering stages
3. **ESI Integration**: Enriches killmail data with character, corporation, and alliance details
4. **Notification Engine**: Determines eligibility and formats messages based on tracking rules
5. **Discord Delivery**: Sends rich embed or text notifications to configured channels

### Key Components
- **Supervision Tree**: Robust fault tolerance with supervisor hierarchies
- **Cache System**: Multi-adapter caching (Cachex/ETS) with unified key management
- **HTTP Client**: Centralized client with retry logic, rate limiting, and structured logging
- **Schedulers**: Background tasks for character/system updates and maintenance
- **License Service**: Controls premium features and notification formatting
- **Map Integration**: Tracks wormhole systems and character locations via external API

### Technology Stack
- **Elixir 1.18+** with OTP supervision trees
- **Nostrum** for Discord bot functionality
- **HTTPoison/Req** for HTTP API interactions
- **Cachex** for distributed caching
- **Jason** for JSON handling
- **WebSockex** for WebSocket connections
- **Docker** for containerized deployment

## License

This project is licensed according to the terms in the LICENSE file.

## Support

If you encounter issues or have questions, please open an issue on the project repository.