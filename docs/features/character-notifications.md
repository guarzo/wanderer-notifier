# Character Notifications

This document outlines the character notification system in the WandererNotifier application, including the fields used in notifications and their sources within the code.

## Overview

Character notifications are triggered when a new character is discovered or added to tracking. They provide information about the character's name, corporation, and other relevant details.

## Notification Data Structure

When a new character is discovered, the `WandererNotifier.Api.Map.CharactersClient.notify_new_tracked_characters/2` function creates a notification with the following data structure:

| Field              | Description                | Source                         | Example      |
| ------------------ | -------------------------- | ------------------------------ | ------------ |
| `character_id`     | EVE Online character ID    | `Character.eve_id`             | `"12345678"` |
| `character_name`   | Character name             | `Character.name`               | `"John Doe"` |
| `corporation_name` | Corporation ticker or name | `Character.corporation_ticker` | `"CORP"`     |
| `corporation_id`   | EVE Online corporation ID  | `Character.corporation_id`     | `98765432`   |

## Character Data Structure

The underlying `WandererNotifier.Data.Character` struct contains these fields:

| Field                | Type                | Description                                  |
| -------------------- | ------------------- | -------------------------------------------- |
| `eve_id`             | `String.t()`        | EVE Online character ID (primary identifier) |
| `name`               | `String.t()`        | Character name                               |
| `corporation_id`     | `integer() \| nil`  | Corporation ID                               |
| `corporation_ticker` | `String.t() \| nil` | Corporation ticker (used as name)            |
| `alliance_id`        | `integer() \| nil`  | Alliance ID                                  |
| `alliance_ticker`    | `String.t() \| nil` | Alliance ticker (used as name)               |
| `tracked`            | `boolean()`         | Whether character is being tracked           |

## Data Flow

The character notification system follows this flow:

1. **Map API Response**: The character data is initially fetched from the Wanderer Map API (`/api/map/characters`)
2. **Data Transformation**: The API response is converted to `Character` structs in `CharactersClient.update_tracked_characters/1`
3. **New Characters Detection**: `CharactersClient.notify_new_tracked_characters/2` compares fresh characters with cached ones to identify newly discovered characters
4. **Notification Determination**: The system uses `NotificationDeterminer.should_notify_character?` to decide if a notification should be sent
5. **Notification Formatting**: For each new character, notification data is created with the fields described above
6. **Notification Sending**: The notifier (usually Discord) receives the character notification data structure
7. **Embedding**: The Discord notifier converts the data into a rich embed format using the `format_character_notification/1` function

## API Response Formats

The application handles two main formats for character data:

1. **Standard API Format**: Characters returned directly from the API

   ```json
   {
     "character": {
       "name": "Janissik",
       "alliance_id": null,
       "alliance_ticker": null,
       "corporation_id": 98551135,
       "corporation_ticker": "FLYSF",
       "eve_id": "404850015"
     },
     "tracked": true
   }
   ```

2. **Notification Format**: Simplified format used for notifications
   ```json
   {
     "character_id": "404850015",
     "character_name": "Janissik",
     "corporation_name": "FLYSF",
     "corporation_id": 98551135
   }
   ```

## Formatter Extraction

The `Formatter.format_character_notification/1` function extracts these fields using helper functions optimized for the two API formats:

1. `extract_character_id/1`: Extracts character ID from:

   - `character.eve_id` (Standard API Format)
   - `character_id` (Notification Format)

2. `extract_character_name/1`: Extracts character name from:

   - `character.name` (Standard API Format)
   - `character_name` (Notification Format)

3. `extract_corporation_name/1`: Extracts corporation name from:

   - `character.corporation_ticker` (Standard API Format)
   - `corporation_name` (Notification Format)
   - Falls back to ESI lookup if a corporation ID is available

4. `extract_corporation_id/1`: Extracts corporation ID from:
   - `character.corporation_id` (Standard API Format)
   - `corporation_id` (Notification Format)

## Discord Formatting

The character notification is formatted as a Discord embed with:

1. **Title**: Character name
2. **Color**: Green (#00FF00) to visually distinguish character notifications
3. **Thumbnail**: Character portrait from EVE Image Server
4. **Fields**:
   - **Character**: Character name with link to zKillboard
   - **Corporation**: Corporation name with link to zKillboard (if corporation ID is available)
   - **Character ID**: EVE Online character ID
5. **Links**:
   - Link to character's zKillboard page
   - Link to corporation's zKillboard page (if corporation ID is available)

## Example Notification

```
[CHARACTER NOTIFICATION]
Character: John Doe
Corporation: CORP
Character ID: 12345678
```

## Notification Determination Logic

The system uses a centralized notification determination system through the `NotificationDeterminer` module:

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

## Corporation ID Usage

The corporation ID is crucial for creating clickable links to zKillboard in character notifications. Without it, the notification will still display the corporation name but without a link to its zKillboard page.

## Character Portrait

The notification includes a character portrait retrieved from the EVE Image Server using the character's ID:

```
https://images.evetech.net/characters/{character_id}/portrait?size=128
```

This visual element helps users quickly identify the character being mentioned in the notification.
