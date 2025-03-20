# Kill Notification Testing

This document explains the WebSocket message flow and how kills are processed and cached in the WandererNotifier application.

## WebSocket Message Flow

1. WebSocket messages are received in `WandererNotifier.Api.ZKill.WebSocket` via the `handle_frame/2` function
2. Messages are parsed and classified in `process_text_frame/2` 
3. Valid kill messages are forwarded to the main service GenServer via `{:zkill_message, message}`
4. The service GenServer receives the message in its `handle_info/2` function and forwards to `KillProcessor`
5. `KillProcessor.process_zkill_message/2` parses and validates the kill data
6. If valid, the kill is cached and ready for notification

## Cache Changes

### Previous Implementation Issues

The previous implementation used the Process Dictionary to store recent kills:

```elixir
Process.put(@recent_kills_key, updated_kills)
```

This approach had several issues:
- Process dictionary is process-specific, meaning kills stored in the WebSocket process were not accessible from the API controller process
- Restarting the WebSocket process would lose all cached kills
- No TTL (time to live) management, requiring manual cleanup
- No shared access between different parts of the application

### New Implementation

The updated implementation uses the shared `WandererNotifier.Cache.Repository` to store kills:

1. Each kill is stored individually with its own key
2. A separate list of recent kill IDs is maintained
3. TTL is applied to avoid unbounded cache growth
4. Data is converted to the `WandererNotifier.Data.Killmail` struct when possible for consistency

Benefits:
- Kills are accessible from any process in the application
- Persistence across WebSocket restarts (until TTL expires)
- Automatic cache cleanup via TTL
- Better data structure consistency with the Killmail struct

## Testing Notifications

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

## Cache Keys

The following cache keys are used for kill data:

- `zkill:recent_kills` - List of recent kill IDs
- `zkill:recent_kills:{kill_id}` - Individual kill data

Each kill has a TTL of 1 hour to prevent the cache from growing unbounded.