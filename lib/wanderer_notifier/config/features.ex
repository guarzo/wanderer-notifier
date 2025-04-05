defmodule WandererNotifier.Config.Features do
  @moduledoc """
  Configuration module for feature flags and limits.

  This module centralizes all feature flag configuration access,
  providing a standardized interface for retrieving feature settings
  and validating configuration values. It handles:

  - Notification features
  - Tracking features
  - Chart features
  - Resource limits
  """

  # Cache the feature status for improved performance
  # This is refreshed when the application starts or when explicitly asked to
  @feature_cache_key :features_cache

  @doc """
  Returns the complete features configuration map.
  """
  @spec config() :: map()
  def config do
    # Check if we have cached the features
    cached_features = Process.get(@feature_cache_key)

    if is_nil(cached_features) do
      # If not cached, compute and cache the features
      features_map = get_env(:features, %{})

      # Merge the raw features map with computed values
      features =
        features_map
        |> Map.merge(%{
          limits: get_all_limits(),
          loaded_tracking_data: should_load_tracking_data?()
        })

      # Cache the result
      Process.put(@feature_cache_key, features)
      features
    else
      # Return the cached result
      cached_features
    end
  end

  @doc """
  Refreshes the cached feature configuration.
  Call this when configuration changes at runtime.
  """
  def refresh_cache do
    Process.delete(@feature_cache_key)
    config()
  end

  @doc """
  Gets all resource limits.

  Returns a map containing the limits for tracked systems, characters, and notification history.
  """
  @spec get_all_limits() :: map()
  def get_all_limits do
    %{
      tracked_systems: get_limit(:tracked_systems, 1000),
      tracked_characters: get_limit(:tracked_characters, 500),
      notification_history: get_limit(:notification_history, 1000)
    }
  end

  @doc """
  Gets a limit for a specific resource.

  ## Parameters
    - resource: The resource to get the limit for
    - default: The default value if no limit is configured
  """
  @spec get_limit(atom(), integer()) :: integer()
  def get_limit(resource, default \\ nil) do
    get_env(resource, default)
  end

  @doc """
  Gets a feature flag from the features map.

  ## Parameters
    - key: The feature key to look up (atom or string)
    - default: The default value if the feature is not configured
  """
  @spec get_feature(atom() | String.t(), boolean()) :: boolean()
  def get_feature(key, default \\ false) do
    features_map = get_env(:features, %{})

    # Try both atom and string keys
    atom_key = if is_atom(key), do: key, else: String.to_atom("#{key}")
    string_key = if is_binary(key), do: key, else: Atom.to_string(key)

    # Check if each key exists
    atom_exists = Map.has_key?(features_map, atom_key)
    string_exists = Map.has_key?(features_map, string_key)

    # Get the value based on which key exists
    cond do
      atom_exists -> Map.get(features_map, atom_key)
      string_exists -> Map.get(features_map, string_key)
      true -> default
    end
  end

  @doc """
  Checks if a specific feature is enabled.

  ## Parameters
    - feature: The feature to check (atom)
  """
  @spec enabled?(atom()) :: boolean()
  def enabled?(feature) when is_atom(feature) do
    get_feature(feature, false)
  end

  #
  # Notification feature checks
  #

  @doc """
  Checks if notifications are enabled globally.
  """
  @spec notifications_enabled?() :: boolean()
  def notifications_enabled? do
    get_feature(:notifications_enabled, true)
  end

  @doc """
  Checks if kill notifications are enabled.
  """
  @spec kill_notifications_enabled?() :: boolean()
  def kill_notifications_enabled? do
    notifications_enabled?() && get_feature(:kill_notifications_enabled, true)
  end

  @doc """
  Checks if character notifications are enabled.
  """
  @spec character_notifications_enabled?() :: boolean()
  def character_notifications_enabled? do
    notifications_enabled?() && get_feature(:character_notifications_enabled, true)
  end

  @doc """
  Checks if system notifications are enabled.
  """
  @spec system_notifications_enabled?() :: boolean()
  def system_notifications_enabled? do
    notifications_enabled?() && get_feature(:system_notifications_enabled, true)
  end

  @doc """
  Checks if tracked systems notifications are enabled.
  """
  @spec tracked_systems_notifications_enabled?() :: boolean()
  def tracked_systems_notifications_enabled? do
    notifications_enabled?() && get_feature(:tracked_systems_notifications_enabled, true)
  end

  @doc """
  Checks if tracked characters notifications are enabled.
  """
  @spec tracked_characters_notifications_enabled?() :: boolean()
  def tracked_characters_notifications_enabled? do
    notifications_enabled?() && get_feature(:tracked_characters_notifications_enabled, true)
  end

  #
  # Tracking feature checks
  #

  @doc """
  Checks if character tracking is enabled.
  """
  @spec character_tracking_enabled?() :: boolean()
  def character_tracking_enabled? do
    get_feature(:character_tracking_enabled, true)
  end

  @doc """
  Checks if system tracking is enabled.
  """
  @spec system_tracking_enabled?() :: boolean()
  def system_tracking_enabled? do
    get_feature(:system_tracking_enabled, true)
  end

  @doc """
  Checks if tracking k-space systems is enabled.
  """
  @spec track_kspace_systems?() :: boolean()
  def track_kspace_systems? do
    get_feature(:track_kspace_systems, true)
  end

  #
  # Charts feature checks
  #

  @doc """
  Checks if kill charts are enabled.
  """
  @spec kill_charts_enabled?() :: boolean()
  def kill_charts_enabled? do
    notifications_enabled?() && get_feature(:kill_charts_enabled, true)
  end

  @doc """
  Checks if map charts are enabled.
  """
  @spec map_charts_enabled?() :: boolean()
  def map_charts_enabled? do
    get_feature(:map_charts, false)
  end

  #
  # Miscellaneous feature checks
  #

  @doc """
  Checks if test mode is enabled.
  """
  @spec test_mode_enabled?() :: boolean()
  def test_mode_enabled? do
    get_feature(:test_mode_enabled, false)
  end

  @doc """
  Checks if status messages are disabled.
  """
  @spec status_messages_disabled?() :: boolean()
  def status_messages_disabled? do
    get_feature(:status_messages_disabled, false)
  end

  @doc """
  Check if we should load tracking data (systems and characters) for use in kill notifications.
  """
  @spec should_load_tracking_data?() :: boolean()
  def should_load_tracking_data? do
    kill_notifications_enabled?() || system_tracking_enabled?() || character_tracking_enabled?()
  end

  @doc """
  Gets the Discord channel ID for activity charts.
  """
  @spec discord_channel_id_for_activity_charts() :: String.t() | nil
  def discord_channel_id_for_activity_charts do
    get_env(:activity_charts_channel_id)
  end

  @doc """
  Gets the static info cache TTL in seconds.
  """
  @spec static_info_cache_ttl() :: integer()
  def static_info_cache_ttl do
    get_env(:static_info_cache_ttl, 3600)
  end

  @doc """
  Gets the status of all features.

  Returns a map containing the status of all configured features.
  """
  @spec get_feature_status() :: map()
  def get_feature_status do
    %{
      map_charts: map_charts_enabled?(),
      kill_charts: kill_charts_enabled?(),
      character_notifications_enabled: character_notifications_enabled?(),
      system_notifications_enabled: system_notifications_enabled?(),
      character_tracking_enabled: character_tracking_enabled?(),
      system_tracking_enabled: system_tracking_enabled?(),
      tracked_systems_notifications_enabled: tracked_systems_notifications_enabled?(),
      tracked_characters_notifications_enabled: tracked_characters_notifications_enabled?(),
      kill_notifications_enabled: kill_notifications_enabled?(),
      notifications_enabled: notifications_enabled?()
    }
  end

  @doc """
  Validates that all feature configuration values are valid.

  Returns :ok if the configuration is valid, or a list of errors if not.
  """
  @spec validate() :: :ok | {:error, [String.t()]}
  def validate do
    errors = []

    # All feature flags should be booleans
    features_map = get_env(:features, %{})

    invalid_features =
      features_map
      |> Enum.filter(fn {_key, value} -> not is_boolean(value) end)
      |> Enum.map(fn {key, value} -> "Feature '#{key}' has invalid value: #{inspect(value)}" end)

    errors = errors ++ invalid_features

    # All limits should be positive integers
    limits = get_all_limits()

    invalid_limits =
      limits
      |> Enum.filter(fn {_key, value} -> not (is_integer(value) and value > 0) end)
      |> Enum.map(fn {key, value} -> "Limit '#{key}' has invalid value: #{inspect(value)}" end)

    errors = errors ++ invalid_limits

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  # Private helper to get environment variables
  defp get_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
