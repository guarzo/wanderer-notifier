ExUnit.start()

# Set up application environment for testing
Application.put_env(:wanderer_notifier, :zkill_client, WandererNotifier.Api.ZKill.Client)
Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.Api.ESI.Service)
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
Mox.defmock(WandererNotifier.MockLogger, for: WandererNotifier.Logger.Behaviour)
Mox.defmock(WandererNotifier.MockHTTP, for: WandererNotifier.Api.Http.Behaviour)
Mox.defmock(WandererNotifier.MockWebSocket, for: WandererNotifier.Api.ZKill.WebSocketBehaviour)
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
  for: WandererNotifier.Data.Cache.CacheBehaviour
)

Application.put_env(:mox, :verify_on_exit, true)

# Define mocks for our new behaviors
defmodule WandererNotifier.Config.Behaviour do
  @callback map_url() :: String.t() | nil
  @callback map_token() :: String.t() | nil
  @callback map_csrf_token() :: String.t() | nil
  @callback map_name() :: String.t() | nil
  @callback notifier_api_token() :: String.t() | nil
  @callback license_key() :: String.t() | nil
  @callback license_manager_api_url() :: String.t() | nil
  @callback license_manager_api_key() :: String.t() | nil
  @callback discord_channel_id_for(atom()) :: String.t() | nil
  @callback discord_channel_id_for_activity_charts() :: String.t() | nil
  @callback kill_charts_enabled?() :: boolean()
  @callback map_charts_enabled?() :: boolean()
  @callback character_tracking_enabled?() :: boolean()
  @callback character_notifications_enabled?() :: boolean()
  @callback system_notifications_enabled?() :: boolean()
  @callback track_kspace_systems?() :: boolean()
  @callback get_map_config() :: map()
  @callback static_info_cache_ttl() :: integer()
  @callback get_env(atom(), any()) :: any()
  @callback get_feature_status() :: map()
end

Mox.defmock(WandererNotifier.MockConfig, for: WandererNotifier.Config.Behaviour)

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
Application.put_env(:wanderer_notifier, :cache_helpers_module, WandererNotifier.MockCacheHelpers)
Application.put_env(:wanderer_notifier, :notifier_factory, WandererNotifier.MockNotifierFactory)
Application.put_env(:wanderer_notifier, :date_module, WandererNotifier.MockDate)

Application.put_env(
  :wanderer_notifier,
  :killmail_chart_adapter,
  WandererNotifier.MockKillmailChartAdapter
)

# Define the KillmailChartAdapter behaviour
defmodule WandererNotifier.ChartService.KillmailChartAdapterBehaviour do
  @callback generate_weekly_kills_chart() :: {:ok, String.t()} | {:error, any()}
end

Mox.defmock(WandererNotifier.MockKillmailChartAdapter,
  for: WandererNotifier.ChartService.KillmailChartAdapterBehaviour
)

# Define the Date behaviour for mocking Date functions
defmodule WandererNotifier.DateBehaviour do
  @callback utc_today() :: Date.t()
  @callback day_of_week(Date.t()) :: non_neg_integer()
end

Mox.defmock(WandererNotifier.MockDate, for: WandererNotifier.DateBehaviour)

# Define the NotifierFactory behaviour
defmodule WandererNotifier.Notifiers.FactoryBehaviour do
  @callback notify(atom(), list()) :: {:ok, map()} | {:error, any()}
end

Mox.defmock(WandererNotifier.MockNotifierFactory,
  for: WandererNotifier.Notifiers.FactoryBehaviour
)

# Set up application environment for testing
Application.put_env(:wanderer_notifier, :notifier_factory, WandererNotifier.MockNotifierFactory)
