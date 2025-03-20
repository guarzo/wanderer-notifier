# Wanderer Notifier

Wanderer Notifier is an Elixir-based application that monitors EVE Online kill data and notifies designated Discord channels about significant events. It integrates with multiple external services to retrieve, enrich, and filter kill information before sending alerts.

## Features

- **Real-Time Monitoring:** Listens to live kill data via a WebSocket from ZKillboard.
- **Data Enrichment:** Retrieves detailed killmail information from ESI.
- **Map-Based Filtering:** Uses a custom map API to track wormhole systems and process only those kills originating from systems you care about.
- **Periodic Maintenance:** Automatically updates system data, processes backup kills, and sends heartbeat notifications to Discord.
- **Caching:** Implements caching with Cachex to minimize redundant API calls.
- **Fault Tolerance:** Leverages Elixir's OTP and supervision trees to ensure a robust and resilient system.

### Notification System

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

## Notification Types and Triggers

The application sends several types of notifications to Discord:

1. **Kill Notifications**
   - **Trigger**: When a ship is destroyed in a tracked system or involves a tracked character
   - **Frequency**: Real-time as events occur
   - **Content**: Detailed information about the kill, including victim, attacker, ship types, and ISK value

2. **System Notifications**
   - **Trigger**: When a new system is added to the tracking list via the map API
   - **Frequency**: Real-time when systems are added
   - **Content**: System name, ID, and link to zKillboard

3. **Character Notifications**
   - **Trigger**: When a new character is added to the tracking list
   - **Frequency**: Real-time when characters are added
   - **Content**: Character name, corporation, and portrait

4. **Service Status Notifications**
   - **Trigger**: Service startup, connection status changes, or errors
   - **Frequency**: As events occur
   - **Content**: Status information and error details

### Testing Notifications

To test different notification types:

1. **Kill Notifications**: These will occur automatically every 5 minutes regardless of filters
2. **System Notifications**: Add a new system to your map via the map API
3. **Character Notifications**: Add a new character to your tracking list
4. **Service Status**: Restart the service or trigger a connection error

## Requirements

