# WebSocket Message Processing Logic

This document outlines the flow and logic for processing WebSocket messages from zKillboard's real-time kill feed.

## Message Flow

1. WebSocket connection is established to `wss://zkillboard.com/websocket/`
2. The application subscribes to the `killstream` channel
3. Messages are received in the WebSocket handler
4. Messages are forwarded to the parent process (Service GenServer)
5. Messages are decoded and processed by KillProcessor
6. Processed kills are stored in Process dictionary
7. Kill notifications are sent based on configured filters

## Message Types

The WebSocket feed from zKillboard can send several types of messages:

### 1. Kill Messages

These contain information about a kill that just happened. Example structure:

```json
{
  "killmail_id": 123456789,
  "killmail_time": "2025-03-20T15:49:58Z",
  "solar_system_id": 30000253,
  "victim": {
    "character_id": 2118987968,
    "corporation_id": 98760838,
    "damage_taken": 10809,
    "ship_type_id": 621
  },
  "attackers": [
    {
      "alliance_id": 99003581,
      "character_id": 96393511,
      "corporation_id": 98715093,
      "damage_done": 10809,
      "final_blow": true,
      "security_status": -3.1,
      "ship_type_id": 29344,
      "weapon_type_id": 3138
    }
  ],
  "zkb": {
    "locationID": 40015966,
    "hash": "e32ea5d44469fbe320dcb977bdf30b8fa025e246",
    "fittedValue": 34691435.01,
    "totalValue": 35061250.61,
    "points": 44,
    "npc": false,
    "solo": true,
    "awox": false
  }
}
```

### 2. TQ Status Messages

These contain information about the EVE Online server status:

```json
{
  "action": "tqStatus",
  "tqStatus": {
    "players": 25000,
    "vip": false
  }
}
```

### 3. Action Messages

These messages have an "action" field indicating server events:

```json
{
  "action": "pong"
}
```

## Processing Logic

### 1. Initial Message Classification

Messages are first classified based on their structure:

```elixir
defp classify_message_type(json_data) when is_map(json_data) do
  cond do
    Map.has_key?(json_data, "action") ->
      "action:#{json_data["action"]}"
      
    Map.has_key?(json_data, "killmail_id") and Map.has_key?(json_data, "zkb") ->
      "killmail_with_zkb"
      
    Map.has_key?(json_data, "killmail_id") ->
      "killmail_without_zkb"
      
    Map.has_key?(json_data, "tqStatus") ->
      "tq_status"
      
    true ->
      "unknown"
  end
end
```

### 2. Message Handling Path

Based on the message type, different processing paths are taken:

#### TQ Status Messages

If the message has a "tqStatus" field, it's treated as server status:

```elixir
"tqStatus" ->
  # Handle server status updates
  handle_tq_status(message)
  state
```

The TQ status (player count, VIP status) is stored in the process dictionary for monitoring.

#### Kill Messages

If the message has no "action" field, it's treated as a killmail:

```elixir
nil ->
  # Handle killmail
  handle_killmail(message, state)
```

#### Action Messages

Other messages with an "action" field are generally ignored:

```elixir
other ->
  Logger.debug("Ignoring zKill message with action: #{other}")
  state
```

### 3. Killmail Processing

Each killmail goes through the following steps:

1. **Extract Kill ID**

   ```elixir
   kill_id = get_in(killmail, ["killmail_id"])
   ```

2. **Check if Already Processed**

   ```elixir
   if Map.has_key?(state.processed_kill_ids, kill_id) do
     Logger.debug("Kill #{kill_id} already processed, skipping")
     state
   else
     # Process the kill
     process_new_kill(killmail, kill_id, state)
   end
   ```

3. **Process New Kill**

   ```elixir
   # Store each kill in memory - limited to recent kills
   update_recent_kills(killmail)

   # Only continue with processing if feature is enabled
   if Features.enabled?(:backup_kills_processing) do
     # Validate, enrich, and notify
     # ...
   ```

4. **Store in Cache**

   The kill is stored in the process dictionary for later use:

   ```elixir
   # Add the new kill to the front
   updated_kills = [kill_with_id | recent_kills]
   # Keep only the most recent ones
   updated_kills = Enum.take(updated_kills, @max_recent_kills)
   # Update the process dictionary
   Process.put(@recent_kills_key, updated_kills)
   ```

## Kill ID Extraction Logic

To handle variations in kill message formats from zKillboard, we have a robust ID extraction function:

```elixir
defp get_killmail_id(kill_data) when is_map(kill_data) do
  cond do
    # Direct field
    Map.has_key?(kill_data, "killmail_id") -> 
      Map.get(kill_data, "killmail_id")
    
    # Check for nested structure
    Map.has_key?(kill_data, "zkb") && Map.has_key?(kill_data, "killmail") ->
      get_in(kill_data, ["killmail", "killmail_id"])
    
    # Check for string keys converted to atoms
    Map.has_key?(kill_data, :killmail_id) ->
      Map.get(kill_data, :killmail_id)
      
    # Try to extract from the raw data if it has a zkb key 
    # (common format in real-time websocket feed)
    Map.has_key?(kill_data, "zkb") ->
      kill_id = Map.get(kill_data, "killID") || 
               get_in(kill_data, ["zkb", "killID"]) ||
               get_in(kill_data, ["zkb", "killmail_id"])
               
      # If we found a string ID, convert to integer
      if is_binary(kill_id) do
        String.to_integer(kill_id)
      else
        kill_id
      end
    
    true -> nil
  end
end
```

## Notification Decision Logic

Kills are processed for notification based on these criteria:

1. Is it the first notification since startup? (Always send enriched)
2. Is the license valid? (Controls rich vs. text notifications)
3. Is the kill relevant based on:
   - System tracking settings
   - Character tracking settings

## Special Cases

### First Kill Notification

The first kill notification after startup is always sent in enriched format regardless of license status to demonstrate premium features:

```elixir
# For first notification, use enriched format regardless of license
if is_first_notification || License.status().valid do
  # Mark that we've sent the first notification if this is it
  if is_first_notification do
    Stats.mark_notification_sent(:kill)
    Logger.info("Sending first kill notification in enriched format (startup message)")
  end
  
  # Use the formatter to create the notification
  generic_notification = Formatter.format_kill_notification(enriched_kill, kill_id)
  discord_embed = Formatter.to_discord_format(generic_notification)
  send_discord_embed(discord_embed, :kill_notifications)
end
```

### Test Notifications

For debugging and testing, we have a special endpoint that will use real cached kills if available, falling back to sample data only when necessary:

```elixir
cond do
  recent_kills == [] ->
    # Use sample data if no real kills cached
    sample_kill = get_sample_kill()
    # ...
    
  true ->
    # Use real kill data for the notification
    recent_kill = List.first(recent_kills)
    # ...
end
```