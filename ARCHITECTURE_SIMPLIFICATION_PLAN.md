# Architecture Simplification Implementation Plan

## Overview
This plan outlines a systematic approach to simplifying the overcomplicated architecture while maintaining all functionality. Changes are organized into phases to minimize risk and allow for incremental testing.

## Phase 1: Dependency Injection Consolidation (High Priority)
**Duration**: 2-3 days  
**Risk**: Medium (affects core dependency resolution)

### Step 1.1: Create Simple Dependency Helper Module
```elixir
# lib/wanderer_notifier/shared/dependencies.ex
defmodule WandererNotifier.Shared.Dependencies do
  @moduledoc """
  Simplified dependency resolution using application configuration.
  Replaces the complex DependencyRegistry GenServer.
  """

  @doc "Get a service implementation with fallback to default"
  def get(service_key, default_module) do
    Application.get_env(:wanderer_notifier, service_key, default_module)
  end

  # Pre-configured service getters for common dependencies
  def cache, do: get(:cache_module, WandererNotifier.Infrastructure.Cache)
  def http, do: get(:http_client, WandererNotifier.Infrastructure.Http)
  def discord, do: get(:discord_client, WandererNotifier.DiscordNotifier)
  def esi, do: get(:esi_service, WandererNotifier.Infrastructure.Adapters.ESI.Service)
end
```

### Step 1.2: Replace DependencyRegistry Calls
**Files to modify:**
- `lib/wanderer_notifier/application/services/application_service.ex:92`
- Search for all `DependencyRegistry.resolve` calls
- Replace with `Dependencies.get(key, default)`

### Step 1.3: Remove Complex DI Files
**Files to delete:**
- `lib/wanderer_notifier/application/services/dependency_registry.ex`
- `lib/wanderer_notifier/application/services/application_service/dependency_manager.ex`
- `lib/wanderer_notifier/application/services/dependencies.ex`

### Step 1.4: Update Application Supervision Tree
Remove `DependencyRegistry` from the supervision tree in `application.ex`

---

## Phase 2: Context Layer Elimination (High Priority)
**Duration**: 1-2 days  
**Risk**: Low (mostly wrapper functions)

### Step 2.1: Identify Context Usage
**Search and replace operations:**
```bash
# Find all ProcessingContext calls
grep -r "ProcessingContext\." lib/

# Find all ApiContext calls  
grep -r "ApiContext\." lib/
```

### Step 2.2: Replace ProcessingContext Calls
**Target file**: Any modules calling `ProcessingContext.process_killmail/1`

**Replace:**
```elixir
# Before
ProcessingContext.process_killmail(killmail_data)

# After - direct call with metrics
case Pipeline.process_killmail(killmail_data) do
  {:ok, result} = success ->
    ApplicationService.increment_metric(:killmail_processing_complete_success)
    success
  {:error, reason} = error ->
    ApplicationService.increment_metric(:killmail_processing_complete_error)
    error
end
```

### Step 2.3: Replace ApiContext Calls
**Common replacements:**
```elixir
# Before
ApiContext.get_character(character_id)
# After
WandererNotifier.Infrastructure.Adapters.ESI.Client.get_character_info(character_id)

# Before
ApiContext.get_tracked_systems()
# After
WandererNotifier.Domains.Tracking.MapTrackingClient.fetch_and_cache_systems()
```

### Step 2.4: Move Useful Functions
**Extract valuable functions** from contexts before deletion:
- Move caching logic from `ApiContext` to respective service modules
- Move validation logic from `ProcessingContext` to `Pipeline` module

### Step 2.5: Remove Context Files
**Files to delete:**
- `lib/wanderer_notifier/contexts/processing_context.ex`
- `lib/wanderer_notifier/contexts/api_context.ex`
- `lib/wanderer_notifier/contexts/` directory (if empty)

---

## Phase 3: Domain Structure Cleanup (Medium Priority)
**Duration**: 1 day  
**Risk**: Very Low (just file organization)

### Step 3.1: Audit Empty Directories
**Run script to find empty directories:**
```bash
find lib/wanderer_notifier/domains -type d -empty
```

