---
layout: default
title: Wanderer Notifier
description: Get real-time EVE Online notifications directly to your Discord channel
---

# Wanderer Notifier

Wanderer Notifier delivers real-time alerts directly to your Discord channel, ensuring you never miss critical in-game events. Whether it's a significant kill, a newly tracked character, or a fresh system discovery, our notifier keeps you informed with rich, detailed notifications.

In the fast-paced universe of EVE Online, timely information can mean the difference between success and failure. When a hostile fleet enters your territory, when a high-value target appears in your hunting grounds, or when a new wormhole connection opens up valuable opportunities - knowing immediately gives you the edge. Wanderer Notifier bridges this information gap, bringing critical intel directly to your Discord where your team is already coordinating.

## Prerequisites

Before setting up Wanderer Notifier, ensure you have the following:

- A Discord server where you have administrator permissions
- Docker and Docker Compose installed on your system
- Basic knowledge of terminal/command line operations
- Your Wanderer map URL and API token
- A Discord bot token (see our [guide on creating a Discord bot](https://gist.github.com/guarzo/a4d238b932b6a168ad1c5f0375c4a561))

## How to Get Started

There are two ways to install Wanderer Notifier: a **Quick Install** option using a one-liner, or a **Manual Setup** for those who prefer step-by-step control.

### Quick Install Option

For a streamlined installation that creates the necessary directory and files automatically, run:

```bash
curl -fsSL https://gist.githubusercontent.com/guarzo/3f05f3c57005c3cf3585869212caecfe/raw/33cba423f27c12a09ec3054d4eb76b283da66ab4/wanderer-notifier-setup.sh | bash
```

Once the script finishes, update the `wanderer-notifier/.env` file with your configuration values, then run the container.

### Manual Setup

If you'd rather set up everything manually, follow these steps:

#### 1. Download the Docker Image

Pull the latest Docker image:

```bash
docker pull guarzo/wanderer-notifier:latest
```

#### 2. Configure Your Environment

Create a `.env` file in your working directory with the following content. Replace the placeholder values with your actual credentials:

```dotenv
# Discord Configuration
DISCORD_BOT_TOKEN=your_discord_bot_token
DISCORD_APPLICATION_ID=your_discord_application_id # Optional
DISCORD_CHANNEL_ID=your_discord_channel_id

# Optional Discord Channel Configuration
# DISCORD_SYSTEM_KILL_CHANNEL_ID=your_system_kill_channel_id
# DISCORD_CHARACTER_KILL_CHANNEL_ID=your_character_kill_channel_id
# DISCORD_SYSTEM_CHANNEL_ID=your_system_channel_id
# DISCORD_CHARACTER_CHANNEL_ID=your_character_channel_id

# Map Configuration
MAP_URL="https://wanderer.ltd"
MAP_NAME="your map slug"
MAP_API_KEY=your_map_api_key

# License Configuration
LICENSE_KEY=your_license_key  # Provided with your map subscription

# Feature Flags (default values shown below)
# General Settings
# NOTIFICATIONS_ENABLED=true  # Master switch for all notifications
# STATUS_MESSAGES_ENABLED=false  # Controls startup/status notifications

# Notification Control
# KILL_NOTIFICATIONS_ENABLED=true  # Controls kill notifications
# SYSTEM_NOTIFICATIONS_ENABLED=true  # Controls system notifications
# CHARACTER_NOTIFICATIONS_ENABLED=true  # Controls character notifications
# RALLY_NOTIFICATIONS_ENABLED=true  # Controls rally point notifications

# Voice Participant Notifications (NEW)
# DISCORD_GUILD_ID=your_discord_guild_id  # Required for voice participant notifications
# VOICE_PARTICIPANT_NOTIFICATIONS_ENABLED=false  # Target only active voice channel users
# FALLBACK_TO_HERE_ENABLED=true  # Fallback to @here if no voice participants

# Character Configuration
# CHARACTER_EXCLUDE_LIST=character_id1,character_id2

# Priority Systems Configuration
# PRIORITY_SYSTEMS_ONLY=false  # Only send notifications for priority systems


```

> **Note:** If you don't have a Discord bot yet, follow our [guide on creating a Discord bot](https://gist.github.com/guarzo/a4d238b932b6a168ad1c5f0375c4a561) or search the web for more information.

> **Note:** The map configuration now uses separate `MAP_URL` and `MAP_NAME` variables for cleaner configuration. The application automatically combines these to create the full map URL.

#### 3. Create the Docker Compose Configuration

Create a file named `docker-compose.yml` with the following content:

```yaml
services:
  wanderer_notifier:
    image: guarzo/wanderer-notifier:latest
    container_name: wanderer-notifier
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - "${PORT:-4000}:4000"
    deploy:
      resources:
        limits:
          memory: 512M
      restart_policy:
        condition: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

#### 4. Run It

Start the service with Docker Compose:

```bash
docker-compose up -d
```

Your notifier is now up and running, delivering alerts to your Discord channel automatically!

## Discord Slash Commands

Wanderer Notifier supports Discord slash commands for managing your notification preferences directly from Discord:

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

### Setting Up Slash Commands

1. Ensure your bot has the `applications.commands` scope when inviting it to your server
2. Add your Discord Application ID to the `.env` file
3. Restart the notifier - commands will be registered automatically
4. Type `/notifier` in Discord to see available commands

### Priority Systems

Priority systems receive special treatment in notifications:
- System notifications in priority systems include targeted mentions (@here or voice participants)
- Ensures critical systems get immediate attention
- Priority status persists between bot restarts
- Can be configured to only send notifications for priority systems using `PRIORITY_SYSTEMS_ONLY=true`

### Voice Participant Notifications (NEW)

For more targeted notifications, the system can now notify only users actively in Discord voice channels:

- **Smart Targeting**: Only mentions users currently in voice channels (excludes AFK channel)
- **Fallback Support**: Optionally falls back to @here if no voice participants are found
- **Priority Integration**: Works seamlessly with priority systems for enhanced notifications
- **Configurable**: Disabled by default, requires Discord Guild ID to enable

## Configuration Validation

On startup, the application validates all configuration settings. If there are issues with your configuration, detailed error messages will be displayed in the logs to help you resolve them. This ensures that your notifier is properly configured before it begins operation.

## Current Features

- **Real-Time Kill Monitoring:** Receives pre-enriched killmail data via WebSocket connection to WandererKills service
- **Live Map Synchronization:** Uses Server-Sent Events (SSE) for real-time system and character updates from the map
- **Rich Discord Notifications:** Sends beautifully formatted embed notifications with ship thumbnails, character portraits, and kill details
- **Character & System Tracking:** Monitor specific characters and wormhole systems for targeted notifications
- **Rally Point Notifications:** Get instant alerts when players create rally points in your tracked systems
- **Multi-Channel Support:** Route different notification types (kills, character tracking, system updates) to separate Discord channels
- **Discord Slash Commands:** Manage priority systems and check bot status directly from Discord
- **Priority Systems:** Mark critical systems for special notifications with targeted mentions
- **Voice Participant Notifications:** Target only active voice channel users instead of @here mentions
- **License-Based Features:** Premium subscribers get rich embed notifications; free tier gets text-based alerts
- **Advanced Caching:** Multi-adapter caching system (Cachex/ETS) with intelligent TTL management
- **Data Enrichment:** Integrates with EVE's ESI API when needed (pre-enriched data used when available)
- **Map Integration:** Real-time SSE connection to Wanderer map API for system and character tracking
- **Robust Architecture:** Built on Elixir's OTP supervision trees for fault tolerance and reliability
- **Production Ready:** Comprehensive logging, telemetry, Docker deployment, and health checks

[Learn more about notification types](./notifications.html)

[View on GitHub](https://github.com/guarzo/wanderer-notifier)