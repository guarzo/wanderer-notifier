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

### Key Configuration Options

1. **Required Core Configuration**

   - `DISCORD_BOT_TOKEN`: Your Discord bot's authentication token
   - `DISCORD_CHANNEL_ID`: Main Discord channel ID for notifications
   - `LICENSE_KEY`: Your license key for accessing premium features

2. **Map Configuration**

   - `MAP_URL`: URL of the map service
   - `MAP_NAME`: Map identifier for system tracking
   - `MAP_TOKEN`: Authentication token for map API

3. **Feature Enablement**

   - `ENABLE_NOTIFICATIONS`: Master switch for all notifications (default: `true`)
   - `ENABLE_KILL_NOTIFICATIONS`: Enable kill notifications (default: `true`)
   - `ENABLE_SYSTEM_NOTIFICATIONS`: Enable system tracking (default: `true`)
   - `ENABLE_CHARACTER_NOTIFICATIONS`: Enable character tracking (default: `true`)
   - `ENABLE_MAP_CHARTS`: Enable map/activity charts (default: `false`)
   - `ENABLE_CHARTS`: General charts functionality (default: `false`)
   - `TRACK_ALL_SYSTEMS`: Track all systems instead of specific ones (default: `false`)

4. **Feature-specific Discord Channels**
   - `DISCORD_KILL_CHANNEL_ID`: Channel for kill notifications
   - `DISCORD_SYSTEM_CHANNEL_ID`: Channel for system tracking notifications
   - `DISCORD_CHARACTER_CHANNEL_ID`: Channel for character tracking notifications
   - `DISCORD_CHARTS_CHANNEL_ID`: Channel for chart notifications

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
 ```