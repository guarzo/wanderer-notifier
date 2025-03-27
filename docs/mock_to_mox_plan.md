# Mock to Mox Migration Plan

## Phase 1 Results: Inventory and Analysis

### Test Files Using Mock

- `test/wanderer_notifier/schedulers/killmail_chart_scheduler_test.exs`
- `test/wanderer_notifier/services/character_kills_service_test.exs`

### Modules Being Mocked

- WandererNotifier.Api.ZKill.Client
- WandererNotifier.Api.ESI.Service
- WandererNotifier.Data.Cache.Repository
- WandererNotifier.Resources.KillmailPersistence
- WandererNotifier.Helpers.CacheHelpers
- WandererNotifier.Core.Config
- Date
- WandererNotifier.ChartService.KillmailChartAdapter

### Existing Behavior Interfaces

- WandererNotifier.HTTP.Behaviour
- WandererNotifier.Notifiers.Behaviour
- WandererNotifier.Api.Http.ClientBehaviour
- WandererNotifier.Api.ESI.ServiceBehaviour
- WandererNotifier.WebSocket.Behaviour
- WandererNotifier.NotifierBehaviour
- WandererNotifier.Discord.Behaviour
- WandererNotifier.Discord.ApiBehaviour
- WandererNotifier.Cache.Behaviour
- WandererNotifier.Schedulers.Behaviour
- WandererNotifier.Data.Cache.RepositoryBehavior (defined in test_helper.exs)

### Missing Behavior Interfaces

- WandererNotifier.Api.ZKill.ClientBehaviour
- WandererNotifier.Resources.KillmailPersistenceBehaviour
- WandererNotifier.Helpers.CacheHelpersBehaviour
- WandererNotifier.ChartService.KillmailChartAdapterBehaviour
- WandererNotifier.Core.ConfigBehaviour

## Phase 2: Creating Missing Behavior Interfaces

### 1. ZKill Client Behaviour

```elixir
# lib/wanderer_notifier/api/zkill/client_behaviour.ex
defmodule WandererNotifier.Api.ZKill.ClientBehaviour do
  @callback get_single_killmail(kill_id :: integer) ::
    {:ok, map()} | {:error, term()}

  @callback get_recent_kills(limit :: integer) ::
    {:ok, list(map())} | {:error, term()}

  @callback get_system_kills(system_id :: integer, limit :: integer) ::
    {:ok, list(map())} | {:error, term()}

  @callback get_character_kills(character_id :: integer, limit :: integer, page :: integer) ::
    {:ok, list(map())} | {:error, term()}
end
```

### 2. KillmailPersistence Behaviour

```elixir
# lib/wanderer_notifier/resources/killmail_persistence_behaviour.ex
defmodule WandererNotifier.Resources.KillmailPersistenceBehaviour do
  @callback maybe_persist_killmail(killmail :: map()) ::
    {:ok, map()} | {:error, term()}
end
```

### 3. CacheHelpers Behaviour

```elixir
# lib/wanderer_notifier/helpers/cache_helpers_behaviour.ex
defmodule WandererNotifier.Helpers.CacheHelpersBehaviour do
  @callback get_tracked_characters() :: list(map())
end
```

### 4. KillmailChartAdapter Behaviour

```elixir
# lib/wanderer_notifier/chart_service/killmail_chart_adapter_behaviour.ex
defmodule WandererNotifier.ChartService.KillmailChartAdapterBehaviour do
  @callback send_weekly_kills_chart_to_discord(
    channel_id :: String.t(),
    date_from :: Date.t(),
    date_to :: Date.t()
  ) :: {:ok, map()} | {:error, term()}
end
```

### 5. Config Behaviour

```elixir
# lib/wanderer_notifier/core/config_behaviour.ex
defmodule WandererNotifier.Core.ConfigBehaviour do
  @callback discord_channel_id_for(feature :: atom()) :: String.t()
  @callback kill_charts_enabled?() :: boolean()
end
```

## Phase 2 Implementation Steps

1. **Create Each Behavior Interface File**

   - Use the templates above as a starting point
   - Add any additional functions used in mocks
   - Add proper typespec documentation

2. **Update Each Module to Implement Its Behavior**

   - Add `@behaviour ModuleName.Behaviour` to each module
   - Ensure function signatures match the behavior specifications
   - Add `@impl true` to implemented functions

3. **Register Mocks in test_helper.exs**

   ```elixir
   # Add to test/test_helper.exs
   Mox.defmock(WandererNotifier.MockZKillClient, for: WandererNotifier.Api.ZKill.ClientBehaviour)
   Mox.defmock(WandererNotifier.MockKillmailPersistence, for: WandererNotifier.Resources.KillmailPersistenceBehaviour)
   Mox.defmock(WandererNotifier.MockCacheHelpers, for: WandererNotifier.Helpers.CacheHelpersBehaviour)
   Mox.defmock(WandererNotifier.MockKillmailChartAdapter, for: WandererNotifier.ChartService.KillmailChartAdapterBehaviour)
   Mox.defmock(WandererNotifier.MockConfig, for: WandererNotifier.Core.ConfigBehaviour)
   ```

4. **Special Cases**
   - For Elixir standard library modules like `Date`, we'll need to use Mox's pass-through functionality

## Example Implementation for ZKill Client

1. Create the behavior interface file (as shown above)

2. Update the existing client module:

```elixir
defmodule WandererNotifier.Api.ZKill.Client do
  @moduledoc """
  Client for interacting with the zKillboard API.
  Handles making HTTP requests to the zKillboard API endpoints.
  """

  @behaviour WandererNotifier.Api.ZKill.ClientBehaviour

  # ... existing code ...

  @impl true
  def get_single_killmail(kill_id) do
    # ... existing implementation ...
  end

  @impl true
  def get_recent_kills(limit \\ 10) do
    # ... existing implementation ...
  end

  @impl true
  def get_system_kills(system_id, limit \\ 5) do
    # ... existing implementation ...
  end

  @impl true
  def get_character_kills(character_id, limit \\ 25, page \\ 1) do
    # ... existing implementation ...
  end

  # ... rest of implementation ...
end
```

## Implementation Timeline for Phase 2

- Day 1: Create behavior interfaces for ZKill Client and ESI Service
- Day 2: Create behavior interfaces for KillmailPersistence and CacheHelpers
- Day 3: Create behavior interfaces for remaining modules and update test_helper.exs

## Testing Strategy

After creating each behavior interface and updating its implementation:

1. Run the existing tests to verify nothing breaks
2. Create a simple test with Mox to verify the behavior works as expected
3. Document any edge cases or issues encountered

## Expected Challenges

1. **Standard Library Mocking**: For modules like `Date`, we'll need special handling
2. **Default Arguments**: Ensure behavior callbacks handle default arguments correctly
3. **Dynamic Functions**: Some mocks might use functions not defined in the original modules
