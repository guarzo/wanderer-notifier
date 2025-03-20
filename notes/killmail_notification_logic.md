# Killmail Notification Logic

## Overview

This document explains how the killmail notification system works in Wanderer Notifier.

## Architecture

The killmail notification system consists of several components:

### 1. WebSocket Connection

- The application maintains a WebSocket connection to zKillboard.
- This connection listens for real-time killmail data as it's published.

### 2. Message Processing

- When a message is received, it's first parsed and validated.
- We ensure the message contains a killmail ID and a hash for verification.

### 3. Killmail Handling

- The parsed killmail data is processed in the Kill Processor service.
- The killmail is fetched from the ESI API using the ID and hash.
- Basic information is extracted and the killmail is saved to Redis cache.

### 4. Notification Determination

- The system uses the centralized `WandererNotifier.Services.NotificationDeterminer` to decide if a notification should be sent.
- For killmails, the determination is based on:
  - Whether kill notifications are enabled globally
  - Whether the kill occurred in a tracked system
  - Whether the kill involved a tracked character (as victim or attacker)
- The same module also handles determination for:
  - System notifications - checking if system notifications are enabled and if the specific system is being tracked
  - Character notifications - checking if character notifications are enabled and if the specific character is being tracked

### 5. Enrichment

- If the killmail should trigger a notification, it's enriched with additional data:
  - Character names (victim and attackers)
  - Corporation names
  - Alliance names
  - Ship type name
  - Solar system and region names

### 6. Notification Formatting

- The enriched killmail data is formatted into a Discord embed.
- The embed includes details about:
  - The victim (character, corporation, alliance, ship)
  - The final blow attacker
  - Other attack data (total attackers, damage done)
  - Location information (system, region)
  - Links to zKillboard for more details

### 7. Discord Delivery

- The formatted notification is sent to the configured Discord webhook.
- The notification appears in the user's Discord channel.

## Process Flow

1. WebSocket receives killmail data from zKillboard
2. Message is parsed and validated
3. Killmail is fetched from ESI API
4. Basic information is extracted and killmail is cached
5. Notification determiner checks if a notification should be sent
6. If yes, killmail is enriched with additional data
7. Notification is formatted into a Discord embed
8. Embed is sent to Discord webhook

## Key Files

- `lib/wanderer_notifier/websocket.ex` - WebSocket connection and message parsing
- `lib/wanderer_notifier/services/kill_processor.ex` - Killmail processing and notification handling
- `lib/wanderer_notifier/services/notification_determiner.ex` - Centralized notification determination logic
- `lib/wanderer_notifier/api/esi/service.ex` - ESI API services for data enrichment
- `lib/wanderer_notifier/api/map/systems.ex` - System tracking and notification logic
- `lib/wanderer_notifier/api/map/characters.ex` - Character tracking and notification logic
- `lib/wanderer_notifier/discord/service.ex` - Discord notification formatting and delivery

## Notification Determination Logic

The system uses a centralized notification determination system through the `NotificationDeterminer` module:

### For Kill Notifications:

```elixir
def should_notify_kill?(killmail, system_id) do
  # Check if kill notifications are enabled globally
  if !Features.kill_notifications_enabled?() do
    Logger.debug("Kill notifications disabled globally")
    false
  else
    # Check if the kill happened in a tracked system
    system_tracked = is_tracked_system?(system_id)

    # Check if the kill involved a tracked character
    character_tracked = has_tracked_character?(killmail)

    # Send notification if either condition is met
    system_tracked || character_tracked
  end
end
```

### For System Notifications:

```elixir
def should_notify_system?(system_id) do
  # Check if system notifications are enabled globally
  if !Features.system_notifications_enabled?() do
    Logger.debug("System notifications disabled globally")
    false
  else
    # Check if this specific system is being tracked
    is_tracked_system?(system_id)
  end
end
```

### For Character Notifications:

```elixir
def should_notify_character?(character_id) do
  # Check if character notifications are enabled globally
  if !Features.character_notifications_enabled?() do
    Logger.debug("Character notifications disabled globally")
    false
  else
    # Check if this specific character is being tracked
    is_tracked_character?(character_id)
  end
end
```

## Dependencies

- Redis - Used for caching killmail data and tracking information
- ESI API - Used for fetching additional killmail data and enrichment
- Discord Webhooks - Used for delivering notifications
