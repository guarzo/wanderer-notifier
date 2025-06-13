# Discord Bot Setup Guide

This guide walks you through setting up the WandererNotifier Discord bot with the new `/notifier` system commands.

## 🔧 Prerequisites

1. **Discord Bot**: You need a Discord bot token and application ID
2. **Environment**: Elixir 1.18+ and the WandererNotifier application
3. **Permissions**: Bot needs slash command permissions in your Discord server

## 📋 Environment Variables

Set these environment variables before starting the application:

```bash
# Required for Discord bot functionality
export DISCORD_BOT_TOKEN="your_bot_token_here"
export DISCORD_APPLICATION_ID="your_application_id_here"

# Required for basic functionality (existing)
export DISCORD_CHANNEL_ID="your_default_channel_id"
export MAP_API_KEY="your_map_api_key"
export NOTIFIER_API_TOKEN="your_api_token"
export LICENSE_KEY="your_license_key"

# Optional: Separate channel for system notifications
export DISCORD_SYSTEM_CHANNEL_ID="your_system_channel_id"
```

## 🚀 Quick Start

1. **Start the application:**
   ```bash
   mix run --no-halt
   ```

2. **Verify bot is online:**
   - Check Discord - your bot should show as online
   - Check logs for "Successfully registered Discord slash commands"

3. **Test slash commands in Discord:**
   ```
   /notifier status
   /notifier system Jita action:add-priority
   /notifier system Jita action:remove-priority
   ```

## 🎯 Available Commands

### `/notifier status`
Shows current bot status and configuration:
- Number of priority systems
- Command usage statistics
- Feature toggle states

### `/notifier system <system_name>`
Manages system tracking and priority settings:

**Actions:**
- `add-priority` - Adds system to priority list (gets @here notifications)
- `remove-priority` - Removes system from priority list
- `track` - Basic system tracking (acknowledgment only)
- `untrack` - Stop tracking system (acknowledgment only)

**Examples:**
```
/notifier system Jita action:add-priority
/notifier system Amarr action:remove-priority
/notifier system Dodixie action:track
```

## 💡 Priority System Logic

Priority systems receive special treatment with three notification modes:

### Normal Mode (default)
- ✅ **Notifications Enabled + Priority System**: @here notification  
- ✅ **Notifications Enabled + Regular System**: Normal notification
- ✅ **Notifications Disabled + Priority System**: @here notification (overrides disabled setting)
- ❌ **Notifications Disabled + Regular System**: No notification

### Priority-Only Mode (`PRIORITY_SYSTEMS_ONLY=true`)
- ✅ **Priority System**: @here notification (always)
- ❌ **Regular System**: No notification (regardless of system notifications setting)

This gives you complete control over which systems generate notifications.

## 📊 Data Persistence

The bot persists data between restarts:

- **Priority Systems**: Stored in `priv/persistent_values.bin`
- **Command History**: Stored in `priv/command_log.bin`
- **Files are created automatically** in the application's priv directory

## 🔧 Configuration Options

### Feature Toggles
Control notification behavior via environment variables:

```bash
# System notifications (can be overridden by priority systems)
export SYSTEM_NOTIFICATIONS_ENABLED=true

# Priority-only mode: only send notifications for priority systems
export PRIORITY_SYSTEMS_ONLY=false

# Other notification types  
export CHARACTER_NOTIFICATIONS_ENABLED=true
export KILL_NOTIFICATIONS_ENABLED=true
```

### Channel Configuration
Direct different notification types to specific channels:

```bash
export DISCORD_CHANNEL_ID="default_channel"           # Default fallback
export DISCORD_SYSTEM_CHANNEL_ID="system_channel"     # System notifications
export DISCORD_CHARACTER_CHANNEL_ID="character_channel" # Character notifications
```

## 🧪 Testing Your Setup

1. **Check bot permissions:**
   ```
   /notifier status
   ```
   Should return current status without errors.

2. **Test priority system:**
   ```
   /notifier system TestSystem action:add-priority
   ```
   Should confirm system added to priority list.

3. **Verify persistence:**
   - Add a priority system
   - Restart the application
   - Check `/notifier status` - priority system should still be there

## 🚨 Troubleshooting

### Bot not responding to commands
- ✅ Check `DISCORD_BOT_TOKEN` is correct
- ✅ Check `DISCORD_APPLICATION_ID` is correct
- ✅ Verify bot has "Use Slash Commands" permission
- ✅ Check application logs for "Successfully registered Discord slash commands"

### Commands not appearing in Discord
- ✅ Bot needs "applications.commands" scope
- ✅ Wait 1-2 minutes for Discord to sync commands globally
- ✅ Try logging out and back into Discord

### Permission errors
- ✅ Bot needs "Send Messages" permission in target channels
- ✅ Bot needs "Use Slash Commands" permission
- ✅ Bot needs "Mention Everyone" permission for @here notifications

### Application startup errors
- ✅ Check all required environment variables are set
- ✅ Verify Discord token format (should start with your bot ID)
- ✅ Check application ID is numeric

## 📝 Logs to Monitor

Watch for these log messages:

```bash
# Successful startup
[info] Discord consumer ready, registering slash commands
[info] Successfully registered Discord slash commands

# Command usage
[info] Discord command executed (type: system, param: Jita, user: username)
[info] Added priority system (system: Jita, hash: 40432253)

# Notifications
[info] Sending system notification (system: Jita, priority: true)
[info] Sending priority system notification despite disabled notifications
```

## 🔄 Next Steps

Once system commands are working:
1. Test with real EVE Online system names
2. Configure notification channels for your server
3. Set up priority systems for important trade hubs
4. Train your users on the available commands

## 📞 Support

If you encounter issues:
1. Check the application logs for error messages
2. Verify all environment variables are correctly set
3. Test with a simple `/notifier status` command first
4. Check Discord Developer Portal for bot configuration

The system is designed to be resilient - data persists between restarts and the bot will continue working even if some features are disabled.