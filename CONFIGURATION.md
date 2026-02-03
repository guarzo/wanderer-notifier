# Configuration Reference

This document provides a comprehensive reference for all environment variables used to configure Wanderer Notifier.

---

## Table of Contents

- [Required Configuration](#required-configuration)
- [Discord Configuration](#discord-configuration)
- [Map API Configuration](#map-api-configuration)
- [License Configuration](#license-configuration)
- [Feature Flags](#feature-flags)
- [Notification Channels](#notification-channels)
- [Voice Notifications](#voice-notifications)
- [Filtering & Exclusions](#filtering--exclusions)
- [Service URLs](#service-urls)
- [Application Settings](#application-settings)
- [Timing Configuration](#timing-configuration)

---

## Required Configuration

These variables must be set for the application to function.

| Variable | Description | Example |
|----------|-------------|---------|
| `DISCORD_BOT_TOKEN` | Discord bot authentication token | `MTEyMzQ1...` |
| `DISCORD_CHANNEL_ID` | Main Discord channel ID for notifications | `123456789012345678` |
| `MAP_URL` | Base URL for the Wanderer map API | `https://wanderer.ltd` |
| `MAP_NAME` | Slug identifier for your specific map | `my-corp-map` |
| `MAP_API_KEY` | Authentication token for map API access | `abc123...` |

---

## Discord Configuration

Configure Discord bot integration and slash commands.

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `DISCORD_BOT_TOKEN` | Bot authentication token | — | Yes |
| `DISCORD_APPLICATION_ID` | Application ID for slash commands | — | For commands |
| `DISCORD_CHANNEL_ID` | Main notification channel | — | Yes |
| `DISCORD_GUILD_ID` | Server/guild ID (for voice features) | — | For voice |

---

## Map API Configuration

Configure the connection to the Wanderer map service.

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `MAP_URL` | Base URL for map API | — | Yes |
| `MAP_NAME` | Your map's slug identifier | — | Yes |
| `MAP_API_KEY` | API authentication token | — | Yes |

---

## License Configuration

Configure premium license features.

| Variable | Description | Default |
|----------|-------------|---------|
| `LICENSE_KEY` | Your license key for premium features | — |
| `LICENSE_MANAGER_API_KEY` | API token for license validation | — |
| `LICENSE_MANAGER_URL` | License manager endpoint | `https://lm.wanderer.ltd/api` |

> **Note:** Without a license, the free tier allows 5 rich embed notifications per type before switching to text format.

---

## Feature Flags

Toggle specific features on or off.

| Variable | Description | Default |
|----------|-------------|---------|
| `NOTIFICATIONS_ENABLED` | Master switch for all notifications | `true` |
| `KILL_NOTIFICATIONS_ENABLED` | Enable kill notifications | `true` |
| `SYSTEM_NOTIFICATIONS_ENABLED` | Enable system tracking notifications | `true` |
| `CHARACTER_NOTIFICATIONS_ENABLED` | Enable character tracking notifications | `true` |
| `RALLY_NOTIFICATIONS_ENABLED` | Enable rally point notifications | `true` |
| `STATUS_MESSAGES_ENABLED` | Enable startup/status messages | `false` |
| `TRACK_KSPACE_ENABLED` | Track K-Space systems | `true` |
| `PRIORITY_SYSTEMS_ONLY` | Only notify for priority systems | `false` |
| `WORMHOLE_ONLY_KILL_NOTIFICATIONS` | Only notify for wormhole kills | `false` |
| `NOTABLE_ITEMS_ENABLED` | Enable notable item detection | `false` |

---

## Notification Channels

Route different notification types to separate Discord channels.

| Variable | Description | Default |
|----------|-------------|---------|
| `DISCORD_CHANNEL_ID` | Main/fallback notification channel | — (Required) |
| `DISCORD_SYSTEM_CHANNEL_ID` | System tracking notifications | Main channel |
| `DISCORD_CHARACTER_CHANNEL_ID` | Character tracking notifications | Main channel |
| `DISCORD_SYSTEM_KILL_CHANNEL_ID` | Kill notifications (by system) | Main channel |
| `DISCORD_CHARACTER_KILL_CHANNEL_ID` | Kill notifications (by character) | Main channel |

> **Tip:** Using separate channels helps organize notifications and allows team members to subscribe to specific feeds.

---

## Voice Notifications

Target users in voice channels for priority notifications.

| Variable | Description | Default |
|----------|-------------|---------|
| `DISCORD_GUILD_ID` | Server ID (required for voice features) | — |
| `VOICE_PARTICIPANT_NOTIFICATIONS_ENABLED` | Target voice channel users | `false` |
| `FALLBACK_TO_HERE_ENABLED` | Use @here if no voice users | `true` |

---

## Filtering & Exclusions

Control which notifications are sent and which are filtered out.

### Corporation Kill Focus

| Variable | Description | Example |
|----------|-------------|---------|
| `CORPORATION_KILL_FOCUS` | Corporation IDs for focused kill routing | `98000001,98000002` |

> When set, kills involving characters from these corporations (as victim or attacker) will be routed to the **character kill channel** and excluded from the system kill channel. This is useful for tracking your own corporation's kills separately from general system activity.

### Character Exclusion

| Variable | Description | Example |
|----------|-------------|---------|
| `CHARACTER_EXCLUDE_LIST` | Character IDs to exclude from tracking | `12345678,87654321` |

---

## Service URLs

Configure connections to external services. These have sensible defaults for Docker environments.

| Variable | Description | Default |
|----------|-------------|---------|
| `WEBSOCKET_URL` | WebSocket URL for killmail data | `ws://host.docker.internal:4004` |
| `WANDERER_KILLS_URL` | WandererKills API base URL | `http://host.docker.internal:4004` |
| `LICENSE_MANAGER_URL` | License validation endpoint | `https://lm.wanderer.ltd/api` |

---

## Application Settings

General application configuration.

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Web server port | `4000` |
| `HOST` | Web server hostname | `localhost` |
| `SCHEME` | URL scheme (http/https) | `http` |
| `PUBLIC_URL` | Publicly accessible URL | `http://localhost:4000` |
| `CACHE_DIR` | Directory for cache storage | `/app/data/cache` |
| `NOTIFIER_API_TOKEN` | API token for dashboard access | — |

---

## Timing Configuration

Control notification timing and filtering.

| Variable | Description | Default |
|----------|-------------|---------|
| `STARTUP_SUPPRESSION_SECONDS` | Suppress notifications after startup | `30` |
| `MAX_KILLMAIL_AGE_SECONDS` | Maximum age for killmail notifications | `3600` (1 hour) |

> **Startup Suppression:** Prevents notification spam when the service restarts by ignoring events for the specified duration.
>
> **Max Killmail Age:** Prevents notifications for old killmails when the service starts or reconnects. Killmails older than this threshold are silently skipped.

---

## External APIs

### Janice API (for notable items)

| Variable | Description | Required |
|----------|-------------|----------|
| `JANICE_API_TOKEN` | Janice API authentication token | For notable items |

---

## Example Configuration

A minimal configuration for getting started:

```bash
# Required
DISCORD_BOT_TOKEN=your_bot_token
DISCORD_CHANNEL_ID=YOUR_DISCORD_CHANNEL_ID
MAP_URL=https://wanderer.ltd
MAP_NAME=my-map
MAP_API_KEY=your_map_api_key

# Recommended
DISCORD_APPLICATION_ID=your_app_id  # For slash commands
LICENSE_KEY=your_license_key        # For unlimited rich embeds
```

A production configuration with multiple channels:

```bash
# Core
DISCORD_BOT_TOKEN=your_bot_token
DISCORD_APPLICATION_ID=your_app_id
DISCORD_CHANNEL_ID=YOUR_DISCORD_CHANNEL_ID
MAP_URL=https://wanderer.ltd
MAP_NAME=my-map
MAP_API_KEY=your_map_api_key
LICENSE_KEY=your_license_key

# Separate channels for organization
DISCORD_SYSTEM_KILL_CHANNEL_ID=YOUR_DISCORD_SYSTEM_KILL_CHANNEL_ID
DISCORD_CHARACTER_KILL_CHANNEL_ID=YOUR_DISCORD_CHARACTER_KILL_CHANNEL_ID
DISCORD_SYSTEM_CHANNEL_ID=YOUR_DISCORD_SYSTEM_CHANNEL_ID
DISCORD_CHARACTER_CHANNEL_ID=YOUR_DISCORD_CHARACTER_CHANNEL_ID

# Voice notifications
DISCORD_GUILD_ID=YOUR_DISCORD_GUILD_ID
VOICE_PARTICIPANT_NOTIFICATIONS_ENABLED=true

# Focus your corporation's kills to character channel
CORPORATION_KILL_FOCUS=98000001,98000002
```

---

## See Also

- [README.md](README.md) - Project overview and quick start
- [.env.example](.env.example) - Template configuration file
