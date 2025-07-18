# WandererKills HTTP Client Integration

This document describes the HTTP client integration that complements the WebSocket connection to WandererKills service.

## Overview

The HTTP client provides:
- **Automatic fallback** when WebSocket connection is unavailable
- **Type-safe API** with behavior definitions for easy testing
- **Bulk loading** capabilities for historical data
- **Health checking** to monitor service availability

## Architecture

### Components

1. **WandererKillsAPI** (`lib/wanderer_notifier/killmail/wanderer_kills_api.ex`)
   - Enhanced type-safe HTTP client
   - Implements the behavior contract
   - Provides all API endpoints with proper error handling

2. **FallbackHandler** (`lib/wanderer_notifier/killmail/fallback_handler.ex`)
   - GenServer that monitors WebSocket connection status
   - Automatically switches to HTTP polling when WebSocket is down
   - Manages bulk loading and periodic data fetching

3. **WandererKillsClient** (`lib/wanderer_notifier/killmail/wanderer_kills_client.ex`)
   - Original HTTP client (maintained for compatibility)
   - Used by the enhanced API client internally

## Usage

### Manual API Calls

```elixir
# Fetch killmails for a system
{:ok, kills} = WandererNotifier.Killmail.WandererKillsAPI.fetch_system_killmails(30000142, 24, 100)

# Fetch killmails for multiple systems
{:ok, system_kills} = WandererNotifier.Killmail.WandererKillsAPI.fetch_systems_killmails(
  [30000142, 30000143], 
  24, 
  50
)

# Get a specific killmail
{:ok, killmail} = WandererNotifier.Killmail.WandererKillsAPI.get_killmail(12345)

# Check API health
{:ok, status} = WandererNotifier.Killmail.WandererKillsAPI.health_check()
```

### Automatic Fallback

The fallback handler automatically activates when:
- WebSocket connection is lost
- WebSocket fails to reconnect after multiple attempts

No manual intervention is required. The system will:
1. Detect WebSocket disconnection
2. Start HTTP polling for tracked systems
3. Process killmails through the same pipeline
4. Stop HTTP polling when WebSocket reconnects

### Bulk Loading

For initial data loading or recovery:

```elixir
# Load last 24 hours of data for all tracked systems
{:ok, result} = WandererNotifier.Killmail.FallbackHandler.bulk_load(24)
# Returns: %{loaded: 150, errors: []}
```

## Configuration

The HTTP client uses the same base URL as the WebSocket connection:

```elixir
# In config/runtime.exs or environment variables
config :wanderer_notifier,
  wanderer_kills_base_url: System.get_env("WANDERER_KILLS_URL", "http://host.docker.internal:4004"),
  wanderer_kills_max_retries: 3
```

## Error Handling

The API client provides structured error responses:

```elixir
{:error, %{
  type: :timeout | :rate_limit | :not_found | :server_error | :client_error | :unknown,
  message: "Description of the error"
}}
```

Common error types:
- `:timeout` - Request timed out
- `:rate_limit` - API rate limit exceeded
- `:not_found` - Resource not found (404)
- `:server_error` - Server error (5xx)
- `:client_error` - Client error (4xx)

## Testing

The implementation includes comprehensive tests with mocks:

```elixir
# In your tests
import Mox

setup do
  Application.put_env(:wanderer_notifier, :http_client, HttpClientMock)
  :ok
end

test "fetch system killmails" do
  HttpClientMock
  |> expect(:get, fn _url, _headers, _opts ->
    {:ok, %{status_code: 200, body: Jason.encode!(%{"kills" => []})}}
  end)
  
  assert {:ok, []} = WandererKillsAPI.fetch_system_killmails(30000142)
end
```

## Performance Considerations

1. **Rate Limiting**: The client respects API rate limits (10 req/s, burst of 20)
2. **Chunking**: Bulk operations process systems in chunks of 10
3. **Caching**: Results are cached to minimize API calls
4. **Retries**: Failed requests retry with exponential backoff

## Monitoring

The fallback handler logs its activities:
- When fallback mode activates/deactivates
- Number of systems being monitored
- Killmails processed via HTTP
- Any errors encountered

Check logs for entries like:
```
[info] WebSocket connection down, activating HTTP fallback
[info] Fetching recent data via HTTP API systems_count=45 characters_count=12
[info] WebSocket connection restored, deactivating HTTP fallback
```