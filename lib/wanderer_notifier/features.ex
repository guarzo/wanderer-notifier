defmodule WandererNotifier.Features do
  @moduledoc """
  Feature management for WandererNotifier.
  Handles feature availability based on license status.
  """
  require Logger
  alias WandererNotifier.License

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
      :backup_kills_processing
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
    tracked_systems: nil,  # Changed from 10 to nil (unlimited)
    tracked_characters: nil,  # Changed from 20 to nil (unlimited)
    notification_history: 24 # hours
  }

  # Maximum limits for standard license
  @standard_limits %{
    tracked_systems: nil, # unlimited
    tracked_characters: nil, # unlimited
    notification_history: 72 # hours
  }

  @doc """
  Checks if a specific feature is enabled based on the current license status.
  """
  def enabled?(feature) do
    # Special case for character tracking - check if it's explicitly enabled in config
    cond do
      feature == :tracked_characters_notifications ->
        character_tracking_config_enabled? = WandererNotifier.Config.character_tracking_enabled?()
        character_notifications_enabled? = WandererNotifier.Config.character_notifications_enabled?()

        if not character_tracking_config_enabled? or not character_notifications_enabled? do
          Logger.debug("[Features] Character tracking or notifications are explicitly disabled in configuration")
          false
        else
          # If enabled in config, continue with normal license check
          Logger.debug("[Features] Character tracking and notifications are enabled (default), checking license")
          check_license_for_feature(feature)
        end

      # Special case for system tracking notifications - check if it's explicitly enabled in config
      feature == :tracked_systems_notifications ->
        system_notifications_enabled? = WandererNotifier.Config.system_notifications_enabled?()

        if not system_notifications_enabled? do
          Logger.debug("[Features] System notifications are explicitly disabled in configuration")
          false
        else
          # If enabled in config, continue with normal license check
          Logger.debug("[Features] System notifications are enabled (default), checking license")
          check_license_for_feature(feature)
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
end
