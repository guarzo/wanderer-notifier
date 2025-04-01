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
docker pull guarzo/wanderer-notifier:latest
```

#### 2. Configure Your Environment

Create a `.env` file in your working directory with the following content. Replace the placeholder values with your actual credentials:

```dotenv
# Discord Configuration
WANDERER_DISCORD_BOT_TOKEN=your_discord_bot_token
WANDERER_DISCORD_CHANNEL_ID=your_discord_channel_id

# Map Configuration
WANDERER_MAP_URL="https://wanderer.ltd/<yourmap>"
WANDERER_MAP_TOKEN=your_map_api_token

# License Configuration (for enhanced features)
# Note: Premium features are enabled with your map subscription
WANDERER_LICENSE_KEY=your_map_license_key  # Provided with your map subscription

# Database Configuration (required)
# Default values shown below, customize as needed
# WANDERER_DB_USERNAME=postgres
# WANDERER_DB_PASSWORD=postgres
# WANDERER_DB_HOSTNAME=postgres
# WANDERER_DB_PORT=5432
# WANDERER_DB_POOL_SIZE=10

# Feature Flags (all enabled by default)
# WANDERER_FEATURE_KILL_NOTIFICATIONS=true
# WANDERER_FEATURE_CHARACTER_NOTIFICATIONS=true
# WANDERER_FEATURE_SYSTEM_NOTIFICATIONS=true
# WANDERER_FEATURE_TRACK_KSPACE=false  # Set to 'true' to track K-Space systems in addition to wormholes
```

> **Note:** For backward compatibility, legacy variable names (without the WANDERER\_ prefix) are still supported but will display deprecation warnings.
>
> **Note:** If you don't have a Discord bot yet, follow our [guide on creating a Discord bot](https://gist.github.com/guarzo/a4d238b932b6a168ad1c5f0375c4a561) or search the web for more information.

#### 3. Create the Docker Compose Configuration

Create a file named `docker-compose.yml` with the following content:

```yaml
services:
  wanderer_notifier:
    image: guarzo/wanderer-notifier:v1
    container_name: wanderer-notifier
    restart: unless-stopped
    environment:
      # Core application configuration
      WANDERER_PORT: "4000"
      WANDERER_DISCORD_BOT_TOKEN: ${WANDERER_DISCORD_BOT_TOKEN}
      WANDERER_DISCORD_CHANNEL_ID: ${WANDERER_DISCORD_CHANNEL_ID}
      WANDERER_MAP_URL: ${WANDERER_MAP_URL}
      WANDERER_MAP_TOKEN: ${WANDERER_MAP_TOKEN}
      WANDERER_LICENSE_KEY: ${WANDERER_LICENSE_KEY}
    ports:
      - "${WANDERER_PORT:-4000}:4000"
    depends_on:
      db_init:
        condition: service_completed_successfully
    volumes:
      - wanderer_data:/app/data
    deploy:
      resources:
        limits:
          memory: 512M
      restart_policy:
        condition: unless-stopped
    healthcheck:
      test:
        [
          "CMD",
          "wget",
          "--no-verbose",
          "--tries=1",
          "--spider",
          "http://localhost:4000/health",
        ]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Database service
  postgres:
    image: postgres:16-alpine
    container_name: wanderer-postgres
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
    environment:
      - POSTGRES_USER=${WANDERER_DB_USER:-postgres}
      - POSTGRES_PASSWORD=${WANDERER_DB_PASSWORD:-postgres}
      - POSTGRES_DB=${WANDERER_DB_NAME:-wanderer_notifier}
    volumes:
      - postgres_data:/var/lib/postgresql/data

  # Database initialization container
  db_init:
    image: guarzo/wanderer-notifier:latest
    profiles: ["database"]
    environment:
      # Database configuration
      WANDERER_DB_HOST: postgres
      WANDERER_DB_USER: ${WANDERER_DB_USER:-postgres}
      WANDERER_DB_PASSWORD: ${WANDERER_DB_PASSWORD:-postgres}
      WANDERER_DB_NAME: ${WANDERER_DB_NAME:-wanderer_notifier}
      WANDERER_DB_PORT: "5432"
    command: sh -c '/app/bin/wanderer_notifier eval "WandererNotifier.Release.createdb()" && /app/bin/wanderer_notifier eval "WandererNotifier.Release.migrate()"'
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  wanderer_data:
  postgres_data:
    name: wanderer_postgres_data
  db_backups:
    name: wanderer_db_backups
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

- **Real-Time Monitoring:** Listens to live kill data via a WebSocket from ZKillboard
- **Data Enrichment:** Retrieves detailed killmail information from ESI
- **Map-Based Filtering:** Uses a custom map API to track wormhole systems (with option to include K-Space systems) and process only kills from systems you care about
- **Periodic Maintenance:** Automatically updates system data and processes backup kills
- **Discord Integration:** Sends beautifully formatted notifications to your Discord channel
- **Web Dashboard:** Access system status and notification statistics via the built-in web interface
- **Fault Tolerance:** Leverages Elixir's OTP and supervision trees for a robust and resilient system

[Learn more about notification types](./notifications.html)

[View on GitHub](https://github.com/guarzo/wanderer-notifier)
