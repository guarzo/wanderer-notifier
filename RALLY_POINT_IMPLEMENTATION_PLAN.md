# Rally Point Notification Implementation Plan

## Overview
This plan outlines the implementation of rally point notifications from the Wanderer mapper SSE feed. Rally points are coordination points where players can form up, and the notifications will ping a specific Discord group when created.

## Event Types
- `rally_point_added`: When a rally point is created

## Implementation Steps

### 1. Environment Configuration

#### Add new environment variables:
```elixir
# config/runtime.exs
config :wanderer_notifier,
  discord_rally_channel_id: System.get_env("DISCORD_RALLY_CHANNEL_ID") || System.get_env("DISCORD_CHANNEL_ID"),
  discord_rally_group_id: System.get_env("DISCORD_RALLY_GROUP_ID"),
  rally_notifications_enabled: System.get_env("RALLY_NOTIFICATIONS_ENABLED", "true") == "true"
```

#### Update Config module:
```elixir
# lib/wanderer_notifier/shared/config.ex
def discord_rally_channel_id, do: get(:discord_rally_channel_id) || discord_channel_id()
def discord_rally_group_id, do: get(:discord_rally_group_id)
def rally_notifications_enabled?, do: get(:rally_notifications_enabled, true)
```

### 2. SSE Event Handling

#### Update Event Processor:
```elixir
# lib/wanderer_notifier/map/event_processor.ex

# Add to categorize_event/1
defp categorize_event(%{type: "rally_point_added"}), do: :rally

# Add handler function
def handle_rally_event(%{type: "rally_point_added", payload: payload} = event) do
  Logger.info("Rally point created", 
    system: payload["system_name"], 
    character: payload["character_name"],
    category: :rally
  )
  
  rally_point = %{
    id: payload["rally_point_id"],
    system_id: payload["solar_system_id"],
    system_name: payload["system_name"],
    character_name: payload["character_name"],
    character_eve_id: payload["character_eve_id"],
    message: payload["message"],
    created_at: payload["created_at"]
  }
  
  # Trigger notification
  NotificationService.notify(:rally_point, rally_point)
end
```

### 3. Notification Determination

#### Update Unified Determiner:
```elixir
# lib/wanderer_notifier/domains/notifications/determiner.ex

def should_notify?(:rally_point, rally_data) do
  cond do
    not Config.notifications_enabled?() -> 
      {:skip, :notifications_disabled}
      
    not Config.rally_notifications_enabled?() -> 
      {:skip, :rally_notifications_disabled}
      
    true ->
      # Check deduplication
      case Deduplication.check(:rally_point, rally_data.id) do
        {:ok, :new} -> 
          {:notify, :rally_point_created}
        {:ok, :duplicate} -> 
          {:skip, :duplicate}
        {:error, _} -> 
          {:notify, :rally_point_created}
      end
  end
end
```

### 4. Notification Formatting

#### Update NotificationFormatter:
```elixir
# lib/wanderer_notifier/domains/notifications/formatters/notification_formatter.ex

def format_notification(%{} = rally_point) when is_map_key(rally_point, :rally_point_id) do
  format_rally_point_notification(rally_point)
end

defp format_rally_point_notification(rally_point) do
  %{
    type: :rally_point,
    title: "Rally Point Created",
    description: "#{rally_point.character_name} has created a rally point in **#{rally_point.system_name}**",
    color: 0x00FF00,  # Green
    fields: [
      %{
        name: "System",
        value: rally_point.system_name,
        inline: true
      },
      %{
        name: "Created By",
        value: rally_point.character_name,
        inline: true
      },
      %{
        name: "Message",
        value: rally_point.message || "No message provided",
        inline: false
      }
    ],
    footer: %{
      text: "Rally Point Notification",
      icon_url: nil
    },
    timestamp: rally_point[:created_at] || DateTime.utc_now()
  }
end
```

### 5. Discord Notification Handling

#### Update Discord Notifier:
```elixir
# lib/wanderer_notifier/domains/notifications/discord/notifier.ex

def send_notification(%{type: :rally_point} = notification, rally_data) do
  channel_id = Config.discord_rally_channel_id()
  
  # Add group ping for rally points
  content = build_rally_content(rally_data)
  
  notification_with_content = Map.put(notification, :content, content)
  
  case NeoClient.send_embed(notification_with_content, channel_id) do
    {:ok, _} -> 
      Logger.info("Rally point notification sent", 
        system: rally_data.system_name,
        type: rally_data.type,
        category: :discord
      )
      :ok
      
    {:error, reason} ->
      Logger.error("Failed to send rally point notification", 
        reason: inspect(reason),
        category: :discord
      )
      {:error, reason}
  end
end

defp build_rally_content(rally_data) do
  group_id = Config.discord_rally_group_id()
  
  if group_id do
    "<@&#{group_id}> Rally point created!"
  else
    "Rally point created!"
  end
end
```

### 6. Testing Strategy

#### Unit Tests:
1. **SSE Event Parsing**: Test parsing of rally_point_added events
2. **Event Processor**: Test routing and handling of rally events
3. **Determiner**: Test notification logic and deduplication
4. **Formatter**: Test formatting of rally point notifications
5. **Discord Notifier**: Test group ping and channel selection

#### Integration Tests:
1. Full flow from SSE event to Discord notification
2. Test fallback to default channel when DISCORD_RALLY_CHANNEL_ID not set
3. Test behavior when DISCORD_RALLY_GROUP_ID not configured

#### Test Fixtures:
```elixir
# test/support/fixtures/rally_point_fixtures.ex
defmodule WandererNotifier.RallyPointFixtures do
  def rally_point_added_payload do
    %{
      "rally_point_id" => "550e8400-e29b-41d4-a716-446655440000",
      "solar_system_id" => 30000142,
      "system_id" => "660e8400-e29b-41d4-a716-446655440000",
      "character_id" => "770e8400-e29b-41d4-a716-446655440000",
      "character_name" => "Test Pilot",
      "character_eve_id" => 95123456,
      "system_name" => "Jita",
      "message" => "Form up for fleet ops!",
      "created_at" => "2024-01-01T12:00:00Z"
    }
  end
end
```

### 7. Expected Discord Output

```
@RallyGroup Rally point created!

[Embed]
Title: Rally Point Created
Description: Test Pilot has created a rally point in **Jita**
Color: Green (0x00FF00)

Fields:
- System: Jita (inline)
- Created By: Test Pilot (inline)
- Message: Form up for fleet ops! (not inline)

Footer: Rally Point Notification
Timestamp: 2024-01-01T12:00:00Z
```

### 8. Configuration Summary

New environment variables:
- `DISCORD_RALLY_CHANNEL_ID` - Dedicated channel for rally notifications (optional)
- `DISCORD_RALLY_GROUP_ID` - Discord role ID to ping for rally points (optional)
- `RALLY_NOTIFICATIONS_ENABLED` - Toggle for rally notifications (default: true)

### 9. Implementation Order

1. Add environment configuration
2. Update SSE event processor to handle rally events
3. Implement determiner logic with deduplication
4. Create formatter for rally notifications
5. Update Discord notifier for group pings
6. Write comprehensive tests
7. Update documentation

### 10. Future Enhancements

- Add support for rally point expiration times
- Include wormhole chain information if available
- Add Discord slash command to create rally points
- Support for multiple rally points per system
- Rally point history tracking
- Add support for rally_point_removed notifications