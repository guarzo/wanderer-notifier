# Multi-Map Support Architecture Plan

## Context

Wanderer Notifier currently supports a single map connection with configuration managed via environment variables. The goal is to support **300+ maps**, each with its own Discord bot token, channel configuration, feature flags, and tracked systems/characters. A new API endpoint on the Wanderer server will provide per-map configuration, dramatically simplifying local config management.

**Key constraints at 300+ map scale:**
- 300+ concurrent SSE connections (one per map)
- 300+ Discord bot tokens (HTTP-only, no gateway connections)
- Killmail fan-out must be O(1) per system lookup, not O(N) per map
- Single instance now, architecture compatible with future sharding
- Backwards compatible with single-map env var config until API endpoint exists

**Map opt-in model:** Map administrators enable notifications through the Wanderer server's existing UI. They configure their Discord bot token and channel IDs there. The notifier simply polls the server for the list of maps that have opted in -- the notifier itself is stateless with respect to map registration.

---

## Implementation Status

All 5 sprints have been implemented and pass all quality gates (`make compile`, `make test`, `mix credo --strict`, `mix dialyzer`).

| Sprint | Status | Summary |
|--------|--------|---------|
| Sprint 1: Foundation | COMPLETED | MapConfig, MapRegistry, scoped cache keys, Discord HttpClient |
| Sprint 2: Threading context | COMPLETED | MapTrackingClient multi-map, Initializer per-map, SSESupervisor multi-map, handler reverse index |
| Sprint 3: Notification path | COMPLETED | NeoClient send_embed_for_map, Determiner should_notify_for_map?, DiscordNotifier MapConfig-aware sends |
| Sprint 4: Killmail fan-out | COMPLETED | Pipeline fan-out via MapRegistry reverse index, mode-aware system tracking |
| Sprint 5: Polish | COMPLETED | Character reverse index, per-map SSE health stats, per-bot-token rate limiter |

---

## Phase 1: API Contract & MapConfig Data Model

### 1a. API Endpoint Contract

Design for the Wanderer server team to implement. This endpoint returns **only maps that have opted in for notifications** (configured by map admins through the map server UI).

**Endpoint:** `GET {MAP_URL}/api/v1/notifier/config`
**Auth:** `Authorization: Bearer {MAP_API_KEY}`
**Response:**

```json
{
  "data": {
    "maps": [
      {
        "slug": "wh-corp-map",
        "name": "WH Corp Map",
        "map_id": "uuid-here",
        "owner": "corp-name",
        "discord": {
          "bot_token": "MTEyMz...",
          "channels": {
            "primary": "111222333444555666",
            "system_kill": null,
            "character_kill": null,
            "system": null,
            "character": null,
            "rally": null
          },
          "rally_group_ids": []
        },
        "features": {
          "notifications_enabled": true,
          "kill_notifications_enabled": true,
          "system_notifications_enabled": true,
          "character_notifications_enabled": true,
          "rally_notifications_enabled": true,
          "wormhole_only_kill_notifications": false,
          "track_kspace": true,
          "priority_systems_only": false
        },
        "settings": {
          "corporation_kill_focus": [],
          "character_exclude_list": [],
          "system_exclude_list": []
        }
      }
    ],
    "version": 42,
    "updated_at": "2026-02-14T12:00:00Z"
  }
}
```

### 1b. MapConfig Struct

**File:** `lib/wanderer_notifier/map/map_config.ex`

```elixir
defmodule WandererNotifier.Map.MapConfig do
  defstruct [:slug, :name, :map_id, :owner,
             :discord, :features, :settings]

  # Key functions:
  # from_api/1 - parse API response into struct
  # from_env/0 - build from legacy env vars (backwards compat)
  # feature_enabled?/2 - check per-map feature flag
  # channel_for/2 - get Discord channel ID for notification type
  # bot_token/1 - get the map's Discord bot token
  # notifications_fully_enabled?/2 - check master + specific feature flag
end
```

---

## Phase 2: MapRegistry (GenServer + ETS)

**File:** `lib/wanderer_notifier/map/map_registry.ex`

A GenServer holding all map configurations with:
- **Startup:** Fetch from API, fall back to `MapConfig.from_env/0` if API unavailable
- **Periodic refresh:** Poll API every 5 minutes using `version` field to detect changes
- **PubSub events:** Broadcast `:maps_updated` when config changes so SSE supervisor can add/remove clients
- **Efficient access:** ETS tables for concurrent reads (300+ maps accessed from many processes)

### ETS Tables

| Table | Key | Value | Purpose |
|-------|-----|-------|---------|
| `:map_registry_configs` | slug | MapConfig.t() | Map configuration storage |
| `:map_registry_system_index` | system_id | [map_slug] | System reverse index for killmail fan-out |
| `:map_registry_character_index` | character_id | [map_slug] | Character reverse index for killmail fan-out |

