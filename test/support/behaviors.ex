defmodule WandererNotifier.Cache.Behaviour do
  @callback put(any()) :: any()
  @callback get(any()) :: any()
  @callback exists?(any()) :: boolean()
end

defmodule WandererNotifier.Cache.HelpersBehaviour do
  @callback clear_cache() :: any()
  @callback clear_for_key(any()) :: any()
end

defmodule WandererNotifier.Api.ESI.Behaviour do
  @callback fetch_data(any()) :: any()
end

defmodule WandererNotifier.Api.ESI.ServiceBehaviour do
  @callback get_killmail(any()) :: any()
  @callback get_killmail(any(), any()) :: any()
end

defmodule WandererNotifier.Api.ZKill.ServiceBehaviour do
  @callback fetch_killmail(any()) :: any()
end

defmodule WandererNotifier.Api.ZKill.ClientBehaviour do
  @callback get_single_killmail(any()) :: any()
  @callback get_system_kills(any(), any()) :: any()
  @callback get_character_kills(any(), any(), any()) :: any()
  @callback get_recent_kills(any()) :: any()
end

defmodule WandererNotifier.Logger.LoggerBehaviour do
  @callback log(any(), any()) :: any()
end

defmodule WandererNotifier.Data.RepositoryBehaviour do
  @callback query(any()) :: any()
end

defmodule WandererNotifier.Config.Behaviour do
  @callback get(any()) :: any()
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
  @callback kill_notifications_enabled?() :: boolean()
  @callback get_map_config() :: map()
  @callback static_info_cache_ttl() :: integer()
  @callback get_env(atom(), any(), any()) :: any()
  @callback get_feature_status() :: map()
end

defmodule WandererNotifier.DateBehaviour do
  @callback now() :: any()
  @callback utc_today() :: Date.t()
  @callback day_of_week(Date.t()) :: integer()
end

defmodule WandererNotifier.Notifiers.FactoryBehaviour do
  @callback create(any()) :: any()
end

defmodule WandererNotifier.Data.Cache.RepositoryBehaviour do
  @callback get(any()) :: any()
  @callback put(any(), any()) :: any()
  @callback delete(any()) :: any()
  @callback set(any(), any(), any()) :: any()
  @callback clear() :: any()
  @callback exists?(any()) :: boolean()
  @callback get_and_update(any(), any()) :: any()
  @callback get_tracked_characters() :: any()
end

defmodule WandererNotifier.Notifiers.StructuredFormatterBehaviour do
  @callback format_system_status_message(
              String.t(),
              String.t(),
              map(),
              String.t(),
              map(),
              map(),
              integer(),
              integer()
            ) :: map()

  @callback to_discord_format(map()) :: map()
end