### Step 3.2: Remove Empty Directories
**Directories to delete** (confirmed empty):
- `lib/wanderer_notifier/domains/killmail/entities/`
- `lib/wanderer_notifier/domains/killmail/services/`
- `lib/wanderer_notifier/domains/notifications/entities/`
- `lib/wanderer_notifier/domains/notifications/services/`
- `lib/wanderer_notifier/domains/license/entities/`
- `lib/wanderer_notifier/domains/license/services/`

### Step 3.3: Flatten Unnecessary Nesting
**Move files up one level** where directories contain only 1-2 files:
```bash
# Example: If pipeline/ directory only has one file
mv lib/wanderer_notifier/domains/killmail/pipeline/worker.ex \
   lib/wanderer_notifier/domains/killmail/pipeline_worker.ex
rmdir lib/wanderer_notifier/domains/killmail/pipeline/
```

### Step 3.4: Update Module Names
**Update module declarations** for moved files:
```elixir
# Before (in subdirectory)
defmodule WandererNotifier.Domains.Killmail.Pipeline.Worker

# After (flattened)  
defmodule WandererNotifier.Domains.Killmail.PipelineWorker
```

### Step 3.5: Update Import Statements
**Find and update all imports** for renamed modules:
```bash
grep -r "Pipeline.Worker" lib/
# Replace with PipelineWorker
```

---

## Phase 4: Application Service Simplification (Medium Priority)  
**Duration**: 2 days  
**Risk**: Medium (core service changes)

### Step 4.1: Extract Focused Services
**Create separate focused modules:**

```elixir
# lib/wanderer_notifier/shared/metrics.ex
defmodule WandererNotifier.Shared.Metrics do
  @moduledoc "Simple metrics tracking without GenServer overhead"
  
  use Agent
  
  def start_link(_opts) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end
  
  def increment(type) do
    Agent.update(__MODULE__, fn state ->
      update_in(state, [:counters, type], &(&1 + 1))
    end)
  end
  
  def get_stats do
    Agent.get(__MODULE__, & &1)
  end
  
  defp initial_state do
    %{
      counters: %{},
      startup_time: DateTime.utc_now(),
      notifications_sent: %{kill: false, character: false, system: false}
    }
  end
end
```

```elixir
# lib/wanderer_notifier/shared/health.ex  
defmodule WandererNotifier.Shared.Health do
  @moduledoc "Simple health checking without complex state management"
  
  def check_all_services do
    %{
      cache: check_cache(),
      http: check_http(),
      discord: check_discord(),
      status: overall_status()
    }
  end
  
  defp check_cache do
    case WandererNotifier.Infrastructure.Cache.get("health_check") do
      {:ok, _} -> :healthy
      {:error, :not_found} -> :healthy  
      _ -> :degraded
    end
  end
  
  # ... other simple health checks
end
```

### Step 4.2: Replace ApplicationService Calls
**Search and replace throughout codebase:**
```elixir
# Before
ApplicationService.increment_metric(:some_metric)

# After  
WandererNotifier.Shared.Metrics.increment(:some_metric)

# Before
ApplicationService.get_stats()

# After
WandererNotifier.Shared.Metrics.get_stats()
```

### Step 4.3: Remove ApplicationService Complexity
**Files to significantly simplify or delete:**
- `lib/wanderer_notifier/application/services/application_service.ex` (reduce to < 100 lines)
- `lib/wanderer_notifier/application/services/application_service/metrics_tracker.ex` (delete)
- `lib/wanderer_notifier/application/services/application_service/state.ex` (delete)

---

## Phase 5: Configuration Streamlining (Low Priority)
**Duration**: 1 day  
**Risk**: Low (mostly simplification)

