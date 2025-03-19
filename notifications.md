---
layout: default
title: Notification Types - Wanderer Notifier
description: Learn about the different types of notifications provided by Wanderer Notifier
---

# Notification Types

Wanderer Notifier provides three main types of notifications, each with different presentation based on your license status:

## Kill Notifications

When a kill occurs in a tracked system or involves a tracked character:

- **With License**: Rich embed format with:
  - Ship thumbnail image
  - Detailed information about victim and attacker
  - Links to zKillboard profiles
  - Ship type details
  - ISK value of the kill
  - Corporation logos

![Licensed Kill Notification Example](./assets/images/paid-kill.png)

- **Without License**: Basic text notification with essential information:
  - System name
  - Victim name
  - Ship type lost

![Free Kill Notification Example](./assets/images/free-kill.png)

## Character Tracking Notifications

When a new character is added to your tracked list:

- **With License**: Rich embed with:
  - Character portrait
  - Corporation details
  - Direct link to zKillboard profile
  - Formatted timestamp

![Licensed Character Notification Example](./assets/images/paid-character.png)

- **Without License**: Simple text notification with character name

![Free Character Notification Example](./assets/images/free-character.png)

## System Notifications

When a new system is discovered or added to your map:

- **With License**: Rich embed with:
  - System name (including any aliases/temporary names)
  - Link to zKillboard for the system
  - Formatted timestamp

![Licensed System Notification Example](./assets/images/paid-system.png)

- **Without License**: Basic text notification with system name

![Free System Notification Example](./assets/images/free-system.png)

## Web Dashboard

Wanderer Notifier includes a web dashboard that provides insights into your notification system:

1. Access the dashboard at `http://your-server-ip:4000`
2. View system status, license information, and notification statistics
3. Monitor resource usage and feature availability

The dashboard automatically refreshes every 30 seconds to provide up-to-date information. Licensed users gain access to additional dashboard features including detailed statistics and visualization tools.

## Configuration Options

Wanderer Notifier offers several configuration options to customize your notification experience:

### Notification Control

You can enable or disable specific notification types using these environment variables:

- **ENABLE_KILL_NOTIFICATIONS**: Enable/disable kill notifications (default: true)
- **ENABLE_CHARACTER_TRACKING**: Enable/disable the tracking of characters (default: true)
- **ENABLE_CHARACTER_NOTIFICATIONS**: Enable/disable notifications when new characters are added (default: true)
- **ENABLE_SYSTEM_NOTIFICATIONS**: Enable/disable notifications when new systems are added (default: true)

The difference between character tracking and character notifications:
- **Character Tracking**: Controls whether the application monitors characters at all
- **Character Notifications**: Controls whether you receive Discord alerts when new characters are added to tracking

To disable any notification type, set the corresponding variable to `false` or `0` in your `.env` file:

```dotenv
# Example: Disable kill notifications but keep character and system notifications
ENABLE_KILL_NOTIFICATIONS=false
```

These settings can be changed without restarting the application by updating your environment variables and reloading the configuration.

[Back to home](./index.html) | [See license comparison](./license.html) | [View on GitHub](https://github.com/yourusername/wanderer-notifier) 