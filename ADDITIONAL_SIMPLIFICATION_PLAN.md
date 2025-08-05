# Additional Architecture Simplification Plan

## Overview
This document extends the original ARCHITECTURE_SIMPLIFICATION_PLAN.md with additional simplification opportunities discovered through deeper analysis. These changes focus on removing unnecessary GenServers, breaking down large modules, and eliminating duplicate functionality.

## Phase 6: Large Module Breakdown (High Priority)
**Duration**: 3-4 days  
**Risk**: Low (splitting files, no logic changes)

### Step 6.1: Split NotificationFormatter (1,149 lines)
**Current Issue**: Single massive module handling all notification types with deep nesting.

**Implementation**:
```elixir
# Split into focused formatters:
# lib/wanderer_notifier/domains/notifications/formatters/killmail_formatter.ex
defmodule WandererNotifier.Domains.Notifications.Formatters.KillmailFormatter do
  @moduledoc "Formats killmail notifications for Discord"
  
  alias WandererNotifier.Domains.Notifications.Formatters.FormatterHelpers
  
  def format(killmail_data, opts \\ []) do
    # Move killmail-specific formatting here
  end
  
  def format_embed(killmail_data, opts \\ []) do
    # Move killmail embed logic here
  end
end

# lib/wanderer_notifier/domains/notifications/formatters/character_formatter.ex
defmodule WandererNotifier.Domains.Notifications.Formatters.CharacterFormatter do
  @moduledoc "Formats character notifications for Discord"
  
  def format(character_data, opts \\ []) do
    # Move character-specific formatting here
  end
end

# lib/wanderer_notifier/domains/notifications/formatters/system_formatter.ex
defmodule WandererNotifier.Domains.Notifications.Formatters.SystemFormatter do
  @moduledoc "Formats system notifications for Discord"
  
  def format(system_data, opts \\ []) do
    # Move system-specific formatting here
  end
end

# lib/wanderer_notifier/domains/notifications/formatters/formatter_helpers.ex
defmodule WandererNotifier.Domains.Notifications.Formatters.FormatterHelpers do
  @moduledoc "Shared formatting utilities"
  
  def format_isk(value), do: # Common ISK formatting
  def format_timestamp(datetime), do: # Common timestamp formatting
  def truncate_text(text, max_length), do: # Common text truncation
end
```

**Update References**:
```elixir
# Before
NotificationFormatter.format_killmail_notification(data)

# After
KillmailFormatter.format(data)
```

### Step 6.2: Simplify Discord NeoClient (945 lines)
**Current Issue**: Mixing Discord API, channel resolution, and environment logic.

**Implementation**:
```elixir
# lib/wanderer_notifier/domains/notifications/discord/channel_resolver.ex
defmodule WandererNotifier.Domains.Notifications.Discord.ChannelResolver do
  @moduledoc "Resolves Discord channel IDs with fallback logic"
  
  def resolve_channel(notification_type, config) do
    # Extract channel resolution logic
  end
  
  def get_test_channel(), do: # Test channel logic
  def get_production_channel(type), do: # Production channel logic
end

# Simplify neo_client.ex to focus only on Discord API communication
```

### Step 6.3: Extract WebSocket Heartbeat Logic (904 lines)
**Current Issue**: WebSocketClient manages connection, heartbeat, and subscriptions in one place.

**Implementation**:
```elixir
# lib/wanderer_notifier/domains/killmail/websocket_heartbeat.ex
defmodule WandererNotifier.Domains.Killmail.WebSocketHeartbeat do
  @moduledoc "Manages WebSocket heartbeat logic"
  
  def schedule_heartbeat(interval_ms) do
    Process.send_after(self(), :send_heartbeat, interval_ms)
  end
  
  def create_heartbeat_frame() do
    {:ping, ""}
  end
  
  def handle_pong(state) do
    # Update last pong timestamp
  end
end
```

**Testing**: Run existing WebSocket tests to ensure heartbeat still works.

---

## Phase 7: GenServer to Module Conversion (High Priority)
**Duration**: 2-3 days  
**Risk**: Medium (changing process architecture)

### Step 7.1: Convert LicenseService to Simple Module
**Current**: 865-line GenServer for stateless license validation  
**Target**: Simple module with pure functions

**Implementation**:
```elixir
# lib/wanderer_notifier/domains/license/license.ex
defmodule WandererNotifier.Domains.License.License do
  @moduledoc "Simple license validation without GenServer overhead"
  
  alias WandererNotifier.Shared.Dependencies
  
  @validation_url "https://lm.wanderer.ltd/validate_bot"
  
  def validate(opts \\ []) do
    with {:ok, config} <- get_license_config(),
         {:ok, response} <- make_validation_request(config),
         {:ok, result} <- parse_validation_response(response) do
      handle_validation_result(result)
    end
  end
  
  defp get_license_config do
    # Simple config loading
  end
  
  defp make_validation_request(config) do
    # Direct HTTP call using Dependencies.http()
  end
  
  # Remove all GenServer callbacks and state management
end
```

