# Notification System

The WandererNotifier application provides several types of Discord notifications to keep users informed about in-game events and system status.

## Notification Types

### 1. Kill Notifications

- **Purpose**: Real-time alerts for ship destructions in tracked systems or involving tracked characters
- **Trigger**: When a ship is destroyed in a tracked system or involves a tracked character
- **Frequency**: Real-time as events occur
- **Content**: Detailed information about the kill, including:
  - System location and kill value
  - Victim details (character, corporation, ship type)
  - Final blow attacker information
  - Top damage dealer (if different)
- **Visual Elements**:
  - Ship thumbnails and corporation icons
  - Direct links to zKillboard
  - Distinctive red color scheme for easy identification

### 2. System Notifications

- **Purpose**: Alerts when new systems are added to tracking
- **Trigger**: When a new system is added to the tracking list via the map API
- **Frequency**: Real-time when systems are added
- **Content**:
  - System name, ID, and link to zKillboard
  - System classification (wormhole class, region)
  - Static wormhole connections (if applicable)
  - Recent kill activity
- **Visual Elements**:
  - Distinctive orange color scheme for easy identification
  - Structured data presentation
  - Links to external resources (Dotlan, zKillboard)

### 3. Character Notifications

- **Purpose**: Notifications for newly tracked characters
- **Trigger**: When a new character is added to the tracking list
- **Frequency**: Real-time when characters are added
- **Content**:
  - Character name and ID
  - Corporation affiliation
  - Links to zKillboard profiles
- **Visual Elements**:
  - Character portraits
  - Corporation affiliations
  - Links to character profiles
  - Green color scheme for visual distinction

### 4. Service Status Updates

- **Purpose**: System startup confirmations and service monitoring
- **Trigger**: Service startup, connection status changes, or errors
- **Frequency**: As events occur
- **Content**:
  - Status information
  - Error details
  - System version and configuration
- **Visual Elements**:
  - Color-coded status indicators
  - Timestamp information
  - Service identification

## Notification Determination

The application uses a centralized notification determination system through the `NotificationDeterminer` module to decide when to send notifications:

### For Kill Notifications:

Notifications are sent when:

- Kill notifications are enabled globally (`ENABLE_KILL_NOTIFICATIONS=true`)
- AND EITHER:
  - The kill happened in a tracked system
  - OR the kill involved a tracked character (as victim or attacker)

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

Notifications are sent when:

- System notifications are enabled globally (`ENABLE_SYSTEM_NOTIFICATIONS=true`)
- AND the specific system is being tracked

### For Character Notifications:

Notifications are sent when:

- Character notifications are enabled globally (`ENABLE_CHARACTER_NOTIFICATIONS=true`)
- AND the specific character is being tracked

## Testing Notifications

To test different notification types:

1. **Kill Notifications**: Navigate to `/api/test-notification`
2. **System Notifications**: Add a new system to your map via the map API
3. **Character Notifications**: Add a new character to your tracking list
4. **Service Status**: Restart the service or trigger a connection error

## Discord Channel Configuration

Notifications can be sent to specific Discord channels based on type:

- `DISCORD_CHANNEL_ID`: Main Discord channel ID for all notifications
- `DISCORD_KILL_CHANNEL_ID`: Channel for kill notifications (defaults to main channel)
- `DISCORD_SYSTEM_CHANNEL_ID`: Channel for system tracking notifications (defaults to main channel)
- `DISCORD_CHARACTER_CHANNEL_ID`: Channel for character tracking notifications (defaults to main channel)

Each notification checks for a feature-specific channel first. If not found, it falls back to the main channel defined by `DISCORD_CHANNEL_ID`. This allows you to:

1. Send all notifications to a single channel by only setting `DISCORD_CHANNEL_ID`
2. Send specific notification types to different channels by setting the corresponding channel variables
3. Mix and match, with some notification types going to dedicated channels and others falling back to the main channel

## Visual Examples

### Kill Notification Example

```
[KILL NOTIFICATION]
Victim: John Doe (ALLIANCE)
Ship: Vindicator
System: J123456 (C5)
Value: 1,250,000,000 ISK
Final Blow: Jane Smith (ENEMIES)
```

### System Notification Example

```
[SYSTEM NOTIFICATION]
System: J123456 (Home)
Class: C3 Wolf-Rayet
Region: A-R00001
Statics: N062 (C5), E545 (NS)
Recent Activity: 3 kills in the last 24 hours
```

### Character Notification Example

```
[CHARACTER NOTIFICATION]
Character: John Doe
Corporation: CORP [ALLIANCE]
Character ID: 12345678
```
