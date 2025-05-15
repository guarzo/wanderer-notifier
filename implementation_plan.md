# Killmail Notification System Enhancement Implementation Plan

## Overview

This plan outlines the implementation of a new killmail notification system that introduces chain kill mode and separate channels for character and system kills.

## Pre-Implementation: Environment Variable Cleanup ✅

### 1. Review Current Environment Variables ✅

- Analyze all environment variables in:
  - `config/config.exs`
  - `config/runtime.exs`
  - `lib/wanderer_notifier/config_provider.ex`

### 2. Environment Variable Status ✅

- Variables to keep (currently in use):

  - `WANDERER_DISCORD_SYSTEM_CHANNEL_ID` - Used in notification routing
  - `WANDERER_DISCORD_CHARACTER_CHANNEL_ID` - Used in notification routing
  - `WANDERER_CHARACTER_NOTIFICATIONS_ENABLED` - Used in character notification logic
  - `WANDERER_SYSTEM_NOTIFICATIONS_ENABLED` - Used in system notification logic
  - `WANDERER_KILL_NOTIFICATIONS_ENABLED` - Used in kill notification logic
  - `WANDERER_DISABLE_STATUS_MESSAGES` - Used in status message handling
  - `WANDERER_FEATURE_TRACK_KSPACE` - Used in system tracking logic

- Variables to remove (unused or redundant):
  - `WANDERER_DISCORD_KILL_CHANNEL_ID` - Redundant with new channel system
  - `WANDERER_CHARACTER_TRACKING_ENABLED` - Redundant with character notifications
  - `WANDERER_SYSTEM_TRACKING_ENABLED` - Redundant with system notifications

### 3. Cleanup Process ✅

- Remove unused variables from configuration files
- Update documentation to reflect removed variables
- Add deprecation warnings for removed variables
- Create migration guide for users who might be using removed variables

### 4. Documentation Updates ✅

- Update README.md with current environment variable list
- Add clear descriptions for each variable's purpose
- Document any changes to variable names or behavior

## New Environment Variables ✅

- `WANDERER_CHAIN_KILLS_MODE`: Controls whether to use the new chain kills notification system
- `WANDERER_ENABLE_CHARACTER_KILL_NOTIFICATIONS`: Controls whether to send notifications for character-related kills
- `WANDERER_ENABLE_SYSTEM_KILL_NOTIFICATIONS`: Controls whether to send notifications for system-related kills
- `WANDERER_DISCORD_CHARACTER_KILL_CHANNEL_ID`: Discord channel ID for character kill notifications
- `WANDERER_DISCORD_SYSTEM_KILL_CHANNEL_ID`: Discord channel ID for system kill notifications

## Implementation Steps

### 1. Configuration Updates ✅

- Add new environment variables to the configuration system
- Update configuration validation to handle new variables
- Add helper functions to check chain kills mode and character kill notifications status

### 2. Killmail Notification Logic Updates ✅

- Modify `WandererNotifier.Notifications.Determiner.Kill` to:
  - Check for chain kills mode
  - Determine if a kill is character-related or system-related
  - Apply appropriate notification rules based on mode and type

### 3. Discord Notification Channel Routing ✅

- Update `WandererNotifier.Notifications.Dispatcher` to:
  - Add new notification types for character and system kills
  - Implement channel routing logic based on kill type
  - Handle fallback to default channel when specific channels are not configured

### 4. Notification Formatter Updates ✅

- Add a wrapper function in `WandererNotifier.Notifications.Formatters.Killmail` to:
  - Maintain consistent notification format for both types
  - Add metadata for kill type (character vs system)
  - Allow for future format customization without changing the core logic

### 5. Testing ✅

- Add new test cases for:
  - Chain kills mode functionality
  - Character kill notification routing
  - System kill notification routing
  - Environment variable handling
  - Channel fallback behavior

## Code Changes Required

### Configuration Module ✅

```elixir
# Add to config.exs or similar
config :wanderer_notifier,
  chain_kills_mode: System.get_env("WANDERER_CHAIN_KILLS_MODE") == "true",
  enable_character_kill_notifications: System.get_env("WANDERER_ENABLE_CHARACTER_KILL_NOTIFICATIONS") == "true",
  discord_character_kill_channel_id: System.get_env("WANDERER_DISCORD_CHARACTER_KILL_CHANNEL_ID"),
  discord_system_kill_channel_id: System.get_env("WANDERER_DISCORD_SYSTEM_KILL_CHANNEL_ID")
```

### Kill Determiner Updates ✅

```elixir
# Add to KillDeterminer
def is_character_kill?(killmail) do
  # Check if kill involves tracked character as attacker or victim
end

def is_system_kill?(killmail) do
  # Check if kill is in tracked system
end
```

### Notification Dispatcher Updates ✅

```elixir
# Add to Dispatcher
defp route_kill_notification(killmail) do
  cond do
    is_character_kill?(killmail) && character_kills_enabled?() ->
      :character_kill
    is_system_kill?(killmail) ->
      :system_kill
    true ->
      :default
  end
end
```

### Notification Formatter Updates ✅

```elixir
# Add to KillmailFormatter
def format_kill_notification(killmail) do
  # Get base notification format
  base_notification = format_base_kill_notification(killmail)

  # Add kill type metadata
  kill_type = determine_kill_type(killmail)

  # Return enhanced notification with type info
  Map.put(base_notification, :kill_type, kill_type)
end

defp determine_kill_type(killmail) do
  cond do
    is_character_kill?(killmail) -> :character_kill
    is_system_kill?(killmail) -> :system_kill
    true -> :default
  end
end
```

## Testing Strategy ✅

### Unit Tests

1. Test chain kills mode configuration ✅
2. Test character kill notification routing ✅
3. Test system kill notification routing ✅
4. Test channel fallback behavior ✅
5. Test notification formatting with kill type metadata ✅

### Integration Tests

1. Test end-to-end notification flow with chain kills mode ✅
2. Test notification delivery to correct channels ✅
3. Test environment variable handling ✅
4. Test error cases and fallback behavior ✅

## Migration Plan

1. Deploy configuration changes
2. Deploy code changes
3. Monitor notification delivery
4. Verify channel routing
5. Check for any missed notifications

## Rollback Plan

1. Revert environment variables
2. Revert code changes
3. Restore original notification behavior

## Success Criteria

- Killmail notifications are correctly routed based on type ✅
- Character kill notifications respect the enable flag ✅
- System kill notifications are sent to the correct channel ✅
- Fallback to default channel works as expected ✅
- No duplicate notifications are sent ✅
- Performance impact is minimal ✅
- Kill type metadata is correctly included in notifications ✅

## Next Steps

1. Deploy the changes to staging environment
2. Monitor the system for any issues
3. Gather feedback from users
4. Plan for production deployment
