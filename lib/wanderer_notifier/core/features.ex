defmodule WandererNotifier.Core.Features do
  @moduledoc """
  Feature flags for WandererNotifier.
  Provides functions to check if specific features are enabled.
  """
  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Core.License

  # Define feature flags
  @features %{
    # Core features - available even with invalid license
    core: [
      :basic_notifications,
      :tracked_systems_notifications,
      :tracked_characters_notifications,
      :system_tracking
    ],

    # Standard features - require valid license
    standard: [
      :kill_charts,
      :map_charts
    ]
  }

  # Maximum limits for free/invalid license
  @free_limits %{
    # No limits on tracking systems - previously was 10
    tracked_systems: nil,
    # No limits on tracking characters - previously was 20
    tracked_characters: nil,
    # hours of notification history
    notification_history: 24
  }

  # Maximum limits for standard license
  @standard_limits %{
    # No limits on tracking systems
    tracked_systems: nil,
    # No limits on tracking characters
    tracked_characters: nil,
    # hours of notification history
    notification_history: 72
  }

  @doc """
  Checks if a specific feature is enabled based on the current license status.
  """
  def enabled?(feature) do
    # Delegate to specific handler functions based on feature type
    cond do
      feature == :tracked_characters_notifications ->
        check_character_tracking_enabled(feature)

      feature == :tracked_systems_notifications ->
        check_system_tracking_enabled(feature)

      feature == :activity_charts ->
        WandererNotifier.Core.Config.map_charts_enabled?()

      feature == :kill_charts ->
        WandererNotifier.Core.Config.kill_charts_enabled?()

      feature == :map_charts ->
        WandererNotifier.Core.Config.map_charts_enabled?()

      true ->
        check_license_for_feature(feature)
    end
  end

  # Checks if character tracking notifications are enabled
  defp check_character_tracking_enabled(feature) do
    character_tracking_config_enabled? =
      WandererNotifier.Core.Config.character_tracking_enabled?()

    character_notifications_enabled? =
      WandererNotifier.Core.Config.character_notifications_enabled?()

    if not character_tracking_config_enabled? or not character_notifications_enabled? do
      Logger.debug(
        "[Features] Character tracking or notifications are explicitly disabled in configuration"
      )

      false
    else
      # If enabled in config, continue with normal license check
      Logger.debug(
        "[Features] Character tracking and notifications are enabled (default), checking license"
      )

      check_license_for_feature(feature)
    end
  end

  # Checks if system tracking notifications are enabled
  defp check_system_tracking_enabled(feature) do
    system_notifications_enabled? =
      WandererNotifier.Core.Config.system_notifications_enabled?()

    if system_notifications_enabled? do
      # If enabled in config, continue with normal license check
      AppLogger.config_debug(
        "[Features] System notifications are enabled (default), checking license"
      )

      check_license_for_feature(feature)
    else
      AppLogger.config_debug(
        "[Features] System notifications are explicitly disabled in configuration"
      )

      false
    end
  end

  # Helper function to check if a feature is enabled based on license status
  defp check_license_for_feature(feature) do
    # Check if the feature is in the core features list (always enabled)
    if feature in @features.core do
      true
    else
      # Check license status
      case License.status() do
        %{valid: true} ->
          # Standard license - standard features enabled
          feature in @features.standard

        _ ->
          # Invalid or no license - only core features
          false
      end
    end
  end

  @doc """
  Returns the limit for a specific resource based on the current license status.
  """
  def get_limit(resource) do
    # If license is invalid or bot not assigned, use free limits
    license_status = License.status()

    if not license_status.valid or not license_status.bot_assigned do
      Map.get(@free_limits, resource)
    else
      # Otherwise use standard limits
      Map.get(@standard_limits, resource)
    end
  end

  @doc """
  Checks if a limit has been reached for a specific resource.
  Returns true if the limit is reached or exceeded.
  """
  def limit_reached?(resource, current_count) do
    limit = get_limit(resource)

    # If limit is nil, there is no limit
    if is_nil(limit) do
      false
    else
      current_count >= limit
    end
  end

  @doc """
  Returns a map of all feature limits based on the current license status.
  """
  def get_all_limits do
    # If license is invalid or bot not assigned, use free limits
    license_status = License.status()

    if not license_status.valid or not license_status.bot_assigned do
      @free_limits
    else
      # Otherwise use standard limits
      @standard_limits
    end
  end

  @doc """
  Convenience function to check if tracked systems notifications are enabled.
  """
  def tracked_systems_notifications_enabled? do
    enabled?(:tracked_systems_notifications)
  end

  @doc """
  Convenience function to check if tracked characters notifications are enabled.
  """
  def tracked_characters_notifications_enabled? do
    enabled?(:tracked_characters_notifications)
  end

  @doc """
  Convenience function to check if kill notifications are enabled.
  """
  def kill_notifications_enabled? do
    case System.get_env("WANDERER_FEATURE_KILL_NOTIFICATIONS") do
      "false" -> false
      "0" -> false
      # Default to true if not set
      nil -> true
      # Any other value is considered true
      _ -> true
    end
  end

  @doc """
  Check if we should load tracking data (systems and characters) for use in kill notifications.
  This ensures that kill notifications can still function even when character/system
  notifications themselves are disabled.
  """
  def should_load_tracking_data? do
    # Always load tracking data if kill notifications are enabled
    # regardless of character/system notification settings
    kill_notifications_enabled?()
  end

  @doc """
  Convenience function to check if K-Space (non-wormhole) systems should be tracked,
  delegating to Config.track_kspace_systems?
  """
  def track_kspace_systems? do
    WandererNotifier.Core.Config.track_kspace_systems?()
  end

  @doc """
  Legacy function for backward compatibility.
  @deprecated Use track_kspace_systems?/0 instead
  """
  def track_all_systems? do
    track_kspace_systems?()
  end

  @doc """
  Convenience function to check if all kills should be processed for notifications.
  By default, only specific systems' kills are tracked unless explicitly enabled.

  Setting WANDERER_FEATURE_PROCESS_ALL_KILLS=true in the environment is useful for testing kill notifications.
  """
  def process_all_kills? do
    case System.get_env("WANDERER_FEATURE_PROCESS_ALL_KILLS") do
      "true" -> true
      "1" -> true
      # Default to false if not set
      nil -> false
      # Any other value is considered false
      _ -> false
    end
  end

  @doc """
  Returns a map of feature names and their status (enabled/disabled).
  Used for status reporting and debugging.
  """
  def get_feature_status do
    # Core features
    core_features = Map.new(@features.core, fn feature -> {feature, true} end)

    # Standard features
    standard_features =
      Map.new(@features.standard, fn feature ->
        {feature, License.status().valid}
      end)

    # Special overrides based on configuration
    special_features = %{
      # WebSocket connection status
      websocket_connected: get_websocket_status(),
      # Character tracking status (can be disabled in config)
      character_tracking_enabled: WandererNotifier.Core.Config.character_tracking_enabled?(),
      # System tracking status
      system_tracking_enabled: WandererNotifier.Core.Config.system_notifications_enabled?(),
      # Kill notifications status
      kill_notifications_enabled: kill_notifications_enabled?(),
      # Processing all kills (usually for testing)
      processing_all_kills: process_all_kills?(),
      # Tracking K-Space (non-wormhole) systems
      tracking_kspace_systems: track_kspace_systems?(),
      # Legacy key for backward compatibility
      tracking_all_systems: track_kspace_systems?(),
      # Activity charts status
      activity_charts: WandererNotifier.Core.Config.map_charts_enabled?()
    }

    # Merge all feature maps
    Map.merge(core_features, standard_features)
    |> Map.merge(special_features)
  end

  # Helper function to get WebSocket connection status from stats
  defp get_websocket_status do
    try do
      stats = WandererNotifier.Core.Stats.get_stats()
      Map.get(stats.websocket, :connected, false)
    rescue
      _ -> false
    end
  end

  @doc """
  Convenience function to check if system notifications are enabled.
  """
  def system_notifications_enabled? do
    WandererNotifier.Core.Config.system_notifications_enabled?()
  end

  @doc """
  Convenience function to check if character notifications are enabled.
  """
  def character_notifications_enabled? do
    WandererNotifier.Core.Config.character_notifications_enabled?()
  end

  @doc """
  Convenience function to check if activity charts are enabled.
  """
  def activity_charts_enabled? do
    enabled?(:activity_charts)
  end

  @doc """
  Convenience function to check if kill charts are enabled.
  """
  def kill_charts_enabled? do
    enabled?(:kill_charts)
  end

  @doc """
  Convenience function to check if map charts are enabled.
  """
  def map_charts_enabled? do
    enabled?(:map_charts)
  end
end
