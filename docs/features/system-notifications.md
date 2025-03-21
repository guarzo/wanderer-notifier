# System Notifications

This document describes how system notifications work in the WandererNotifier application, particularly for wormhole systems.

## Overview

System notifications are triggered when a new system is discovered or added to tracking. They provide information about the system's characteristics, including wormhole class, region, and static connections.

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

### Static Information

The `staticInfo` map contains additional details about the system:

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
5. **Notification Determination**: The system uses `NotificationDeterminer.should_notify_system?` to decide if a notification should be sent
6. **Recent Kills Addition**: Recent kill data is fetched from zkillboard and added to the notification
7. **Notification Formatting**: The system data is formatted into a Discord embed
8. **Notification Sending**: The formatted notification is sent to the configured Discord channel

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

## Static Wormhole Information

For wormhole systems, the application includes detailed information about static connections. The `static_details` field contains:

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

## Recent Kill Information

To provide context about system activity, the notification includes recent kill information from zKillboard:

1. **Kill ID**: Unique identifier for the kill
2. **Victim Information**: Character name, ship type, and other victim details
3. **Value**: ISK value of the loss
4. **Time**: When the kill occurred
5. **ZKB Data**: Additional data provided by zkillboard

## System Type Classification

Systems are classified based on their ID ranges and properties:

1. Wormhole systems (`31000000` - `32000000`)

   - Class 1-6 wormholes
   - Thera
   - Shattered wormholes
   - Drifter wormholes

2. K-space systems
   - High-sec
   - Low-sec
   - Null-sec

The application determines system type using the following logic:

1. Check for API-provided data such as "type_description", "class_title", or "system_class"
2. Fall back to ID-based classification when API doesn't provide type information

## Discord Formatting

The system notification is formatted as a Discord embed with:

1. **Title**: System name (with nickname if available)
2. **Color**: Orange (#FFA500) to visually distinguish system notifications
3. **Fields**:
   - **System Type**: Wormhole class or K-space designation
   - **Region**: Region name
   - **Effect**: System effect (if applicable)
   - **Statics**: Static wormhole connections (if applicable)
   - **Recent Activity**: Summary of recent kills (if available)
4. **Links**:
   - Link to Dotlan for more information
   - Links to zKillboard for activity tracking

## Example Notification

```
[SYSTEM NOTIFICATION]
System: J123456 (Home)
Class: C3 Wolf-Rayet
Region: A-R00001
Statics: N062 (C5), E545 (NS)
Recent Activity: 3 kills in the last 24 hours
```

## Notification Determination Logic

The system uses a centralized notification determination system through the `NotificationDeterminer` module:

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
