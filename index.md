---
layout: default
title: Wanderer Notifier
description: Get real-time EVE Online notifications directly to your Discord channel
---

# Wanderer Notifier

Wanderer Notifier delivers real-time alerts directly to your Discord channel, so you never miss critical in-game events. Whether it's a significant kill event, a new tracked character, or a newly discovered system, our notifier keeps you informed with rich, detailed notifications.

## Features

- **Real-Time Monitoring:** Listens to live kill data via a WebSocket from ZKillboard
- **Data Enrichment:** Retrieves detailed killmail information from ESI
- **Map-Based Filtering:** Uses a custom map API to track wormhole systems and process only kills from systems you care about
- **Periodic Maintenance:** Automatically updates system data and processes backup kills
- **Discord Integration:** Sends beautifully formatted notifications to your Discord channel
- **Fault Tolerance:** Leverages Elixir's OTP and supervision trees for a robust and resilient system

## How to Get Started

### 1. Download the Docker Image

Pull the latest Wanderer Notifier image by running:

```bash
docker pull guarzo/wanderer-notifier:v1
```

### 2. Configure Your Environment

Create a `.env` file in your working directory with the following content. Replace the placeholder values with your actual credentials and settings:

```dotenv
# Required Configuration
DISCORD_BOT_TOKEN=your_discord_bot_token
DISCORD_CHANNEL_ID=your_discord_channel_id
MAP_URL_WITH_NAME="https://wanderer.ltd/<yourmap>"
MAP_TOKEN=your_map_api_token

# License Configuration (for enhanced features)
LICENSE_KEY=your_license_key

# Environment Configuration
MIX_ENV=prod

# Web Server Configuration (defaults shown)
PORT=4000
HOST=0.0.0.0

# Notification Control (all enabled by default)
# ENABLE_KILL_NOTIFICATIONS=true
# ENABLE_CHARACTER_TRACKING=true
# ENABLE_CHARACTER_NOTIFICATIONS=true
# ENABLE_SYSTEM_NOTIFICATIONS=true
```

### 3. Run Using Docker Compose

Create a `docker-compose.yml` file with the configuration below:

```yaml
services:
  wanderer_notifier:
    image: guarzo/wanderer-notifier:latest
    container_name: wanderer_notifier
    restart: unless-stopped
    environment:
      # Environment setting
      - MIX_ENV=prod
      
      # Discord Configuration
      - DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
      - DISCORD_CHANNEL_ID=${DISCORD_CHANNEL_ID}
      
      # Map Configuration
      - MAP_URL_WITH_NAME=${MAP_URL_WITH_NAME}
      - MAP_TOKEN=${MAP_TOKEN}
      
      # License Configuration
      - LICENSE_KEY=${LICENSE_KEY}
      
      # Application Configuration
      - PORT=${PORT:-4000}
      - HOST=${HOST:-0.0.0.0}
    ports:
      - "${PORT:-4000}:${PORT:-4000}"
    volumes:
      - wanderer_data:/app/data
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "${PORT:-4000}"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  wanderer_data:
```

Start the service by executing:

```bash
docker-compose up -d
```

Your notifier is now up and running—delivering alerts to your Discord channel automatically!

[Learn more about notification types](./notifications.html) | [See license comparison](./license.html) | [View on GitHub](https://github.com/guarzo/wanderer-notifier) 