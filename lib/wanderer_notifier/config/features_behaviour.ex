defmodule WandererNotifier.Config.FeaturesBehaviour do
  @moduledoc """
  Behaviour module for feature configuration.
  """

  @callback config() :: map()
  @callback refresh_cache() :: map()
  @callback get_all_limits() :: map()
  @callback get_limit(atom(), integer()) :: integer()
  @callback get_feature(atom() | String.t(), boolean()) :: boolean()
  @callback enabled?(atom()) :: boolean()
  @callback notifications_enabled?() :: boolean()
  @callback kill_notifications_enabled?() :: boolean()
  @callback character_notifications_enabled?() :: boolean()
  @callback system_notifications_enabled?() :: boolean()
  @callback tracked_systems_notifications_enabled?() :: boolean()
  @callback tracked_characters_notifications_enabled?() :: boolean()
  @callback character_tracking_enabled?() :: boolean()
  @callback system_tracking_enabled?() :: boolean()
  @callback track_kspace_systems?() :: boolean()
  @callback kill_charts_enabled?() :: boolean()
  @callback map_charts_enabled?() :: boolean()
  @callback test_mode_enabled?() :: boolean()
  @callback should_load_tracking_data?() :: boolean()
  @callback discord_channel_id_for_activity_charts() :: String.t() | nil
  @callback static_info_cache_ttl() :: integer()
  @callback get_feature_status() :: map()
  @callback validate() :: :ok | {:error, [String.t()]}
end
