---
layout: default
title: Notification Types - Wanderer Notifier
description: Learn about the different types of notifications provided by Wanderer Notifier
---

# Notification Types

Wanderer Notifier supports three main notification types, each tailored based on your map subscription status.

## Kill Notifications

When a kill occurs in a tracked system or involves a tracked character:

- **With Premium Map Subscription:**  
  Receives a rich embed that includes:
  - Ship thumbnail image
  - Detailed information about both victim and attacker
  - Links to zKillboard profiles
  - Ship type details
  - ISK value of the kill
  - Corporation logos
  - A clickable link on the final blow character to zKillboard

![Premium Kill Notification Example](./assets/images/paid-kill.png)

- **With Free Map:**  
  Displays a basic text notification containing:
  - Victim name
  - Ship type lost
  - System name

![Free Kill Notification Example](./assets/images/free-kill.png)

## Character Tracking Notifications

When a new character is added to your tracked list:

- **With Premium Map Subscription:**  
  You get a rich embed featuring:
  - Character portrait
  - Corporation details
  - Direct link to the zKillboard profile
  - Formatted timestamp

![Premium Character Notification Example](./assets/images/paid-character.png)

- **With Free Map:**  
  Receives a simple text notification that includes:
  - Character name
  - Corporation name (if available)

![Free Character Notification Example](./assets/images/free-character.png)

## System Notifications

When a new system is discovered or added to your map:

- **With Premium Map Subscription:**  
  Shows a rich embed with:
  - System name (including aliases/temporary names)
  - System type icon
  - Region information or wormhole statics
  - Security status
  - Recent kills in the system
  - Links to zKillboard and Dotlan

![Premium System Notification Example](./assets/images/paid-system.png)

- **With Free Map:**  
  Provides a basic text notification including:
  - Original system name (for wormholes)
  - System name (for k-space)

![Free System Notification Example](./assets/images/free-system.png)

## Web Dashboard

Wanderer Notifier includes a web dashboard that provides real-time insights into your notification system:

- **Access:** Visit `http://localhost:4000` to view the dashboard.
- **System Status:** Monitor system details, subscription information, and notification statistics.
- **Resource Monitoring:** Keep an eye on resource usage and feature availability.
- **Notification Testing:** Test notifications directly from the dashboard.

Premium map subscribers also gain access to detailed statistics and advanced visualization tools.

![Dashboard](./assets/images/dashboard.png)

## Configuration Options

Customize your notification experience with several configuration options available through environment variables.

### Notification Control Variables

- **ENABLE_KILL_NOTIFICATIONS:** Enable/disable kill notifications (default: true).
- **ENABLE_CHARACTER_TRACKING:** Enable/disable character tracking (default: true).
- **ENABLE_CHARACTER_NOTIFICATIONS:** Enable/disable notifications when new characters are added (default: true).
- **ENABLE_SYSTEM_NOTIFICATIONS:** Enable/disable system notifications (default: true).

> **Note:**  
> - **Character Tracking:** Determines whether the application monitors characters.  
> - **Character Notifications:** Controls whether you receive Discord alerts when new characters are added.

To disable a notification type, set the corresponding variable to `false` or `0` in your `.env` file:

```dotenv
# Example: Disable kill notifications while keeping other notifications enabled
ENABLE_KILL_NOTIFICATIONS=false
```

## Troubleshooting

If you encounter issues with Wanderer Notifier, here are solutions to common problems:

### No Notifications Appearing

1. **Check Bot Permissions:** Ensure your bot has the "Send Messages" and "Embed Links" permissions in the Discord channel.
2. **Verify Channel ID:** Double-check your DISCORD_CHANNEL_ID in the .env file.
3. **Check Container Logs:** Run `docker logs wanderer_notifier` to see if there are any error messages.
4. **Test API Connection:** Visit `http://localhost:4000/health` to verify the service is running.

### Connection Issues

1. **Network Configuration:** Ensure port 4000 is not blocked by your firewall.
2. **Docker Status:** Run `docker ps` to verify the container is running.
3. **Restart Service:** Try `docker-compose restart` to refresh the connection.

### Subscription Not Recognized

1. **Check Map Token:** Ensure your MAP_TOKEN is correct and associated with your map.
2. **Verify LICENSE_KEY:** Make sure you've entered the correct map subscription key in your .env file.
3. **Verify Status:** Check the dashboard at `http://localhost:4000` to see subscription status.
4. **Restart After Subscribing:** If you've recently subscribed, restart the notifier with `docker-compose restart`.

For additional support, join our [Discord community](https://discord.gg/wanderer) or email support@wanderer.ltd.

[Back to home](./index.html) | [See subscription options](./license.html) | [View on GitHub](https://github.com/yourusername/wanderer-notifier) 