### Public API

```elixir
MapRegistry.all_maps() :: [MapConfig.t()]
MapRegistry.get_map(slug) :: {:ok, MapConfig.t()} | {:error, :not_found}
MapRegistry.map_slugs() :: [String.t()]
MapRegistry.count() :: non_neg_integer()
MapRegistry.mode() :: :api | :legacy
MapRegistry.refresh() :: :ok

# Reverse index lookups (O(1) via ETS)
MapRegistry.maps_tracking_system(system_id) :: [MapConfig.t()]
MapRegistry.maps_tracking_character(character_id) :: [MapConfig.t()]

# Index maintenance (called by SSE event handlers)
MapRegistry.index_system(map_slug, system_id) :: :ok
MapRegistry.deindex_system(map_slug, system_id) :: :ok
MapRegistry.index_character(map_slug, character_id) :: :ok
MapRegistry.deindex_character(map_slug, character_id) :: :ok
```

**Dynamic map management:** On each periodic refresh (every 5 min), MapRegistry diffs the new config against the current state:
- **New maps** (opted in since last poll): Initialize data, start SSE client
- **Removed maps** (opted out or deleted): Stop SSE client, clean up cached data
- **Changed maps** (config updated): Update in-place, no SSE restart needed unless slug changed

---

## Phase 3: Cache Key Scoping

**Modified file:** `lib/wanderer_notifier/infrastructure/cache/keys.ex`

Map-scoped overloads alongside existing unscoped versions:

```elixir
# Existing (unchanged):
def map_systems, do: "map:systems"

# New scoped versions:
def map_systems(map_slug), do: "map:#{map_slug}:systems"
def map_characters(map_slug), do: "map:#{map_slug}:characters"
def tracked_system(map_slug, id), do: "tracking:#{map_slug}:system:#{id}"
def tracked_character(map_slug, id), do: "tracking:#{map_slug}:character:#{id}"
def notification_dedup(map_slug, key), do: "notification:#{map_slug}:dedup:#{key}"
```

ESI keys (`esi:character:123`, `esi:system:456`) remain global -- they're game data, not map-specific.

**Modified file:** `lib/wanderer_notifier/infrastructure/cache.ex`

Scoped tracking helpers:

```elixir
def is_system_tracked?(map_slug, system_id)
def put_tracked_system(map_slug, system_id, data)
def is_character_tracked?(map_slug, character_id)
def put_tracked_character(map_slug, character_id, data)
```

---

## Phase 4: Discord HTTP Client (Multi-Bot)

**File:** `lib/wanderer_notifier/domains/notifications/discord/http_client.ex`

Direct Discord REST API client that accepts a bot token per request. At 300+ maps, we cannot use Nostrum gateway for each bot. Notification sending is HTTP-only.

```elixir
defmodule WandererNotifier.Domains.Notifications.Discord.HttpClient do
  @discord_api "https://discord.com/api/v10"

  def send_embed(bot_token, channel_id, embed, opts \\ [])
  def send_message(bot_token, channel_id, content, opts \\ [])
  def send_embed_with_content(bot_token, channel_id, embed, content, opts \\ [])
end
```

Uses existing `Infrastructure.Http` with `:discord` service config for rate limiting and retries.

**Per-bot-token rate limiting:** Each request includes a `bucket_key` derived from a truncated SHA-256 hash of the bot token (`discord:<token_hash_12chars>`). The rate limiter middleware resolves custom bucket keys before falling back to per-host or global bucketing.

**Modified file:** `lib/wanderer_notifier/domains/notifications/discord/neo_client.ex`

Routing functions for multi-map sends:

```elixir
def send_embed_for_map(embed, map_config, channel_id)
def send_embed_with_content_for_map(embed, map_config, channel_id, content)
```

Existing Nostrum-based functions remain for the primary bot (slash commands, gateway events).

---

## Phase 5: Multi-Map SSE & Tracking

### 5a. MapTrackingClient accepts MapConfig

**Modified file:** `lib/wanderer_notifier/domains/tracking/map_tracking_client.ex`

New function heads that accept `map_config`:

```elixir
def fetch_and_cache_systems(%MapConfig{} = map_config, skip_notifications \\ false)
def fetch_and_cache_characters(%MapConfig{} = map_config, skip_notifications \\ false)
def is_system_tracked?(map_slug, system_id)
def is_character_tracked?(map_slug, character_id)
```

### 5b. Initializer accepts MapConfig

**Modified file:** `lib/wanderer_notifier/map/initializer.ex`

```elixir
def initialize_map_data_for(map_config) :: :ok
```

At 300+ maps, initialization is parallelized with concurrency limits:

```elixir
maps
|> Task.async_stream(&initialize_map_data_for/1, max_concurrency: 10, timeout: 60_000)
|> Stream.run()
```

