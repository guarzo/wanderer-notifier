# System Notification Fields

This document outlines the fields used in system notifications, particularly for wormhole systems, and their sources within the application.

## Notification Data Structure

When a new system is discovered, the `WandererNotifier.Api.Map.SystemsClient.notify_new_systems/2` function creates a notification with the following data structure:

| Field             | Description                                      | Source                                                                            | Example                                       |
| ----------------- | ------------------------------------------------ | --------------------------------------------------------------------------------- | --------------------------------------------- |
| `name`            | System display name (with nickname if available) | `MapSystem.name` or formatted combination of `temporary_name` and `original_name` | `"J123456"` or `"Home (J123456)"`             |
| `id`              | Solar system ID                                  | `MapSystem.solar_system_id`                                                       | `31000123`                                    |
| `url`             | Link to system on Dotlan                         | Generated from system name                                                        | `"https://evemaps.dotlan.net/system/J123456"` |
| `region_name`     | Region name                                      | `MapSystem.region_name`                                                           | `"A-R00001"`                                  |
| `class_title`     | Wormhole class designation                       | `MapSystem.class_title`                                                           | `"C3"`                                        |
| `effect_name`     | Name of system effect (if any)                   | `MapSystem.effect_name`                                                           | `"Wolf-Rayet"`                                |
| `system_type`     | Type of system                                   | Derived from `MapSystem.is_wormhole?`                                             | `"wormhole"` or `"k-space"`                   |
| `original_name`   | Original EVE system name                         | `MapSystem.original_name`                                                         | `"J123456"`                                   |
| `temporary_name`  | User-assigned nickname                           | `MapSystem.temporary_name`                                                        | `"Home"`                                      |
| `solar_system_id` | EVE Online solar system ID                       | `MapSystem.solar_system_id`                                                       | `31000123`                                    |
| `staticInfo`      | Nested map with additional info                  | Generated in notification process                                                 | See below                                     |
| `recent_kills`    | List of recent zkillboard kills                  | Fetched from zkillboard API                                                       | Array of kill data                            |

### `staticInfo` Structure

The `staticInfo` map contains the following fields:

| Field             | Description                           | Source                                         | Example                 |
| ----------------- | ------------------------------------- | ---------------------------------------------- | ----------------------- |
| `typeDescription` | Description of system type            | Based on `MapSystem.class_title` or fixed text | `"C3"` or `"K-Space"`   |
| `statics`         | Formatted static wormhole connections | Generated from `statics` and `static_details`  | `"N062 (C5), E545 (N)"` |
| `effectName`      | Name of system effect                 | `MapSystem.effect_name`                        | `"Wolf-Rayet"`          |
| `regionName`      | Region name                           | `MapSystem.region_name`                        | `"A-R00001"`            |
| `static_details`  | Raw static wormhole details           | `MapSystem.static_details`                     | Array of static details |
| `class_title`     | Wormhole class                        | `MapSystem.class_title`                        | `"C3"`                  |

## Data Flow

1. **Map API Response**: The system data is initially fetched from the Wanderer Map API (`/api/map/systems`)
2. **Data Transformation**: The API response is converted to `MapSystem` structs in `SystemsClient.update_systems/1`
3. **Static Info Enrichment**: For wormhole systems, additional information is fetched from `/api/common/system-static-info` and integrated through `MapSystem.update_with_static_info/2`
4. **New Systems Detection**: `SystemsClient.notify_new_systems/2` compares fresh systems with cached ones to identify newly discovered systems
5. **Notification Formatting**: For each new system, notification data is created with all the fields described above
6. **Recent Kills Addition**: Recent kill data is fetched from zkillboard and added to the notification
7. **Notification Sending**: The notifier (usually Discord) receives the complete notification data structure
8. **Embedding**: The Discord notifier converts the data into a rich embed format using the `add_recent_kills_to_embed/2` function

## Static Wormhole Information

The `static_details` field contains detailed information about wormhole statics, including:

