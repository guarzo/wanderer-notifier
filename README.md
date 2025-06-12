# Wanderer Notifier

Wanderer Notifier is an Elixir-based application that monitors EVE Online kill data and notifies designated Discord channels about significant events. It integrates with multiple external services to retrieve, enrich, and filter kill information before sending alerts.

## Features

- **Real-Time Monitoring:** Listens to live kill data via a WebSocket from ZKillboard
- **Data Enrichment:** Retrieves detailed killmail information from ESI
- **Map-Based Filtering:** Uses a custom map API to track wormhole systems and process kills originating from systems you care about
- **Character Tracking:** Monitors specific characters and notifies on their activities
- **Periodic Maintenance:** Automatically updates system data, processes backup kills, and sends heartbeat notifications
- **Caching:** Implements efficient caching with Cachex to minimize redundant API calls
- **Fault Tolerance:** Leverages Elixir's OTP and supervision trees for robust, resilient operation
- **Containerized Deployment:** Easy setup using Docker and docker-compose

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

- Elixir (>= 1.14 recommended)
- Erlang/OTP (compatible version)
- [Docker](https://www.docker.com/) (recommended for deployment)
- Discord Bot Token (with proper permissions)

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

   - `DISCORD_BOT_TOKEN`: Your Discord bot's authentication token
   - `DISCORD_CHANNEL_ID`: Main Discord channel ID for notifications
   - `DISCORD_SYSTEM_KILL_CHANNEL_ID`: Channel for system-based kill notifications
   - `DISCORD_CHARACTER_KILL_CHANNEL_ID`: Channel for character-based kill notifications
   - `DISCORD_SYSTEM_CHANNEL_ID`: Channel for system tracking notifications
   - `DISCORD_CHARACTER_CHANNEL_ID`: Channel for character tracking notifications

2. **License Configuration**

   - `LICENSE_KEY`: Your license key for accessing premium features

3. **Map API Configuration**

   - `MAP_URL`: Base URL for the wanderer map API
   - `MAP_NAME`: Name of your specific map
   - `MAP_API_KEY`: Authentication token for map API

   > **Note:** The application will automatically combine `MAP_URL` and `MAP_NAME` to create the full map URL with name parameter. For backward compatibility, you can still use `MAP_URL_WITH_NAME` with the full URL including the name parameter.

4. **Notifier API Configuration**

   - `NOTIFIER_API_TOKEN`: Authentication token for the notifier API

5. **Feature Flags**

   - `NOTIFICATIONS_ENABLED`: Enable all notifications (default: true)
   - `KILL_NOTIFICATIONS_ENABLED`: Enable kill notifications (default: true)
   - `SYSTEM_NOTIFICATIONS_ENABLED`: Enable system notifications (default: true)
   - `CHARACTER_NOTIFICATIONS_ENABLED`: Enable character notifications (default: true)
   - `DISABLE_STATUS_MESSAGES`: Disable startup and status notifications (default: false)
   - `TRACK_KSPACE_ENABLED`: Track K-Space systems in addition to wormholes (default: true)
   - `SYSTEM_TRACKING_ENABLED`: Enable system data tracking scheduler (default: true)
   - `CHARACTER_TRACKING_ENABLED`: Enable character data tracking scheduler (default: true)

6. **Character Configuration**

   - `CHARACTER_EXCLUDE_LIST`: Comma-separated list of character IDs to exclude from tracking

7. **Cache and RedisQ Configuration**

   - `CACHE_DIR`: Directory for cache files (default: /app/data/cache)
   - `REDISQ_URL`: ZKillboard RedisQ URL (default: [https://zkillredisq.stream/listen.php](https://zkillredisq.stream/listen.php))
   - `REDISQ_POLL_INTERVAL_MS`: RedisQ polling interval in milliseconds (default: 1000)

8. **License Manager Configuration**

   - `LICENSE_MANAGER_URL`: License manager API URL (default: [https://lm.wanderer.ltd](https://lm.wanderer.ltd))

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

Wanderer Notifier follows an event-driven, functional, and component-based architecture:

- The application receives real-time data via WebSocket from ZKillboard
- Data is enriched with information from EVE ESI API
- Notifications are determined based on configured rules
- Messages are formatted and sent to Discord channels

## License

This project is licensed according to the terms in the LICENSE file.

## Support

If you encounter issues or have questions, please open an issue on the project repository.

## Notes

```


 docker buildx build . \
  --build-arg API_TOKEN=your_token_here \
  --build-arg APP_VERSION=local \
  -t notifier:local

  docker run \
    --publish=7474:7474 --publish=7687:7687 \
    --volume=$HOME/neo4j/data:/data \
    --volume=$HOME/neo4j/logs:/logs \
    neo4j:latest
```