### 5c. SSE Supervisor iterates MapRegistry

**Modified file:** `lib/wanderer_notifier/map/sse_supervisor.ex`

Supports both `:api` (multi-map) and `:legacy` (single-map) modes. Subscribes to MapRegistry PubSub events to handle dynamic map additions/removals. Staggered connections (50ms apart) to avoid thundering herd.

### 5d. Event Handlers thread map_slug

Event handlers maintain the reverse indexes in MapRegistry:

- **SystemHandler** - calls `MapRegistry.index_system/2` and `MapRegistry.deindex_system/2`
- **CharacterHandler** - calls `MapRegistry.index_character/2` and `MapRegistry.deindex_character/2`

---

## Phase 6: Notification Routing with Map Context

### 6a. DiscordNotifier accepts MapConfig

**Modified file:** `lib/wanderer_notifier/discord_notifier.ex`

All `send_*_async` functions have MapConfig-accepting overloads:

```elixir
def send_system_async(system, %MapConfig{} = map_config)
def send_character_async(character, %MapConfig{} = map_config)
def send_kill_async(killmail, %MapConfig{} = map_config)
def send_rally_point_async(rally_point, %MapConfig{} = map_config)
```

- Channel routing: `MapConfig.channel_for(map_config, :system)` instead of `Config.discord_system_channel_id()`
- Feature flags: `MapConfig.feature_enabled?(map_config, :system_notifications_enabled)` instead of `Config.system_notifications_enabled?()`
- Discord sending: `NeoClient.send_embed_for_map(embed, map_config, channel_id)`

### 6b. Determiner accepts MapConfig

**Modified file:** `lib/wanderer_notifier/domains/notifications/determiner.ex`

```elixir
def should_notify_for_map?(map_config, type, entity_id, entity_data \\ nil)
```

Per-map deduplication uses scoped dedup IDs (`"map_slug:entity_id"`) so the same entity on different maps generates separate notifications.

---

## Phase 7: Killmail Fan-Out

**Modified file:** `lib/wanderer_notifier/domains/killmail/pipeline.ex`

Mode-aware killmail processing:

```elixir
defp handle_notification_response(%Killmail{} = killmail) do
  case MapRegistry.mode() do
    :api -> fan_out_to_maps(killmail)
    :legacy -> send_legacy_notification(killmail)
  end
end
```

Fan-out collects matching maps from both system and character reverse indexes:

```elixir
defp collect_matching_maps(%Killmail{} = killmail) do
  system_maps = MapRegistry.maps_tracking_system(killmail.system_id)
  character_maps = collect_character_maps(killmail)
  (system_maps ++ character_maps) |> Enum.uniq_by(& &1.slug)
end
```

Each matching map gets its notification dispatched via `Task.Supervisor`:

```elixir
Enum.each(matching_maps, fn map_config ->
  Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
    DiscordNotifier.send_kill_async(killmail, map_config)
  end)
end)
```

**Deduplication:** Killmail dedup (`websocket_dedup:123`) stays global (process each killmail once). Notification dedup is per-map (same kill can notify multiple maps).

---

## Phase 8: Initialization Flow

**Modified file:** `lib/wanderer_notifier/application/initialization/service_initializer.ex`

Updated startup sequence:

```
infrastructure_phase (unchanged)
  -> Cache, Registry, RateLimiter, PubSub

foundation_phase (add MapRegistry)
  -> PersistentValues, Metrics, ApplicationCoordinator
  -> MapRegistry  <-- fetches all map configs from API
  -> ItemLookupService, LicenseService

integration_phase (unchanged)
  -> Discord Consumer (primary bot only), Phoenix endpoint

processing_phase (unchanged)
  -> Killmail.Supervisor, SSESupervisor, Schedulers

finalization_phase (multi-map aware)
  -> For each map (parallelized, max_concurrency: 10):
      -> initialize_map_data_for(map_config)
  -> Build reverse system index
  -> Start SSE clients (staggered, 50ms apart)
  -> Signal PipelineWorker
```

---

## Phase 9: Backwards Compatibility

`MapRegistry` detects whether the config API exists:

1. **API available:** Use multi-map configs from API (`:api` mode)
2. **API unavailable (404/timeout):** Build single `MapConfig` from existing env vars using `MapConfig.from_env/0` (`:legacy` mode)

`MapConfig.from_env/0` reads all current env vars (`DISCORD_BOT_TOKEN`, `DISCORD_CHANNEL_ID`, `MAP_NAME`, feature flags, etc.) and constructs one `MapConfig`. This means the entire codebase works identically to today with zero config changes until the server API is ready.

The old unscoped `DiscordNotifier.send_*_async(entity)` function heads remain as thin wrappers that use the legacy code path.

---

## Configuration After Migration