- Elixir (>= 1.12 recommended)
- Erlang/OTP (compatible version)
- [Docker](https://www.docker.com/) (optional, for development container)

## Installation

1. **Clone the repository:**

   ```bash
   git clone https://github.com/yourusername/wanderer-notifier.git
   cd wanderer-notifier
   ```

2. **Setup Environment Variables:**

   Create a `.env` file (you can use the provided `.env.example` as a template):

   ```dotenv
   # Required Core Configuration
   DISCORD_BOT_TOKEN=your_discord_bot_token
   LICENSE_KEY=your_license_key_here
   
   # Map Configuration
   MAP_URL=https://wanderer.zoolanders.space
   MAP_NAME=your_map_slug
   MAP_TOKEN=your_map_api_token
   
   # Feature Enablement Flags
   ENABLE_NOTIFICATIONS=true
   ENABLE_KILL_NOTIFICATIONS=true
   ENABLE_SYSTEM_NOTIFICATIONS=true
   ENABLE_CHARACTER_NOTIFICATIONS=true
   
   # Discord Channel Configuration
   DISCORD_CHANNEL_ID=your_main_discord_channel_id
   # Optional feature-specific channels:
   # DISCORD_KILL_CHANNEL_ID=your_kill_notifications_channel
   # DISCORD_SYSTEM_CHANNEL_ID=your_system_tracking_channel
   # DISCORD_CHARACTER_CHANNEL_ID=your_character_tracking_channel
   
   # API URLs
   ZKILL_BASE_URL=https://zkillboard.com
   ESI_BASE_URL=https://esi.evetech.net/latest
   ```
   
   For a complete list of all available environment variables, see the [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md) file.

3. **Install Dependencies:**

   Using the provided Makefile, run:

   ```bash
   make deps.get
   ```

4. **Compile the Project:**

   ```bash
   make compile
   ```

## Running the Application

You can run the application in several ways:

- **Interactive Shell:**

  ```bash
  make shell
  ```

- **Run the Application:**

  ```bash
  make run
  ```

- **Directly via Mix:**

  ```bash
  mix run --no-halt
  ```

## Development

### Using the Dev Container

This project includes a development container configuration for VS Code:

1. Install the [Remote - Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) for VS Code.
2. Open the repository in VS Code.
3. When prompted, reopen the project in the container. The container is configured using the included `devcontainer.json` and `Dockerfile`.
4. The container automatically runs `mix deps.get` upon setup.

### Frontend Development

For information about frontend development, including the automatic asset building system with Vite, see the [Frontend Development Guide](FRONTEND_DEV.md).

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

## Configuration

All configuration is managed through environment variables in the `.env` file. A template is provided as `.env.example`.

### Key Configuration Options

1. **Required Core Configuration**
   - `DISCORD_BOT_TOKEN`: Your Discord bot's authentication token (without "Bot" prefix)
   - `DISCORD_CHANNEL_ID`: Main Discord channel ID for notifications
   - `LICENSE_KEY`: Your license key for accessing premium features

2. **Map Configuration**
   - `MAP_URL`: URL of the map service
   - `MAP_NAME`: Map identifier for system tracking
   - `MAP_TOKEN`: Authentication token for map API

3. **Feature Enablement**
   - `ENABLE_NOTIFICATIONS`: Master switch for all notifications (default: `true`)
   - `ENABLE_KILL_NOTIFICATIONS`: Enable kill notifications (default: `true`)
   - `ENABLE_SYSTEM_NOTIFICATIONS`: Enable system tracking notifications (default: `true`)
   - `ENABLE_CHARACTER_NOTIFICATIONS`: Enable character tracking notifications (default: `true`)
   - `ENABLE_TPS_CHARTS`: Enable TPS charts (default: `false`)
   - `ENABLE_MAP_CHARTS`: Enable map/activity charts (default: `false`)
   - `ENABLE_CHARTS`: General charts functionality (default: `false`)
   - `TRACK_ALL_SYSTEMS`: Track all systems instead of specific ones (default: `false`)
   
   *Note*: The `ENABLE_CORP_TOOLS` and `ENABLE_MAP_TOOLS` variables are being gradually replaced by `ENABLE_TPS_CHARTS` and `ENABLE_MAP_CHARTS` respectively, but are still supported for backward compatibility.

4. **Feature-specific Discord Channels**
   - `DISCORD_KILL_CHANNEL_ID`: Channel for kill notifications (defaults to main channel)
   - `DISCORD_SYSTEM_CHANNEL_ID`: Channel for system tracking notifications (defaults to main channel)
   - `DISCORD_CHARACTER_CHANNEL_ID`: Channel for character tracking notifications (defaults to main channel)
   - `DISCORD_CHARTS_CHANNEL_ID`: Channel for general chart notifications (defaults to main channel)
   - `DISCORD_TPS_CHARTS_CHANNEL_ID`: Channel for TPS chart notifications (defaults to main channel)
   - `DISCORD_MAP_CHARTS_CHANNEL_ID`: Channel for map chart notifications (defaults to main channel)
   
   *Note*: The `DISCORD_CORP_TOOLS_CHANNEL_ID` and `DISCORD_MAP_TOOLS_CHANNEL_ID` variables are being gradually replaced by `DISCORD_TPS_CHARTS_CHANNEL_ID` and `DISCORD_MAP_CHARTS_CHANNEL_ID` respectively, but are still supported for backward compatibility.

5. **Slack Integration (Optional)**
   - `SLACK_WEBHOOK_URL`: Main Slack webhook URL
   - Feature-specific webhook URLs are also available (see ENVIRONMENT_VARIABLES.md)

6. **External Services**
   - `ZKILL_BASE_URL`: zKillboard API endpoint (default: `https://zkillboard.com`)
   - `ESI_BASE_URL`: EVE Swagger Interface endpoint (default: `https://esi.evetech.net/latest`)
   - `CORP_TOOLS_API_URL`: Corporation tools API URL
   - `CORP_TOOLS_API_TOKEN`: Corporation tools API token

7. **Application Configuration**
   - `CHART_SERVICE_PORT`: Port for the chart service (default: `3001`)
   - `PORT`: Port for the web interface (default: `4000`)

For a complete list of all environment variables, see [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md).

### Feature Relationships

Some features have dependencies on others:

- `ENABLE_CHARTS` is automatically considered enabled if `ENABLE_CORP_TOOLS` or `ENABLE_MAP_TOOLS` is enabled
- `ENABLE_TPS_CHARTS` is automatically considered enabled if `ENABLE_CORP_TOOLS` is enabled
- `ENABLE_ACTIVITY_CHARTS` is automatically considered enabled if `ENABLE_MAP_TOOLS` is enabled

### Channel Resolution Strategy

Each notification checks for a feature-specific channel first. If not found, it falls back to the main channel defined by `DISCORD_CHANNEL_ID`. This allows you to:

1. Send all notifications to a single channel by only setting `DISCORD_CHANNEL_ID`
2. Send specific notification types to different channels by setting the corresponding channel variables
3. Mix and match, with some notification types going to dedicated channels and others falling back to the main channel

Example:
```dotenv
# Main channel that will receive all non-specific notifications
DISCORD_CHANNEL_ID=123456789012345678

# Send kill notifications to a dedicated channel
DISCORD_KILL_CHANNEL_ID=234567890123456789

# Character and system notifications will go to the main channel
# since we haven't specified dedicated channels for them
```

These settings can be changed without restarting the application by updating the environment variables and reloading the configuration.

---

*Wanderer Notifier* integrates critical EVE Online data with Discord notifications in a robust, fault-tolerant manner. For any questions or issues, please open an issue on the repository.

For detailed technical documentation and architecture overview, see [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md).