**Update Application Supervision**:
```elixir
# Remove from application.ex supervision tree
# Update all callers from LicenseService.validate() to License.validate()
```

### Step 7.2: Remove Telemetry GenServers
**Files to convert/remove**:
- `performance_monitor.ex` (732 lines) → Use `:telemetry` events
- `dashboard.ex` (821 lines) → Direct metric queries
- `event_analytics.ex` → Remove if unused
- `collector.ex` → Remove if unused

**Implementation for replacement**:
```elixir
# lib/wanderer_notifier/shared/telemetry_events.ex
defmodule WandererNotifier.Shared.TelemetryEvents do
  @moduledoc "Direct telemetry event handling without GenServer"
  
  def emit_event(event_name, measurements, metadata \\ %{}) do
    :telemetry.execute(
      [:wanderer_notifier | event_name],
      measurements,
      metadata
    )
  end
  
  def attach_handler(event_name, handler_fun) do
    :telemetry.attach(
      "wanderer-#{event_name}",
      [:wanderer_notifier | event_name],
      handler_fun,
      nil
    )
  end
end
```

### Step 7.3: Simplify Connection Monitor
**Current**: 450-line GenServer tracking connection history  
**Target**: Basic alive/dead status checking

**Implementation**:
```elixir
# lib/wanderer_notifier/infrastructure/connection_status.ex
defmodule WandererNotifier.Infrastructure.ConnectionStatus do
  @moduledoc "Simple connection status checking"
  
  def check_websocket do
    case Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient) do
      nil -> :disconnected
      pid -> if Process.alive?(pid), do: :connected, else: :disconnected
    end
  end
  
  def check_sse do
    case Process.whereis(WandererNotifier.Map.SSEClient) do
      nil -> :disconnected
      pid -> if Process.alive?(pid), do: :connected, else: :disconnected
    end
  end
  
  def check_all do
    %{
      websocket: check_websocket(),
      sse: check_sse(),
      discord: check_discord()
    }
  end
end
```

---

## Phase 8: Dead Code Removal (Medium Priority)
**Duration**: 1 day  
**Risk**: Low (removing unused code)

### Step 8.1: Delete Identified Dead Code
```bash
# Remove stub modules
rm lib/wanderer_notifier/infrastructure/adapters/service_stub.ex

# Remove pass-through modules
rm lib/wanderer_notifier/domains/notifications/formatters/plain_text.ex

# Remove unused telemetry modules (after Phase 7.2)
rm lib/wanderer_notifier/shared/telemetry/performance_monitor.ex
rm lib/wanderer_notifier/shared/telemetry/event_analytics.ex
rm lib/wanderer_notifier/shared/telemetry/collector.ex
rm lib/wanderer_notifier/shared/telemetry/dashboard.ex

# Update imports in remaining telemetry.ex
```

### Step 8.2: Verify No Breaking Changes
```bash
# After each deletion
make compile
make test

# Check for any remaining references
grep -r "ServiceStub" lib/
grep -r "PlainText" lib/
grep -r "PerformanceMonitor" lib/
```

---

## Phase 9: Consolidate Duplicate Functionality (Medium Priority)
**Duration**: 2 days  
**Risk**: Low-Medium (merging implementations)

### Step 9.1: Remove Duplicate Cache Implementation
**Current**: Two cache implementations doing the same thing

```bash
# Remove notification-specific cache
rm lib/wanderer_notifier/domains/notifications/cache_impl.ex
```

**Update References**:
```elixir
# Before
alias WandererNotifier.Domains.Notifications.CacheImpl
CacheImpl.check_duplicate(key)

# After
alias WandererNotifier.Infrastructure.Cache
Cache.get(key)
```

### Step 9.2: Merge Configuration Modules
**Current**: `Config` (Application.get_env) and `SimpleConfig` (System.get_env)

**Implementation**:
```elixir
# lib/wanderer_notifier/shared/config.ex (enhanced)
defmodule WandererNotifier.Shared.Config do
  @moduledoc "Unified configuration with both Application and System env support"
  
  # For compile-time config (from config/*.exs)
  def get_app_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end
  
  # For runtime config (from environment variables)
  def get_env(key, default \\ nil) do
    System.get_env(key, default)
  end
  
  # Unified getters that check both sources
  def discord_bot_token do
    get_env("DISCORD_BOT_TOKEN") || get_app_env(:discord_bot_token) ||
      raise "Missing Discord bot token"
  end
  
  # Feature flags with smart defaults
  def notifications_enabled? do
    get_boolean_env("NOTIFICATIONS_ENABLED", 
      get_app_env(:notifications_enabled, true))
  end
  
  # ... migrate all config functions here
end
```

