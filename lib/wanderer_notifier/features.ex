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
      :license_status_display
    ],
    
    # Standard features - require valid license
    standard: [
      :tracked_systems_notifications,
      :tracked_characters_notifications,
      :backup_kills_processing,
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
    tracked_systems: 5,
    tracked_characters: 10,
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
    cond do
      # Core features are always available
      feature in @features.core ->
        true
        
      # If license is invalid, only core features are available
      not License.status().valid ->
        Logger.debug("Feature #{feature} disabled: invalid license")
        false
        
      # If bot is not assigned, only core features are available
      not License.status().bot_assigned ->
        Logger.debug("Feature #{feature} disabled: bot not assigned")
        false
        
      # Standard features require valid license
      feature in @features.standard ->
        true
        
      # Premium features require premium tier
      feature in @features.premium ->
        License.premium?()
        
      # Unknown feature
      true ->
        Logger.warning("Unknown feature check: #{feature}")
        false
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
end
