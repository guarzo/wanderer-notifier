# WebSocket and Kill Notification Testing Guide

This guide explains how to test the WebSocket connection and kill notification functionality in the WandererNotifier application.

## Prerequisites

- Running WandererNotifier application
- Access to the web dashboard
- Discord webhook configured for notifications

## Testing Process Flow

1. **Start the application**:
   - Run the application locally with `mix phx.server` or in a container
   - Verify the application is running by accessing the dashboard

2. **Check WebSocket Connection**:
   - Navigate to the debug dashboard or check logs for WebSocket connection status
   - Look for log messages with `WEBSOCKET TRACE` prefix
   - Verify the WebSocket is in a connected state (logs should show successful subscription)

3. **Initiate Test Notification**:
   - Use the API endpoint `/api/test-notification` to send a test notification
   - This can be accessed via the web dashboard or a direct API call:
     ```
     curl http://localhost:4000/api/test-notification
     ```

4. **Verify Notification Receipt**:
   - Check Discord for the test notification
   - The notification should contain either real kill data from the WebSocket or a sample kill

## Troubleshooting

### WebSocket Issues

1. **WebSocket Not Connecting**:
   - Check if the ZKill WebSocket service is available
   - Verify network connectivity from your environment
   - Check for firewall rules blocking WebSocket connections
   - Look for any connection errors in the logs (`WEBSOCKET TRACE: Error connecting`)

2. **WebSocket Connects but No Messages**:
   - Verify subscription was sent (`WEBSOCKET TRACE: Sending subscription`)
   - Check you're subscribed to the correct channel (should be `killstream`)
   - Try restarting the WebSocket process

### Notification Issues

1. **Test Notification Uses Sample Data Instead of Real Data**:
   - Confirm that WebSocket is connected and receiving messages
   - Check the logs for `CACHE TRACE` messages to see if kills are being stored
   - Verify the cache repository is functioning (look for `Retrieved X cached kills from shared repository`)

2. **No Notification Sent to Discord**:
   - Check Discord webhook configuration
   - Verify Discord rate limits haven't been exceeded
   - Look for errors in the logs related to Discord notification (`Error sending message to Discord`)

## Verifying Cache Operations

To verify that the cache is working correctly:

1. Confirm kills are being stored in the cache:
   ```
   CACHE TRACE: Storing kill in shared cache repository
   CACHE TRACE: Successfully extracted killmail_id: 12345678
   CACHE TRACE: Stored kill 12345678 in shared cache repository
   ```

2. Verify kills can be retrieved from the cache:
   ```
   CACHE TRACE: Retrieving recent kills from shared cache repository
   CACHE TRACE: Found 5 recent kill IDs in cache
   CACHE TRACE: Retrieved 5 cached kills from shared repository
   ```

3. Check if retrieved kills are converted to the right format:
   ```
   First kill is Killmail struct? true
   Killmail struct ID: 12345678
   ```

## Advanced Testing

### Manual WebSocket Testing

You can manually test the WebSocket connection using wscat:

```bash
# Install wscat if you don't have it
npm install -g wscat

# Connect to ZKill WebSocket
wscat -c wss://zkillboard.com/websocket/

# Subscribe to killstream (after connecting)
{"action":"sub","channel":"killstream"}
```

This will let you see raw kill messages coming from ZKill.

### Generating Sample Kill Data

If you need to manually insert kill data for testing, you can use the Cachex API:

```elixir
# Replace 12345678 with a unique kill ID
kill_id = 12345678
kill_data = %{
  "killmail_id" => kill_id,
  "zkb" => %{
    "locationID" => 30000142,
    "hash" => "samplehash",
    "totalValue" => 15000000.00,
  }
}

# Store in cache
key = "zkill:recent_kills:#{kill_id}"
Cachex.put(:wanderer_notifier_cache, key, kill_data, ttl: 3600000)

# Add to recent kills list
kill_ids = Cachex.get!(:wanderer_notifier_cache, "zkill:recent_kills") || []
updated_ids = [kill_id | kill_ids] |> Enum.uniq() |> Enum.take(10)
Cachex.put(:wanderer_notifier_cache, "zkill:recent_kills", updated_ids, ttl: 3600000)
```

Run the above in an IEx session to manually insert test data.