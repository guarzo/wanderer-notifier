# WandererNotifier License Features

This document outlines the functionality available in WandererNotifier based on license status.

## License Status Overview

WandererNotifier operates with two primary license states:
1. **Free/Invalid License**: Basic functionality with limitations
2. **Valid License**: Full functionality with standard features

## Feature Comparison

| Feature | Free/Invalid License | Valid License |
|---------|---------------------|---------------|
| Basic Notifications | ✅ | ✅ |
| Web Dashboard | Basic | Full |
| Tracked Systems | Limited (5 max) | Unlimited |
| Tracked Characters | Limited (10 max) | Unlimited |
| Backup Kills Processing | ❌ | ✅ |
| Notification History | 24 hours | 72 hours |

## Core Functionality (Available with Free/Invalid License)

### Basic Notifications
- **Basic kill notifications**: Receive notifications about kills without filtering
- **Simple notification format**: Basic text-based notifications
- **Limited notification history**: Only 24 hours of notification history is stored

### Basic Web Dashboard
- **System status monitoring**: View application uptime and websocket connection status
- **License status display**: See current license status and validation information
- **Basic statistics**: View simple notification counts

### Limited Tracking
- **Restricted system tracking**: Track up to 5 wormhole systems
- **Restricted character tracking**: Track up to 10 characters
- **Resource usage warnings**: Clear indicators when approaching limits

## Valid License Functionality

### Enhanced Notifications
- **Unlimited systems tracking**: Receive notifications for kills in any number of tracked systems
- **Unlimited characters tracking**: Track any number of characters for notifications
- **New system/character notifications**: Get notified when new entities are added to tracking
- **Extended notification history**: Access to 72 hours of notification history

### Full Web Dashboard
- **Enhanced statistics**: More detailed statistics about notifications and system activity
- **Resource usage visualization**: Visual indicators for resource usage
- **Feature status display**: Clear indication of which features are enabled
- **System and character details**: More comprehensive information about tracked entities

### Backup Kills Processing
- **Historical kill retrieval**: Process kills from the last 24 hours that might have been missed
- **Backup data source**: Use the map API as a secondary source for kill data
- **Kill deduplication**: Ensure the same kill isn't notified multiple times

## Resource Limitations

| Resource | Free/Invalid License | Valid License |
|----------|---------------------|---------------|
| Tracked Systems | 5 maximum | Unlimited |
| Tracked Characters | 10 maximum | Unlimited |
| Notification History | 24 hours | 72 hours |

## User Experience

### Free/Invalid License Experience
- Basic functionality is available, but with clear limitations
- Regular reminders about license status and upgrade benefits
- Resource usage warnings as limits are approached

### Valid License Experience
- Full access to all standard features without tracking limits
- Enhanced dashboard with more detailed information
- Comprehensive notification system for tracked systems and characters
- Backup kill processing ensures no important kills are missed

## Obtaining a Valid License

To upgrade to a valid license and unlock all features:
1. Visit the license portal at [license.wanderer-notifier.com](https://license.wanderer-notifier.com)
2. Purchase a license key
3. Add the license key to your environment configuration (and optionally set a custom BOT_ID if needed)
4. Restart the application to activate the license 