defmodule WandererNotifier.Config.Behaviour do
  @moduledoc """
  Defines the behaviour for configuration in the WandererNotifier application.
  """

  @callback get_env(app :: atom(), key :: atom(), default :: term()) :: term()
  @callback map_url() :: String.t()
  @callback map_token() :: String.t()
  @callback map_csrf_token() :: String.t()
  @callback map_name() :: String.t()
  @callback notifier_api_token() :: String.t()
  @callback license_key() :: String.t()
  @callback license_manager_api_url() :: String.t()
  @callback license_manager_api_key() :: String.t()
  @callback discord_channel_id_for(feature :: atom()) :: String.t() | nil
  @callback character_tracking_enabled?() :: boolean()
  @callback character_notifications_enabled?() :: boolean()
  @callback system_notifications_enabled?() :: boolean()
  @callback track_kspace_systems?() :: boolean()
  @callback get_map_config() :: map()
  @callback static_info_cache_ttl() :: integer()
  @callback get_feature_status() :: map()
end
