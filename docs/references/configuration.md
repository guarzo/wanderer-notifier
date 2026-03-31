# Configuration Reference

## Environment Variables

Environment variables are loaded without the WANDERER_ prefix (e.g., `DISCORD_BOT_TOKEN` instead of `WANDERER_DISCORD_BOT_TOKEN`).

Configuration layers: `config/config.exs` (compile-time) -> `config/runtime.exs` (runtime with env vars). Local development uses `.env` file via Dotenvy.

### Core Service Configuration
- **WebSocket**: `WEBSOCKET_URL` (default: "ws://host.docker.internal:4004") for killmail processing
- **WandererKills**: `WANDERER_KILLS_URL` (default: "http://host.docker.internal:4004")
- **SSE**: Automatically configured from MAP_URL/MAP_NAME/MAP_API_KEY for real-time map events
- **Discord**: `DISCORD_BOT_TOKEN` and `DISCORD_APPLICATION_ID` required for slash commands
- **Core Services**: Killmail processing via WebSocket and map synchronization via SSE are always enabled

### Feature Flags

Features can be toggled via environment variables ending in `_ENABLED`:

- `NOTIFICATIONS_ENABLED` - Master toggle for all notifications (default: true)
- `KILL_NOTIFICATIONS_ENABLED` - Enable/disable kill notifications (default: true)
- `SYSTEM_NOTIFICATIONS_ENABLED` - Enable/disable system notifications (default: true)
- `CHARACTER_NOTIFICATIONS_ENABLED` - Enable/disable character notifications (default: true)
- `STATUS_MESSAGES_ENABLED` - Enable/disable startup status messages (default: false)
- `TRACK_KSPACE_ENABLED` - Enable/disable K-Space system tracking (default: true)
- `PRIORITY_SYSTEMS_ONLY_ENABLED` - Only send notifications for priority systems (default: false)
- `WORMHOLE_ONLY_KILL_NOTIFICATIONS_ENABLED` - Only send kill notifications for wormhole systems (default: false)

### Corporation Kill Focus

- `CORPORATION_KILL_FOCUS` - Comma-separated list of corporation IDs for focused kill routing. When set, kills involving characters from these corporations (as victim or attacker) will:
  - Be routed to the **character kill channel** (or default channel if not configured)
  - Be **excluded** from the system kill channel

### Notification Timing

- `STARTUP_SUPPRESSION_SECONDS` - Suppress all notifications for this many seconds after startup (default: 30)
- `MAX_KILLMAIL_AGE_SECONDS` - Maximum age of killmails to notify about in seconds (default: 3600 / 1 hour)
  - Prevents notifications for old killmails when the service starts or reconnects
  - Killmails older than this threshold will be silently skipped

### Debugging Commands

```bash
# Interactive Development
make s
# In IEx:
iex> WandererNotifier.Config.discord_channel_id()
iex> :observer.start()  # GUI monitoring tool
iex> WandererNotifier.Config.validate_all()
iex> Cachex.stats(:wanderer_cache)
iex> GenServer.call(WandererNotifier.Killmail.WebSocketClient, :status)
iex> GenServer.call(WandererNotifier.Map.SSEClient, :status)
```
