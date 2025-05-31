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
curl -fsSL https://gist.githubusercontent.com/guarzo/3f05f3c57005c3cf3585869212caecfe/raw/wanderer-notifier-setup.sh | bash
```

Once the script finishes, update the `wanderer-notifier/.env` file with your configuration values, then run the container. The setup includes a PostgreSQL database which is now required for the application to function properly.

### Manual Setup

If you'd rather set up everything manually, follow these steps:

#### 1. Download the Docker Image

Pull the latest Docker image:

```bash
docker pull guarzo/wanderer-notifier:v1
```

#### 2. Configure Your Environment

Create a `.env` file in your working directory with the following content. Replace the placeholder values with your actual credentials:

```dotenv
# Discord Configuration
DISCORD_BOT_TOKEN=your_discord_bot_token
DISCORD_CHANNEL_ID=your_discord_channel_id

# Optional Discord Channel Configuration
# DISCORD_SYSTEM_KILL_CHANNEL_ID=your_system_kill_channel_id
# DISCORD_CHARACTER_KILL_CHANNEL_ID=your_character_kill_channel_id
# DISCORD_SYSTEM_CHANNEL_ID=your_system_channel_id
# DISCORD_CHARACTER_CHANNEL_ID=your_character_channel_id

# Map Configuration
MAP_URL="https://wanderer.ltd"
MAP_NAME="yourmap"
MAP_API_KEY=your_map_api_key

# License Configuration
LICENSE_KEY=your_license_key  # Provided with your map subscription

# Notifier API Configuration
NOTIFIER_API_TOKEN=your_notifier_api_token

# Feature Flags (default values shown below)
# General Settings
# NOTIFICATIONS_ENABLED=true  # Master switch for all notifications
# DISABLE_STATUS_MESSAGES=false  # Controls startup/status notifications

# Notification-Related Flags
# KILL_NOTIFICATIONS_ENABLED=true  # Controls kill notifications
# SYSTEM_NOTIFICATIONS_ENABLED=true  # Controls system notifications
# CHARACTER_NOTIFICATIONS_ENABLED=true  # Controls character notifications

# Tracking-Related Flags
# TRACK_KSPACE_ENABLED=true  # Controls whether K-Space systems are tracked
# SYSTEM_TRACKING_ENABLED=true  # Controls system data tracking scheduler
# CHARACTER_TRACKING_ENABLED=true  # Controls character data tracking scheduler

# Character Configuration
# CHARACTER_EXCLUDE_LIST=character_id1,character_id2

# Cache and RedisQ Configuration
# CACHE_DIR=/app/data/cache
# REDISQ_URL=https://zkillredisq.stream/listen.php
# REDISQ_POLL_INTERVAL_MS=1000

# License Manager Configuration
# LICENSE_MANAGER_URL=https://lm.wanderer.ltd

```

> **Note:** If you don't have a Discord bot yet, follow our [guide on creating a Discord bot](https://gist.github.com/guarzo/a4d238b932b6a168ad1c5f0375c4a561) or search the web for more information.

> **Note:** The map configuration now uses separate `MAP_URL` and `MAP_NAME` variables for cleaner configuration. The application automatically combines these to create the full map URL.

#### 3. Create the Docker Compose Configuration

Create a file named `docker-compose.yml` with the following content:

```yaml
services:
  wanderer_notifier:
    image: guarzo/wanderer-notifier:v1
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

## Configuration Validation

On startup, the application validates all configuration settings. If there are issues with your configuration, detailed error messages will be displayed in the logs to help you resolve them. This ensures that your notifier is properly configured before it begins operation.

## Features

- **Real-Time Monitoring:** Listens to live kill data via polling from ZKillboard
- **Data Enrichment:** Retrieves detailed killmail information from ESI
- **Map-Based Filtering:** Uses a custom map API to track wormhole systems (with option to include K-Space systems) and process only kills from systems you care about
- **Periodic Maintenance:** Automatically updates system data and processes backup kills
- **Discord Integration:** Sends beautifully formatted notifications to your Discord channel
- **Fault Tolerance:** Leverages Elixir's OTP and supervision trees for a robust and resilient system

[Learn more about notification types](./notifications.html)

[View on GitHub](https://github.com/guarzo/wanderer-notifier)