### Step 5.1: Replace ConfigurationManager with Simple Functions
```elixir
# lib/wanderer_notifier/shared/simple_config.ex
defmodule WandererNotifier.Shared.SimpleConfig do
  @moduledoc "Simplified configuration access"
  
  # Discord config
  def discord_bot_token, do: get_required_env("DISCORD_BOT_TOKEN")
  def discord_channel_id, do: get_required_env("DISCORD_CHANNEL_ID") 
  def discord_application_id, do: get_env("DISCORD_APPLICATION_ID")
  
  # Feature flags
  def notifications_enabled?, do: get_boolean("NOTIFICATIONS_ENABLED", true)
  def kill_notifications_enabled?, do: get_boolean("KILL_NOTIFICATIONS_ENABLED", true)
  
  # Service URLs  
  def websocket_url, do: get_env("WEBSOCKET_URL", "ws://host.docker.internal:4004")
  def wanderer_kills_url, do: get_env("WANDERER_KILLS_URL", "http://host.docker.internal:4004")
  
  defp get_env(key, default \\ nil) do
    System.get_env(key, default)
  end
  
  defp get_required_env(key) do
    System.get_env(key) || raise "Missing required environment variable: #{key}"
  end
  
  defp get_boolean(key, default) do
    case System.get_env(key) do
      nil -> default
      "true" -> true  
      "false" -> false
      _ -> default
    end
  end
end
```

### Step 5.2: Replace Configuration Calls
**Throughout codebase:**
```elixir
# Before
WandererNotifier.Shared.Config.ConfigurationManager.get_service_config(:discord)

# After
WandererNotifier.Shared.SimpleConfig.discord_bot_token()
```

### Step 5.3: Remove Complex Config Files
**Files to delete:**
- `lib/wanderer_notifier/shared/config/configuration_manager.ex`
- `lib/wanderer_notifier/shared/config/config_behaviour.ex`
- `lib/wanderer_notifier/shared/config/config_provider.ex`

Keep: `lib/wanderer_notifier/shared/config.ex` (main config module)

---

## Testing Strategy

### Testing Requirements for Each Phase

**Phase 1 (Dependency Consolidation):**
```bash
# Before making changes
make test.all  # Ensure baseline passes

# Test dependency resolution
make test.killmail
make test.license
make test.infrastructure

# Integration test  
make s  # Start shell and test basic functionality
```

**Phase 2 (Context Elimination):**
```bash
# Test direct calls work
make test.killmail  # Verify Pipeline.process_killmail/1 works directly
make test.infrastructure  # Verify ESI calls work directly

# End-to-end test
# Send test killmail and verify notification works
```

**Phases 3-5 (Structural cleanup):**
```bash
make compile  # Ensure no compilation errors
make test.all  # Full test suite
make credo --strict  # Code quality
make dialyzer  # Type checking
```

### Risk Mitigation

**High-Risk Changes (Phases 1, 4):**
- Make changes in small commits
- Test after each major module change
- Keep application running in dev mode throughout
- Use feature flags to toggle between old/new implementations during transition

**Low-Risk Changes (Phases 2, 3, 5):**
- Can be done in larger batches
- Primarily file moves and deletions
- Easy to revert if needed

### Success Metrics

**Quantitative improvements expected:**
- **Lines of code reduction**: ~15-20% overall
- **File count reduction**: ~12-15 files removed
- **Module dependencies**: Simplified import graphs
- **Test complexity**: Fewer mocks needed

**Qualitative improvements:**
- Direct function calls instead of layers of indirection  
- Clear data flow from killmail → processing → notification
- Easier debugging with fewer abstraction layers
- Simplified onboarding for new developers

## Implementation Timeline

**Week 1**: 
- **Day 1-2**: Phase 1 (Dependency Consolidation) 
- **Day 3**: Phase 2 (Context Elimination)
- **Day 4**: Phase 3 (Domain Cleanup)  
- **Day 5**: Testing and validation

**Week 2**:
- **Day 1-2**: Phase 4 (Application Service Simplification)
- **Day 3**: Phase 5 (Configuration Streamlining)  
- **Day 4-5**: Final testing, documentation updates, performance validation

## Next Steps

1. **Start with Phase 1** - it has the highest impact on reducing complexity
2. **Work incrementally** - commit after each major change within a phase
3. **Test continuously** - run `make test` after each major modification
4. **Update CLAUDE.md** after completion to reflect the simplified architecture

## Key Benefits

- **Reduced cognitive load**: Fewer layers to understand
- **Easier testing**: Less mocking and setup required  
- **Better performance**: Fewer function calls and GenServer operations
- **Simpler debugging**: Direct function calls instead of multiple indirection layers
- **Easier onboarding**: Less architectural complexity for new developers

This plan maintains all functionality while significantly reducing architectural complexity. The phased approach minimizes risk and allows for easy rollback if issues arise.