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

- **System kill notifications**: Sent to `WANDERER_DISCORD_SYSTEM_KILL_CHANNEL_ID` when a kill happens in a tracked system
- **Character kill notifications**: Sent to `WANDERER_DISCORD_CHARACTER_KILL_CHANNEL_ID` when tracked characters are involved in a kill
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

### Standardized Environment Variables

All environment variables now use a standardized `WANDERER_` prefix.

### Key Configuration Options

1. **Discord Configuration**

   - `WANDERER_DISCORD_BOT_TOKEN`: Your Discord bot's authentication token
   - `WANDERER_DISCORD_CHANNEL_ID`: Main Discord channel ID for notifications
   - `WANDERER_DISCORD_KILL_CHANNEL_ID`: Channel for kill notifications
   - `WANDERER_DISCORD_SYSTEM_KILL_CHANNEL_ID`: Channel for system-based kill notifications
   - `WANDERER_DISCORD_CHARACTER_KILL_CHANNEL_ID`: Channel for character-based kill notifications
   - `WANDERER_DISCORD_SYSTEM_CHANNEL_ID`: Channel for system tracking notifications
   - `WANDERER_DISCORD_CHARACTER_CHANNEL_ID`: Channel for character tracking notifications

2. **License Configuration**

   - `WANDERER_LICENSE_KEY`: Your license key for accessing premium features
   - `WANDERER_LICENSE_MANAGER_URL`: URL for the license manager service

3. **Map API Configuration**

   - `WANDERER_MAP_URL`: URL for the wanderer map
   - `WANDERER_MAP_TOKEN`: Authentication token for map API
   - `WANDERER_NOTIFIER_API_TOKEN`: API token for the notifier

4. **Web Server Configuration**

   - `PORT`: Port for the web server (default: 4000)
   - `WANDERER_HOST`: Host for the web server (default: localhost)
   - `WANDERER_SCHEME`: HTTP scheme to use (default: http)
   - `WANDERER_PUBLIC_URL`: Public URL for the web interface

5. **WebSocket Configuration**

   - `WANDERER_WEBSOCKET_RECONNECT_DELAY`: Delay between reconnection attempts in ms (default: 5000)
   - `WANDERER_WEBSOCKET_MAX_RECONNECTS`: Maximum number of reconnection attempts (default: 20)
   - `WANDERER_WEBSOCKET_RECONNECT_WINDOW`: Window for reconnection attempts in seconds (default: 3600)

6. **Feature Flags**

   - `WANDERER_NOTIFICATIONS_ENABLED`: Enable all notifications (default: true)
   - `WANDERER_KILL_NOTIFICATIONS_ENABLED`: Enable kill notifications (default: true)
   - `WANDERER_SYSTEM_NOTIFICATIONS_ENABLED`: Enable system notifications (default: true)
   - `WANDERER_CHARACTER_NOTIFICATIONS_ENABLED`: Enable character notifications (default: true)
   - `WANDERER_CHARACTER_TRACKING_ENABLED`: Enable character tracking (default: true)
   - `WANDERER_SYSTEM_TRACKING_ENABLED`: Enable system tracking (default: true)
   - `WANDERER_DISABLE_STATUS_MESSAGES`: Disable startup and status notifications (default: false)
   - `WANDERER_TRACK_KSPACE_ENABLED`: Track K-Space systems in addition to wormholes (default: true)

7. **Character Configuration**

   - `WANDERER_CHARACTER_EXCLUDE_LIST`: Comma-separated list of character IDs to exclude from tracking

8. **Caching Configuration**

   - `WANDERER_CACHE_DIR`: Directory for caching data (default: /app/data/cache)

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
 mix archive.install hex bunt

 docker buildx build . \
  --build-arg WANDERER_NOTIFIER_API_TOKEN=your_token_here \
  --build-arg APP_VERSION=local \
  -t notifier:local

  docker run \
    --publish=7474:7474 --publish=7687:7687 \
    --volume=$HOME/neo4j/data:/data \
    --volume=$HOME/neo4j/logs:/logs \
    neo4j:latest
```
