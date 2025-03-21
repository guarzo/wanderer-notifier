defmodule WandererNotifier.Core.Features do
  @moduledoc """
  Feature flags for WandererNotifier.
  Provides functions to check if specific features are enabled.
  """
  require Logger
  alias WandererNotifier.Core.License

  # Define feature flags
  @features %{
    # Core features - available even with invalid license
    core: [
      :basic_notifications,
      :web_dashboard_basic,
      :license_status_display,
      # Added these features to core to enable them even without a license
      :tracked_systems_notifications,
      :tracked_characters_notifications,
      :system_tracking
    ],

    # Standard features - require valid license
    standard: [
      :web_dashboard_full
    ],

    # Premium features - require valid license and premium tier
    premium: [
      :advanced_statistics,
      :character_tracking_unlimited,
      :system_tracking_unlimited,
      :custom_notification_templates
    ]
  }

  # Maximum limits for free/invalid license
  @free_limits %{
    # Changed from 10 to nil (unlimited)
    tracked_systems: nil,
    # Changed from 20 to nil (unlimited)
    tracked_characters: nil,
    # hours
    notification_history: 24
  }

  # Maximum limits for standard license
  @standard_limits %{
    # unlimited
    tracked_systems: nil,
    # unlimited
    tracked_characters: nil,
    # hours
    notification_history: 72
  }

  @doc """
  Checks if a specific feature is enabled based on the current license status.
  """
  def enabled?(feature) do
    # Special case for character tracking - check if it's explicitly enabled in config
    cond do
      feature == :tracked_characters_notifications ->
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

      # Special case for system tracking notifications - check if it's explicitly enabled in config
      feature == :tracked_systems_notifications ->
        system_notifications_enabled? =
          WandererNotifier.Core.Config.system_notifications_enabled?()

        if system_notifications_enabled? do
          # If enabled in config, continue with normal license check
          Logger.debug("[Features] System notifications are enabled (default), checking license")
          check_license_for_feature(feature)
        else
          Logger.debug("[Features] System notifications are explicitly disabled in configuration")
          false
        end

      true ->
        check_license_for_feature(feature)
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
        %{valid: true, premium: true} ->
          # Premium license - all features enabled
          true

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
    cond do
      # If license is invalid or bot not assigned, use free limits
      not License.status().valid or not License.status().bot_assigned ->
        Map.get(@free_limits, resource)

      # If premium, unlimited (nil means no limit)
      License.premium?() ->
        nil

      # Otherwise use standard limits
      true ->
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
    cond do
      # If license is invalid or bot not assigned, use free limits
      not License.status().valid or not License.status().bot_assigned ->
        @free_limits

      # If premium, unlimited
      License.premium?() ->
        Map.new(@free_limits, fn {k, _} -> {k, nil} end)

      # Otherwise use standard limits
      true ->
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
    case System.get_env("ENABLE_KILL_NOTIFICATIONS") do
      "false" -> false
      "0" -> false
      # Default to true if not set
      nil -> true
      # Any other value is considered true
      _ -> true
    end
  end

  @doc """
  Convenience function to check if all systems should be tracked,
  delegating to Config.track_all_systems?
  """
  def track_all_systems? do
    WandererNotifier.Core.Config.track_all_systems?()
  end

  @doc """
  Convenience function to check if all kills should be processed for notifications.
  By default, only specific systems' kills are tracked unless explicitly enabled.

  Setting PROCESS_ALL_KILLS=true in the environment is useful for testing kill notifications.
  """
  def process_all_kills? do
    case System.get_env("PROCESS_ALL_KILLS") do
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

    # Premium features - safely handle missing premium key
    license_status = License.status()
    is_premium = Map.get(license_status, :premium, false)

    premium_features =
      Map.new(@features.premium, fn feature ->
        {feature, license_status.valid && is_premium}
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
      # Tracking all systems
      tracking_all_systems: track_all_systems?(),
      # Activity charts status
      activity_charts: WandererNotifier.Core.Config.activity_charts_enabled?()
    }

    # Merge all feature maps
    Map.merge(core_features, standard_features)
    |> Map.merge(premium_features)
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
end
