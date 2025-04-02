defmodule WandererNotifier.Config.Behaviour do
  @moduledoc """
  Behaviour for configuration modules.
  """

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
  @callback get_feature_status() :: %{
              kill_notifications_enabled: boolean(),
              system_tracking_enabled: boolean(),
              character_tracking_enabled: boolean(),
              activity_charts: boolean()
            }
end
