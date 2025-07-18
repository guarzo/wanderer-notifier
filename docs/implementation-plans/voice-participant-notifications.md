# Voice Participant Notifications Implementation Plan

## Overview

This plan outlines how to modify the Wanderer Notifier system to notify all active voice participants instead of using `@here` for system notifications.

## Current State

The system currently uses `@here` mentions for priority system notifications in `WandererNotifier.NotificationService.send_system_notification/2` at `/workspace/lib/wanderer_notifier/notification_service.ex:196-202`.

**Current notification targeting logic:**
- **Priority systems**: Always get `@here` mentions regardless of notification settings
- **Regular systems**: Get standard notifications without `@here` when enabled
- **Priority-only mode**: Only priority systems generate notifications

**Key limitation**: No existing voice channel or participant tracking functionality in the codebase.

## Required Changes

### 1. Configuration Updates

**Add to `WandererNotifier.Config` module:**
```elixir
# Discord guild configuration
def discord_guild_id, do: get(:discord_guild_id)
```

**New environment variables:**
- `DISCORD_GUILD_ID` - The Discord server/guild ID to monitor for voice participants

### 2. New Voice Participant Module

**Create `WandererNotifier.Discord.VoiceParticipants`:**

Key responsibilities:
- Query guild voice channels (excluding AFK channel)
- Collect active voice participants from `guild.voice_states`
- Filter out bot users
- Build individual user mentions as `<@user_id>`
- Handle cases with no participants

**Reference implementation** (from sprint docs):
```elixir
defmodule WandererNotifier.Discord.VoiceParticipants do
  alias Nostrum.Cache.{GuildCache, GuildChannelCache}
  alias Nostrum.Struct.{Channel, VoiceState}
  
  def get_active_voice_mentions(guild_id) do
    guild = GuildCache.get!(guild_id)
    
    # Find all voice channels except AFK
    voice_channel_ids =
      GuildChannelCache.get_all(guild_id)
      |> Enum.filter(&voice_channel?/1)
      |> Enum.reject(&(&1.id == guild.afk_channel_id))
      |> Enum.map(& &1.id)
    
    # Gather voice participants
    guild.voice_states
    |> Map.values()
    |> Enum.filter(fn %VoiceState{channel_id: cid, user_id: uid} ->
      cid in voice_channel_ids and not user_is_bot?(uid)
    end)
    |> Enum.map(&"<@#{&1.user_id}>")
    |> Enum.uniq()
  end
  
  # Helper functions for channel type and bot detection
end
```

### 3. Notification Service Modifications

**Update `WandererNotifier.NotificationService.send_system_notification/2`:**

Current logic at lines 196-202:
```elixir
message_content =
  if is_priority_system do
    "@here #{message_content}"
  else
    message_content
  end
```

**New logic:**
```elixir
message_content =
  if is_priority_system do
    case get_voice_participant_mentions() do
      [] when fallback_to_here_enabled?() -> "@here #{message_content}"
      [] -> "#{message_content}"  # No voice participants, no fallback
      mentions -> "#{Enum.join(mentions, " ")} #{message_content}"
    end
  else
    message_content
  end
```

### 4. Discord Client Enhancements

**Update `WandererNotifier.Discord.NeoClient`:**
- Add guild cache access methods
- Add voice state query functions  
- Add user bot status checking utilities

### 5. New Configuration Options

**Feature flags to add:**
- `VOICE_PARTICIPANT_NOTIFICATIONS_ENABLED` - Enable voice-only notifications (default: false)
- `FALLBACK_TO_HERE_ENABLED` - Fallback to `@here` when no voice participants (default: true)
- `EXCLUDE_AFK_CHANNEL` - Exclude AFK channel from voice participant queries (default: true)

### 6. Priority System Integration

**Enhanced priority logic options:**
- Priority systems could notify ALL users vs voice-only for regular systems
- Option to always use `@here` for priority systems regardless of voice settings
- Separate voice notification behavior for priority vs regular systems

## Implementation Tasks

### High Priority
1. **Add Discord guild ID configuration** to support voice participant queries
2. **Create VoiceParticipants module** to query active voice channel members
3. **Update NotificationService** to use voice participants instead of @here

### Medium Priority
4. **Add configuration flags** for voice notification behavior
5. **Enhance NeoClient** with guild cache and voice state query methods

## Benefits

1. **Targeted notifications** - Only notify users actually available in voice
2. **Reduced notification fatigue** - No unnecessary pings for offline users
3. **Better user experience** - More relevant notifications for active participants
4. **Backward compatibility** - Configurable fallback to `@here` behavior

## Migration Strategy

1. **Phase 1**: Add configuration and voice participant module (backward compatible)
2. **Phase 2**: Update notification service with feature flag (default disabled)
3. **Phase 3**: Enable voice participant notifications by default
4. **Phase 4**: Deprecate `@here` fallback option (optional)

## Testing Considerations

- Test with empty voice channels
- Test with only bot users in voice
- Test with mixed bot/human users
- Test AFK channel exclusion
- Test fallback behavior when voice participant lookup fails
- Test configuration flag combinations

## Technical Notes

- Uses existing Nostrum guild caches (no additional API calls)
- Maintains current notification architecture and patterns
- Leverages existing priority system logic
- Preserves all current notification features and formatting