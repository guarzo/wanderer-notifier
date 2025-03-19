---
layout: default
title: Map Subscription Features - Wanderer Notifier
description: Comparison of features between free and premium map subscriptions for Wanderer Notifier
---

# Map Subscription Features & Limitations

Wanderer Notifier offers enhanced functionality with a premium map subscription while still providing robust features for free maps.

## Free Version Features

- **Core Notifications:** Basic text notifications for systems and characters.
- **Web Dashboard:** View system status and subscription information.
- **Unlimited Tracking:** Track an unlimited number of systems and characters.
- **Notification History:** 24-hour retention of notification history.

## Premium Map Subscription Enhancements

- **Rich Notifications:** Enhanced embeds with images, links, and detailed data.
- **Interactive Elements:** Clickable links to zKillboard profiles and additional resources.
- **Enhanced System Information:** Comprehensive data including region details, security status, and wormhole statics.
- **Recent Activity:** Access to recent kill data in newly mapped systems.
- **Upcoming Features:** Daily reporting on tracked character activity, structure notifications, ACL notifications, and Slack notifications.

## How to Subscribe

To unlock the enhanced features of Wanderer Notifier:

1. Visit our [Map Subscriptions page](/map-subscriptions) to learn about subscription options
2. Subscribe to any premium map tier to receive your map subscription key
3. Add your map subscription key to the LICENSE_KEY field in your `.env` file:
   ```dotenv
   LICENSE_KEY=your_map_license_key
   ```
4. Restart the notifier to apply your subscription benefits

For more details on map subscription tiers and pricing, see our [complete guide to map subscriptions](/map-subscriptions).

## Feature Comparison

| Feature                  | Free Map | Premium Map Subscription |
|--------------------------|----------|--------------------------|
| Kill Tracking            | Unlimited| Unlimited                |
| System Tracking          | Unlimited| Unlimited                |
| Character Tracking       | Unlimited| Unlimited                |
| Notification Format      | Basic Text| Rich Embeds             |
| System Info Detail       | Basic    | Comprehensive            |
| Dashboard Features       | Basic    | Advanced                 |
| Support                  | Community| Priority                 |

## Updating Wanderer Notifier

To ensure you have the latest features and security updates, periodically update your Wanderer Notifier installation:

### Automatic Updates

The Docker image is configured to check for updates daily. To manually trigger an update:

```bash
# Navigate to your wanderer-notifier directory
cd wanderer-notifier

# Pull the latest image
docker-compose pull

# Restart the container with the new image
docker-compose up -d
```

### Update Notifications

When significant updates are available, you'll receive a notification in your Discord channel. These updates may include:

- New notification types
- Enhanced visualization features
- Security improvements
- Bug fixes

### Preserving Your Configuration

Updates preserve your existing configuration and data. Your `.env` file and tracked entities will remain intact through the update process.

[Back to home](./index.html) | [Learn about notification types](./notifications.html) | [View on GitHub](https://github.com/yourusername/wanderer-notifier) 