### Eliminated env vars (moved to API):
`MAP_NAME`, all `DISCORD_*_CHANNEL_ID` vars, `DISCORD_RALLY_GROUP_IDS`, `DISCORD_GUILD_ID`, `DISCORD_APPLICATION_ID`, all `*_NOTIFICATIONS_ENABLED` flags, `CORPORATION_KILL_FOCUS`, `CHARACTER_EXCLUDE_LIST`, `SYSTEM_EXCLUDE_LIST`, `PRIORITY_SYSTEMS_ONLY_ENABLED`, `WORMHOLE_ONLY_KILL_NOTIFICATIONS_ENABLED`, `TRACK_KSPACE_ENABLED`, `STATUS_MESSAGES_ENABLED`

### Retained env vars:
`MAP_URL` (server base URL), `MAP_API_KEY` (config API auth), `DISCORD_BOT_TOKEN` (primary bot for gateway/slash commands), `LICENSE_KEY`, `WEBSOCKET_URL`, `WANDERER_KILLS_URL`, `PORT`, `HOST`, `JANICE_API_*`, `STARTUP_SUPPRESSION_SECONDS`, `MAX_KILLMAIL_AGE_SECONDS`, HTTP timeout overrides, SSE connection settings

---

## Scale Considerations (300+ Maps)

| Concern | Design Decision |
|---------|----------------|
| **SSE connections** | 300+ lightweight BEAM processes; staggered startup (50ms apart = ~15s total) |
| **Memory per map** | ~small: MapConfig struct + cached systems/characters lists |
| **Killmail matching** | Reverse indexes `system_id -> [map_slugs]` and `character_id -> [map_slugs]` in ETS for O(1) lookup |
| **Discord rate limits** | Rate limiter keyed by truncated SHA-256 hash of bot token per Discord's per-token limits |
| **Initialization** | Parallel with `max_concurrency: 10` to avoid overwhelming the map server |
| **Config refresh** | Poll every 5 min; `version` field for cheap change detection |
| **Failure isolation** | Each SSE client is independent process; one map failure doesn't affect others |
| **Future sharding** | MapRegistry could filter maps by shard assignment; API could add `shard_id` field |

---

## Key Files Modified/Created

### New Files
| File | Purpose |
|------|---------|
| `lib/wanderer_notifier/map/map_config.ex` | Per-map configuration struct |
| `lib/wanderer_notifier/map/map_registry.ex` | GenServer + ETS registry with reverse indexes |
| `lib/wanderer_notifier/domains/notifications/discord/http_client.ex` | Multi-bot Discord REST client |

### Modified Files
| File | Changes |
|------|---------|
| `lib/wanderer_notifier/infrastructure/cache/keys.ex` | Scoped cache key overloads |
| `lib/wanderer_notifier/infrastructure/cache.ex` | Scoped tracking helpers |
| `lib/wanderer_notifier/infrastructure/http/middleware/rate_limiter.ex` | Custom bucket key support for per-token limiting |
| `lib/wanderer_notifier/domains/tracking/map_tracking_client.ex` | MapConfig-accepting function heads |
| `lib/wanderer_notifier/map/initializer.ex` | `initialize_map_data_for/1` |
| `lib/wanderer_notifier/map/sse_supervisor.ex` | Multi-map SSE client management |
| `lib/wanderer_notifier/domains/tracking/handlers/system_handler.ex` | System reverse index maintenance |
| `lib/wanderer_notifier/domains/tracking/handlers/character_handler.ex` | Character reverse index maintenance |
| `lib/wanderer_notifier/domains/notifications/discord/neo_client.ex` | `send_embed_for_map/3`, `send_embed_with_content_for_map/4` |
| `lib/wanderer_notifier/domains/notifications/determiner.ex` | `should_notify_for_map?/4` with per-map dedup |
| `lib/wanderer_notifier/discord_notifier.ex` | MapConfig-aware async send functions |
| `lib/wanderer_notifier/domains/killmail/pipeline.ex` | Mode-aware fan-out, reverse index tracking |
| `lib/wanderer_notifier/api/controllers/system_info.ex` | Multi-map SSE health stats |
| `lib/wanderer_notifier/application/initialization/service_initializer.ex` | MapRegistry in foundation phase |

---

## Verification Plan

1. **Unit tests:** MapConfig parsing, Cache.Keys scoping, MapRegistry CRUD
2. **Integration tests:** SSE client per map, notification routing with MapConfig
3. **Legacy mode test:** Start with no API endpoint, verify single-map behavior unchanged
4. **Fan-out test:** Killmail matching system tracked by 3 maps sends 3 notifications
5. **Scale test:** Load test with 50+ simulated map configs, verify memory and timing
6. **Failure isolation:** Kill one SSE client, verify others continue working
7. **Quality gates:** `make compile`, `make test`, `mix credo --strict`, `mix dialyzer` must all pass
