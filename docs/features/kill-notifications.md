# Kill Notifications

This document outlines the kill notification system in the WandererNotifier application, including the message flow, data processing, and notification logic.

## Overview

Kill notifications provide real-time alerts when ships are destroyed in tracked systems or when tracked characters are involved in combat. The notifications include details about the victim, attackers, location, and value of the destroyed ship.

## Architecture

The kill notification system consists of several interconnected components:

### 1. WebSocket Connection

- The application maintains a WebSocket connection to zKillboard
- This connection listens for real-time killmail data as it's published
- WebSocket messages are received in `WandererNotifier.Api.ZKill.WebSocket` via the `handle_frame/2` function
- Messages are parsed and classified in `process_text_frame/2`

### 2. Message Processing

- Valid kill messages are forwarded to the main service GenServer via `{:zkill_message, message}`
- The service GenServer receives the message in its `handle_info/2` function and forwards to `KillProcessor`
- `KillProcessor.process_zkill_message/2` parses and validates the kill data
- If valid, the kill is cached and ready for notification

### 3. Killmail Handling

- The parsed killmail data is processed in the Kill Processor service
- The killmail is fetched from the ESI API using the ID and hash
- Basic information is extracted and the killmail is saved to the application cache

### 4. Notification Determination

- The system uses the centralized `WandererNotifier.Services.NotificationDeterminer` to decide if a notification should be sent
- For killmails, the determination is based on:
  - Whether kill notifications are enabled globally
  - Whether the kill occurred in a tracked system
  - Whether the kill involved a tracked character (as victim or attacker)

### 5. Enrichment

- If the killmail should trigger a notification, it's enriched with additional data:
  - Character names (victim and attackers)
  - Corporation names
  - Alliance names
  - Ship type name
  - Solar system and region names

### 6. Notification Formatting

- The enriched killmail data is formatted into a Discord embed
- The embed includes details about:
  - The victim (character, corporation, alliance, ship)
  - The final blow attacker
  - Other attack data (total attackers, damage done)
  - Location information (system, region)
  - Links to zKillboard for more details

### 7. Discord Delivery

- The formatted notification is sent to the configured Discord webhook
- The notification appears in the user's Discord channel

## Process Flow

1. WebSocket receives killmail data from zKillboard
2. Message is parsed and validated
3. Killmail is fetched from ESI API
4. Basic information is extracted and killmail is cached
5. Notification determiner checks if a notification should be sent
6. If yes, killmail is enriched with additional data
7. Notification is formatted into a Discord embed
8. Embed is sent to Discord webhook

## Cache Implementation

### Cache Structure

The kill notification system uses an in-memory cache to store recent kills:

1. Each kill is stored individually with its own key
2. A separate list of recent kill IDs is maintained
3. TTL is applied to avoid unbounded cache growth
4. Data is converted to the `WandererNotifier.Data.Killmail` struct when possible for consistency

### Cache Keys

The following cache keys are used for kill data:

- `zkill:recent_kills` - List of recent kill IDs
- `zkill:recent_kills:{kill_id}` - Individual kill data

Each kill has a TTL of 1 hour to prevent the cache from growing unbounded.

### Benefits

- Kills are accessible from any process in the application
- Persistence across WebSocket restarts (until TTL expires)
- Automatic cleanup via TTL
- Better data structure consistency with the Killmail struct

## Killmail Data Structure Handling

The application needs to handle killmails in multiple formats:

1. Raw JSON strings from the WebSocket
2. Parsed maps with string keys
3. `WandererNotifier.Data.Killmail` structs
4. Maps with atom keys

Pattern matching is used to handle all these formats consistently, extracting the necessary information regardless of the source format.

## Notification Determination Logic

The system uses a centralized notification determination system through the `NotificationDeterminer` module:

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

## Discord Formatting

Kill notifications are formatted as Discord embeds with the following structure:

1. **Title**: "Kill Alert: [Victim Name]"
2. **Color**: Red (#E74C3C) to visually distinguish kill notifications
3. **Description**: "[Killer] destroyed [Ship Type] worth [Value] ISK"
4. **Thumbnail**: Ship type image
5. **Fields**:
   - **Location**: System name and security status
   - **Time**: Timestamp of the kill
   - **Involved Parties**: Number of attackers
6. **Footer**: "Data via zKillboard • [Timestamp]"

## Example Notification

```
[KILL ALERT]
Victim: John Doe (ALLIANCE)
Ship: Vindicator
System: J123456 (C5)
Value: 1,250,000,000 ISK
Final Blow: Jane Smith (ENEMIES)
```

## Testing Notifications

To test kill notifications:

1. Call the `/api/test-notification` endpoint
2. The system will look for recent kills in the shared cache
3. If found, it will use the most recent one for the test notification
4. If no recent kills are found, it will fall back to sample data

## Debugging

The system has extensive logging with specific trace tags:

- `WEBSOCKET TRACE` - For WebSocket connection and message receipt
- `PROCESSOR TRACE` - For message processing and parsing
- `KILLMAIL TRACE` - For killmail-specific handling
- `CACHE TRACE` - For cache operations

These logs can help identify where issues are occurring in the processing chain.

## Key Files

- `lib/wanderer_notifier/websocket.ex` - WebSocket connection and message parsing
- `lib/wanderer_notifier/services/kill_processor.ex` - Killmail processing and notification handling
- `lib/wanderer_notifier/services/notification_determiner.ex` - Centralized notification determination logic
- `lib/wanderer_notifier/api/esi/service.ex` - ESI API services for data enrichment
- `lib/wanderer_notifier/discord/service.ex` - Discord notification formatting and delivery

## Dependencies

- In-memory caching - Used for storing killmail data and tracking information
- ESI API - Used for fetching additional killmail data and enrichment
- Discord Webhooks - Used for delivering notifications
