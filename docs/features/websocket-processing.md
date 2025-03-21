# WebSocket Message Processing

This document outlines the flow and logic for processing WebSocket messages from zKillboard's real-time kill feed.

## Message Flow

1. WebSocket connection is established to `wss://zkillboard.com/websocket/`
2. The application subscribes to the `killstream` channel
3. Messages are received in the WebSocket handler (`WandererNotifier.Api.ZKill.WebSocket` via the `handle_frame/2` function)
4. Messages are parsed and classified in `process_text_frame/2`
5. Valid kill messages are forwarded to the parent process (Service GenServer) via `{:zkill_message, message}`
6. The service GenServer receives the message in its `handle_info/2` function and forwards to `KillProcessor`
7. `KillProcessor.process_zkill_message/2` parses and validates the kill data
8. If valid, the kill is cached and processed for notification if it meets the criteria

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

   The kill is stored in a shared cache for later use:

   ```elixir
   # Create a cache key for this kill
   kill_key = "zkill:recent_kills:#{kill_id}"

   # Store the kill data with TTL
   Cache.Repository.put(kill_key, kill_data, ttl: @kill_cache_ttl)

   # Update the list of recent kill IDs
   recent_kill_ids = [kill_id | recent_kill_ids] |> Enum.take(@max_recent_kills)
   Cache.Repository.put("zkill:recent_kills", recent_kill_ids, ttl: @kill_list_cache_ttl)
   ```

## Cache Implementation

The application stores kills in a shared cache repository:

1. Each kill is stored individually with its own key (`zkill:recent_kills:{kill_id}`)
2. A separate list of recent kill IDs is maintained (`zkill:recent_kills`)
3. TTL is applied to avoid unbounded cache growth
4. Data is converted to the `WandererNotifier.Data.Killmail` struct when possible for consistency

Benefits of this approach:

- Kills are accessible from any process in the application
- Persistence across WebSocket restarts (until TTL expires)
- Automatic cache cleanup via TTL
- Better data structure consistency with the Killmail struct

## Kill ID Extraction Logic

To handle variations in kill message formats from zKillboard, there's a robust ID extraction function:

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

## Testing Kill Notifications

To test kill notifications:

1. Call the `/api/test-notification` endpoint
2. The system will look for recent kills in the shared cache
3. If found, it will use the most recent one for the test notification
4. If no recent kills are found, it will fall back to sample data

## Debugging

The system has extensive logging with specific trace tags:

- `WEBSOCKET TRACE` - For WebSocket connection and message receipt
- `PROCESSOR TRACE` - For message processing and parsing
- `KILLMAIL TRACE` - For killmail-specific handling
- `CACHE TRACE` - For cache operations

These logs can help identify where issues are occurring in the processing chain.
