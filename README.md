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

All environment variables now use a standardized `WANDERER_` prefix. Legacy variable names are still supported with deprecation warnings, but will be removed in a future release.

### Key Configuration Options

1. **Discord Configuration**

   - `WANDERER_DISCORD_BOT_TOKEN`: Your Discord bot's authentication token
   - `WANDERER_DISCORD_CHANNEL_ID`: Main Discord channel ID for notifications
   - `WANDERER_DISCORD_KILL_CHANNEL_ID`: Channel for kill notifications
   - `WANDERER_DISCORD_SYSTEM_CHANNEL_ID`: Channel for system tracking notifications
   - `WANDERER_DISCORD_CHARACTER_CHANNEL_ID`: Channel for character tracking notifications
   - `WANDERER_DISCORD_CHARTS_CHANNEL_ID`: Channel for chart notifications

2. **License Configuration**

   - `WANDERER_LICENSE_KEY`: Your license key for accessing premium features
   - `WANDERER_LICENSE_MANAGER_URL`: URL for the license manager service (defaults to production service)

3. **Map API Configuration**

   - `WANDERER_MAP_URL`: URL of the map service
   - `WANDERER_MAP_TOKEN`: Authentication token for map API

4. **Database Configuration**

   - `WANDERER_DB_USERNAME`: Database username (default: postgres)
   - `WANDERER_DB_PASSWORD`: Database password (default: postgres)
   - `WANDERER_DB_HOSTNAME`: Database hostname (default: postgres)
   - `WANDERER_DB_NAME`: Database name (default: wanderer*notifier*[environment])
   - `WANDERER_DB_PORT`: Database port (default: 5432)
   - `WANDERER_DB_POOL_SIZE`: Connection pool size (default: 10)

5. **Web Server Configuration**

   - `WANDERER_WEB_PORT`: Port for the web server (default: 4000)
   - `WANDERER_WEB_HOST`: Host for the web server (default: localhost)
   - `WANDERER_PUBLIC_URL`: Public URL for the web interface

6. **WebSocket Configuration**

   - `WANDERER_WEBSOCKET_ENABLED`: Enable/disable websocket connection (default: true)
   - `WANDERER_WEBSOCKET_RECONNECT_DELAY`: Delay between reconnection attempts in ms (default: 5000)

7. **Feature Flags**

   - `WANDERER_FEATURE_KILL_NOTIFICATIONS`: Enable kill notifications (default: true)
   - `WANDERER_FEATURE_SYSTEM_NOTIFICATIONS`: Enable system notifications (default: true)
   - `WANDERER_FEATURE_CHARACTER_NOTIFICATIONS`: Enable character notifications (default: true)
   - `WANDERER_FEATURE_TRACK_KSPACE`: Track K-Space systems in addition to wormholes (default: false)
   - `WANDERER_FEATURE_KILL_CHARTS`: Enable kill charts (default: false)
   - `WANDERER_FEATURE_MAP_CHARTS`: Enable map charts (default: false)
   - `WANDERER_FEATURE_ACTIVITY_CHARTS`: Enable activity charts (default: false)
   - `WANDERER_DISABLE_STATUS_MESSAGES`: Disable startup and status notifications (default: false)

8. **Character Configuration**

   - `WANDERER_CHARACTER_EXCLUDE_LIST`: Comma-separated list of character IDs to exclude from tracking

9. **Debug Settings**
   - `WANDERER_DEBUG_LOGGING`: Enable debug logging (default: false)

### Legacy Variables Support

For backward compatibility, the following legacy variable names are still supported but will show deprecation warnings:

- `DISCORD_BOT_TOKEN` → use `WANDERER_DISCORD_BOT_TOKEN` instead
- `DISCORD_CHANNEL_ID` → use `WANDERER_DISCORD_CHANNEL_ID` instead
- `MAP_URL_WITH_NAME` → use `WANDERER_MAP_URL` instead
- `MAP_TOKEN` → use `WANDERER_MAP_TOKEN` instead
- `LICENSE_KEY` → use `WANDERER_LICENSE_KEY` instead
- `ENABLE_TRACK_KSPACE_SYSTEMS` → use `WANDERER_FEATURE_TRACK_KSPACE` instead

For a complete list of all available environment variables, see the [Environment Variables Documentation](docs/configuration/environment-variables.md).

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

For more details, see the [Architecture Documentation](docs/architecture/overview.md).

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- **Architecture**: [Overview](docs/architecture/overview.md), [Components](docs/architecture/components.md), and [Data Flow](docs/architecture/data-flow.md)
- **Features**: [System Notifications](docs/features/system-notifications.md), [Character Notifications](docs/features/character-notifications.md), [Kill Notifications](docs/features/kill-notifications.md)
- **Configuration**: [Environment Variables](docs/configuration/environment-variables.md) and [Feature Flags](docs/configuration/feature-flags.md)
- **Development**: [Code Style](docs/development/code-style.md) and [Error Handling](docs/development/error-handling.md)
- **Deployment**: [Docker Deployment](docs/deployment/docker-deployment.md)

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
