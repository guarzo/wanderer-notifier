ExUnit.start()

# Set up application environment for testing
Application.put_env(:wanderer_notifier, :zkill_client, WandererNotifier.MockZKillClient)
Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.MockESI)
Application.put_env(:wanderer_notifier, :cache_helpers, WandererNotifier.MockCacheHelpers)
Application.put_env(:wanderer_notifier, :repository, WandererNotifier.MockRepository)
Application.put_env(:wanderer_notifier, :logger, WandererNotifier.MockLogger)

Application.put_env(
  :wanderer_notifier,
  :killmail_persistence,
  WandererNotifier.MockKillmailPersistence
)

Application.put_env(
  :wanderer_notifier,
  :cache_repo_module,
  WandererNotifier.Data.Cache.RepositoryMock
)

# Define mocks for external dependencies
Mox.defmock(WandererNotifier.MockZKillClient, for: WandererNotifier.Api.ZKill.ClientBehaviour)
Mox.defmock(WandererNotifier.MockESI, for: WandererNotifier.Api.ESI.ServiceBehaviour)
Mox.defmock(WandererNotifier.MockLogger, for: WandererNotifier.LoggerBehaviour)
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.HTTP.Behaviour)
Mox.defmock(WandererNotifier.MockCache, for: WandererNotifier.Cache.Behaviour)

Mox.defmock(WandererNotifier.MockCacheHelpers,
  for: WandererNotifier.Helpers.CacheHelpersBehaviour
)

Mox.defmock(WandererNotifier.MockRepository, for: WandererNotifier.Data.Cache.RepositoryBehaviour)

Mox.defmock(WandererNotifier.MockKillmailPersistence,
  for: WandererNotifier.Resources.KillmailPersistenceBehaviour
)

# Set Mox global mode for tests
Mox.defmock(WandererNotifier.Data.Cache.RepositoryMock,
  for: WandererNotifier.Data.Cache.RepositoryBehaviour
)

Application.put_env(:mox, :verify_on_exit, true)

# Define mocks for our new behaviors
Mox.defmock(WandererNotifier.MockKillmailChartAdapter,
  for: WandererNotifier.Adapters.KillmailChartAdapterBehaviour
)

Mox.defmock(WandererNotifier.MockConfig, for: WandererNotifier.Core.ConfigBehaviour)

# Needed for cache_helpers_test.exs
defmodule WandererNotifier.Data.Cache.RepositoryBehavior do
  @callback get(String.t()) :: any()
  @callback put(String.t(), any()) :: :ok
  @callback delete(String.t()) :: :ok
  @callback get_and_update(String.t(), (any() -> {any(), any()})) :: any()
  @callback exists?(String.t()) :: boolean()
  @callback set(String.t(), any(), non_neg_integer() | nil) :: :ok
end

Mox.defmock(WandererNotifier.Data.Cache.RepositoryMock,
  for: WandererNotifier.Data.Cache.RepositoryBehavior
)

# Set up application environment for testing
Application.put_env(:wanderer_notifier, :config_module, WandererNotifier.MockConfig)

Application.put_env(
  :wanderer_notifier,
  :killmail_chart_adapter_module,
  WandererNotifier.MockKillmailChartAdapter
)

Application.put_env(:wanderer_notifier, :cache_helpers_module, WandererNotifier.MockCacheHelpers)