```bash
# Remove SimpleConfig after migration
rm lib/wanderer_notifier/shared/simple_config.ex
```

### Step 9.3: Remove Duplicate Rate Limiter
**Current**: Simple rate limiter duplicates HTTP middleware functionality

```bash
# Remove simple rate limiter
rm lib/wanderer_notifier/rate_limiter.ex
```

**Update References**:
```elixir
# Before
WandererNotifier.RateLimiter.check_rate(bucket, scale, limit)

# After
alias WandererNotifier.Infrastructure.Http.Middleware.RateLimiter
RateLimiter.check_rate(bucket, scale, limit)
```

### Step 9.4: Remove Connection Health Service Wrapper
```bash
# Remove wrapper
rm lib/wanderer_notifier/infrastructure/connection_health_service.ex
```

**Update References**:
```elixir
# Before
ConnectionHealthService.check_health()

# After (using new simplified module from Phase 7.3)
ConnectionStatus.check_all()
```

---

## Phase 10: Behavior Simplification (Low Priority)
**Duration**: 1 day  
**Risk**: Low (simplifying contracts)

### Step 10.1: Simplify ESI ServiceBehaviour
**Current**: 20+ callback definitions with many duplicates

```elixir
# Reduce to essential callbacks only
defmodule WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour do
  @moduledoc "Simplified ESI service behavior"
  
  # Core ESI operations only
  @callback get_killmail(killmail_id :: integer(), hash :: String.t()) :: 
    {:ok, map()} | {:error, term()}
    
  @callback get_character(character_id :: integer()) :: 
    {:ok, map()} | {:error, term()}
    
  @callback get_corporation(corporation_id :: integer()) :: 
    {:ok, map()} | {:error, term()}
    
  @callback get_alliance(alliance_id :: integer()) :: 
    {:ok, map()} | {:error, term()}
    
  @callback get_system(system_id :: integer()) :: 
    {:ok, map()} | {:error, term()}
    
  @callback get_type(type_id :: integer()) :: 
    {:ok, map()} | {:error, term()}
    
  # Remove duplicate callbacks with different arities
  # Remove unused callbacks
end
```

---

## Testing Strategy

### Phase-by-Phase Testing Requirements

**Phase 6 (Module Breakdown)**:
```bash
# Test each split module individually
make test.notifications
make test.discord
make test.killmail

# Integration test
make s
# Send test notification of each type
```

**Phase 7 (GenServer Conversion)**:
```bash
# Before removing GenServers
make test.license
make test.telemetry

# After conversion
make compile
make test.all
# Verify no supervision tree errors on startup
```

**Phase 8-10 (Cleanup)**:
```bash
# After each deletion/merge
make compile
make test
make credo --strict
make dialyzer
```

---

## Implementation Timeline

**Week 1**:
- **Day 1-2**: Phase 6.1 (Split NotificationFormatter)
- **Day 3**: Phase 6.2-6.3 (Discord and WebSocket simplification)
- **Day 4-5**: Phase 7.1-7.2 (License and Telemetry conversion)

**Week 2**:
- **Day 1**: Phase 7.3 (Connection Monitor) + Phase 8 (Dead code removal)
- **Day 2-3**: Phase 9 (Consolidate duplicates)
- **Day 4**: Phase 10 (Behavior simplification)
- **Day 5**: Final testing and documentation updates

---

## Success Metrics

### Quantitative Improvements
- **Lines of code**: Additional 25-30% reduction (6,000+ lines)
- **File count**: ~20-25 files removed
- **GenServer count**: 8-10 fewer GenServers
- **Module count**: ~15 modules consolidated or removed

### Qualitative Improvements
- **Clearer boundaries**: Each module has a single, clear responsibility
- **Reduced complexity**: No unnecessary GenServers for stateless operations
- **Better performance**: Less process overhead and message passing
- **Easier testing**: Fewer mocks needed for pure functions
- **Simplified debugging**: Direct function calls instead of GenServer messaging

---

## Risk Mitigation

### High-Risk Changes
1. **GenServer removal**: Test thoroughly after each conversion
2. **Config consolidation**: Ensure all config sources work correctly
3. **Module splits**: Verify all imports are updated

### Rollback Strategy
- Each phase is independent and can be reverted
- Git commits after each successful phase
- Keep backup branches for major changes

---

## Final Notes

This plan builds on the existing simplification effort and would result in a much cleaner, more maintainable codebase. The key principles are:

1. **Remove unnecessary abstractions**: GenServers for stateless operations
2. **Single responsibility**: Break large modules into focused ones
3. **DRY principle**: Eliminate duplicate implementations
4. **Direct over indirect**: Prefer function calls over message passing

After completing both simplification plans, the codebase will be significantly more approachable for new developers and easier to maintain long-term.