```json
[
  {
    "name": "E545",
    "destination": {
      "id": "ns",
      "name": "Null-sec",
      "short_name": "N"
    },
    "properties": {
      "lifetime": "16",
      "mass_regeneration": 0,
      "max_jump_mass": 300000000,
      "max_mass": 2000000000
    }
  },
  {
    "name": "N062",
    "destination": {
      "id": "c5",
      "name": "Class 5",
      "short_name": "C5"
    },
    "properties": {
      "lifetime": "24",
      "mass_regeneration": 0,
      "max_jump_mass": 375000000,
      "max_mass": 3000000000
    }
  }
]
```

This is transformed into a human-readable format (e.g., `"E545 (N), N062 (C5)"`) for display in notifications.

## Recent Kills Information

Recent kill information is fetched from zkillboard's API and includes:

1. **Kill ID**: Unique identifier for the kill
2. **Victim Information**: Character name, ship type, and other victim details
3. **Value**: ISK value of the loss
4. **Time**: When the kill occurred
5. **ZKB Data**: Additional data provided by zkillboard

This information is embedded in the Discord notification to show recent activity in the system.

## Core System Fields

| Field             | Description                                   | Example Value                          |
| ----------------- | --------------------------------------------- | -------------------------------------- |
| `id`              | Unique identifier for the system              | "02ce832e-cae1-4f49-9d28-0685775922fe" |
| `solar_system_id` | EVE Online system ID                          | 31000864                               |
| `name`            | Display name (formatted)                      | "J123456"                              |
| `original_name`   | Original EVE system name                      | "J123456"                              |
| `temporary_name`  | User-assigned nickname                        | "Home"                                 |
| `class_title`     | Wormhole class designation                    | "C2"                                   |
| `effect_name`     | System effect name                            | "Pulsar"                               |
| `region_name`     | EVE region containing the system              | "B-R00008"                             |
| `statics`         | List of static wormhole types                 | ["B274", "Z647"]                       |
| `static_details`  | Detailed information about static connections | (see example below)                    |
| `system_type`     | Type classification (atom)                    | :wormhole                              |

## System Naming Logic

The application follows specific rules for displaying system names:

1. In the `MapSystem.new` function:

   - `name` is set directly from the map API response
   - `original_name` is set from explicit field if available, falling back to `name`
   - `temporary_name` is set only if it's different from `original_name`

2. When formatting a system name for display (`MapSystem.format_display_name`):

   - If both `temporary_name` and `original_name` exist, use format: `"temporary_name (original_name)"`
   - If only `original_name` exists, use it
   - Fall back to `name` field if needed

3. In the notification flow, system data is passed through several functions:
   - `SystemsClient.notify_new_systems` prepares data for notification
   - The full `system` object is included in the notification data
   - `Formatter.format_system_notification` extracts and displays the name fields

## Examples

### Static Details Example

```json
[
  {
    "destination": {
      "id": "hs",
      "name": "High-sec",
      "short_name": "H"
    },
    "name": "B274",
    "properties": {
      "lifetime": "24",
      "mass_regeneration": 0,
      "max_jump_mass": 300000000,
      "max_mass": 2000000000
    }
  },
  {
    "destination": {
      "id": "c1",
      "name": "Class 1",
      "short_name": "C1"
    },
    "name": "Z647",
    "properties": {
      "lifetime": "16",
      "mass_regeneration": 0,
      "max_jump_mass": 62000000,
      "max_mass": 500000000
    }
  }
]
```

### Formatted Static Display

When formatting statics with destinations, statics will appear as:

```
B274 (H), Z647 (C1)
```

### Recent Kills Data

Recent kills are fetched from zKillboard and embedded in the notification. Example data:

```elixir
[
  %{
    "killmail_id" => 95827292,
    "zkb" => %{
      "hash" => "4d3b08854c2f26ef8951e1d3c1418b89a1b85889",
      "totalValue" => 187340151.23
    }
  }
]
```
