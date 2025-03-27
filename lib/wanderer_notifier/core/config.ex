defmodule WandererNotifier.Core.Config do
  @moduledoc """
  Configuration management for WandererNotifier.
  Provides access to application configuration with sensible defaults.
  """
  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  # Constants for API URLs
  @zkill_base_url "https://zkillboard.com"
  @esi_base_url "https://esi.evetech.net/latest"
  @default_license_manager_url "https://lm.wanderer.ltd"
  @default_chart_service_port 3001
  @default_web_port 4000

  # Production bot API token - use environment variable or Application config
  # This should be set at runtime, not hardcoded
  @production_token_env "WANDERER_NOTIFIER_API_TOKEN"

  # Feature definitions with their environment variables - using new naming convention
  @features %{
    general: %{
      enabled_var: "WANDERER_FEATURE_NOTIFICATIONS",
      channel_var: "WANDERER_DISCORD_CHANNEL_ID",
      default_enabled: true,
      description: "General notifications"
    },
    kill_notifications: %{
      enabled_var: "WANDERER_FEATURE_KILL_NOTIFICATIONS",
      channel_var: "WANDERER_DISCORD_KILL_CHANNEL_ID",
      default_enabled: true,
      description: "Kill notifications"
    },
    system_tracking: %{
      enabled_var: "WANDERER_FEATURE_SYSTEM_NOTIFICATIONS",
      channel_var: "WANDERER_DISCORD_SYSTEM_CHANNEL_ID",
      default_enabled: true,
      description: "System tracking notifications"
    },
    character_tracking: %{
      enabled_var: "WANDERER_FEATURE_CHARACTER_NOTIFICATIONS",
      channel_var: "WANDERER_DISCORD_CHARACTER_CHANNEL_ID",
      default_enabled: true,
      description: "Character tracking notifications"
    },
    map_charts: %{
      enabled_var: "WANDERER_FEATURE_MAP_CHARTS",
      channel_var: "WANDERER_DISCORD_CHARTS_CHANNEL_ID",
      default_enabled: false,
      description: "Map-based activity charts"
    },
    kill_charts: %{
      enabled_var: "WANDERER_FEATURE_KILL_CHARTS",
      channel_var: "WANDERER_DISCORD_CHARTS_CHANNEL_ID",
      default_enabled: false,
      description: "Killmail charts and history"
    }
  }

  @doc """
  Returns the Discord bot token from the environment.
  """
  def discord_bot_token do
    Application.get_env(:wanderer_notifier, :discord_bot_token)
  end

  @doc """
  Returns the main Discord channel ID from the environment.
  """
  def discord_channel_id do
    Application.get_env(:wanderer_notifier, :discord_channel_id)
  end

  @doc """
  Returns the Discord channel ID for a specific feature.
  Falls back to the main channel ID if a feature-specific channel isn't defined.

  ## Parameters
    - feature: The feature to get the channel ID for (e.g., :kill_notifications)
  """
  def discord_channel_id_for(feature) when is_atom(feature) do
    feature_config = Map.get(@features, feature)

    if feature_config do
      channel_var = feature_config.channel_var
      channel_id = System.get_env(channel_var)

      if is_binary(channel_id) && channel_id != "" do
        channel_id
      else
        # Fall back to the main channel ID
        discord_channel_id()
      end
    else
      # Unknown feature, use the main channel
      AppLogger.config_warn("Unknown feature #{feature} when looking up Discord channel ID")
      discord_channel_id()
    end
  end

  @doc """
  Returns the Discord channel ID specifically for activity charts.
  """
  def discord_channel_id_for_activity_charts do
    discord_channel_id_for(:map_charts)
  end

  @doc """
  Returns whether a specific feature is enabled based on its environment variable.

  ## Parameters
    - feature: The feature to check (atom matching a key in @features)
  """
  def feature_enabled?(feature) when is_atom(feature) do
    feature_config = Map.get(@features, feature)

    if feature_config == nil do
      # Unknown feature, default to false for safety
      AppLogger.config_warn("Unknown feature #{feature} when checking if enabled")
      false
    else
      env_var = feature_config.enabled_var
      default_enabled = feature_config.default_enabled

      # Get environment variable value
      raw_value = System.get_env(env_var)

      # Process the value to determine if feature is enabled
      process_feature_flag_value(raw_value, default_enabled)
    end
  end

  # Process environment variable value to determine if feature is enabled
  defp process_feature_flag_value(raw_value, default_enabled) do
    cond do
      # Common true values
      raw_value in ["true", "1", "yes", "y"] ->
        true

      # Common false values
      raw_value in ["false", "0", "no", "n"] ->
        false

      # Handle nil (unset variable)
      is_nil(raw_value) ->
        default_enabled

      # Handle non-standard values by normalizing
      true ->
        downcased = String.trim(raw_value) |> String.downcase()
        normalize_flag_value(downcased, default_enabled)
    end
  end

  # Normalize unusual flag values
  defp normalize_flag_value(downcased, default_enabled) do
    cond do
      # Additional truthy values
      downcased in ["true", "yes", "y", "1", "on", "enabled"] -> true
      # Additional falsey values
      downcased in ["false", "no", "n", "0", "off", "disabled"] -> false
      # Use default for anything else
      true -> default_enabled
    end
  end

  @doc """
  Returns whether kill charts functionality is enabled.
  """
  def kill_charts_enabled? do
    # Use normal feature flag logic
    feature_enabled?(:kill_charts)
  end

  @doc """
  Returns whether map charts functionality is enabled.
  """
  def map_charts_enabled? do
    # Use normal feature flag logic
    feature_enabled?(:map_charts)
  end

  @doc """
  Returns whether kill notifications are enabled.
  """
  def kill_notifications_enabled? do
    feature_enabled?(:kill_notifications)
  end

  @doc """
  Returns whether system tracking notifications are enabled.
  """
  def system_notifications_enabled? do
    feature_enabled?(:system_tracking)
  end

  @doc """
  Returns whether character tracking notifications are enabled.
  """
  def character_notifications_enabled? do
    feature_enabled?(:character_tracking)
  end

  @doc """
  Returns the chart service port from the environment.
  Defaults to 3001 if not specified.
  """
  def chart_service_port do
    case System.get_env("WANDERER_CHART_SERVICE_PORT") do
      nil ->
        @default_chart_service_port

      port ->
        case Integer.parse(port) do
          {port_num, _} when port_num > 0 -> port_num
          _ -> @default_chart_service_port
        end
    end
  end

  @doc """
  Returns the map URL from the environment.
  If MAP_URL_WITH_NAME is set, it will be used.
  Otherwise, it will construct the URL from MAP_URL and MAP_NAME.
  """
  def map_url do
    case Application.get_env(:wanderer_notifier, :map_url_with_name) do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        base_url = Application.get_env(:wanderer_notifier, :map_url)
        map_name = Application.get_env(:wanderer_notifier, :map_name)

        if is_binary(base_url) and is_binary(map_name) and base_url != "" and map_name != "" do
          "#{base_url}/#{map_name}"
        else
          nil
        end
    end
  end

  @doc """
  Returns the map token from the environment.
  """
  def map_token do
    Application.get_env(:wanderer_notifier, :map_token)
  end

  @doc """
  Returns the map CSRF token from the environment.
  """
  def map_csrf_token do
    Application.get_env(:wanderer_notifier, :map_csrf_token)
  end

  @doc """
  Returns the license key from the environment.
  """
  def license_key do
    Application.get_env(:wanderer_notifier, :license_key)
  end

  @doc """
  Returns the notifier API token.
  In production, always uses the baked-in value from application config.
  In development, uses the value from environment variable.
  """
  def notifier_api_token do
    # First check environment variables
    token_from_env = get_token_from_env()
    baked_token = get_baked_token()

    cond do
      # First priority: Environment variables
      token_from_env ->
        AppLogger.config_info("Using API token from environment variable")
        token_from_env

      # Second priority: Baked token
      baked_token ->
        AppLogger.config_info("Using baked-in API token")
        baked_token

      # Last resort: Fallback based on environment
      true ->
        handle_missing_token()
    end
  end

  # Get token from environment variables
  defp get_token_from_env do
    direct_env_var = System.get_env(@production_token_env)
    legacy_env_var = System.get_env("NOTIFIER_API_TOKEN")
    direct_env_var || legacy_env_var
  end

  # Get token from application config
  defp get_baked_token do
    Application.get_env(:wanderer_notifier, :api_token) ||
      Application.get_env(:wanderer_notifier, :notifier_api_token)
  end

  # Handle case when no token is available
  defp handle_missing_token do
    env = Application.get_env(:wanderer_notifier, :env, :prod)
    AppLogger.config_warn("No API token found in environment or application config")

    if env == :prod do
      AppLogger.config_error("Missing API token in production")
      "invalid-prod-token-missing"
    else
      AppLogger.config_warn("Using development fallback token")
      "dev-environment-token"
    end
  end

  @doc """
  Returns the ZKillboard base URL.
  This is a constant and not configurable.
  """
  def zkill_base_url, do: @zkill_base_url

  @doc """
  Returns the ESI base URL.
  This is a constant and not configurable.
  """
  def esi_base_url, do: @esi_base_url

  @doc """
  Returns the license manager API URL.
  In production environment, this cannot be overridden with environment variables.
  In development/test, environment variable overrides are allowed.
  """
  def license_manager_api_url do
    env = Application.get_env(:wanderer_notifier, :env, :prod)

    if env == :prod do
      get_production_license_manager_url()
    else
      get_development_license_manager_url()
    end
  end

  # Get license manager URL for production environment
  defp get_production_license_manager_url do
    url = Application.get_env(:wanderer_notifier, :license_manager_api_url)

    if is_nil(url) || url == "" do
      @default_license_manager_url
    else
      url
    end
  end

  # Get license manager URL for development environment
  defp get_development_license_manager_url do
    url = Application.get_env(:wanderer_notifier, :license_manager_api_url)

    if is_nil(url) || url == "" do
      get_license_manager_url_from_env() || @default_license_manager_url
    else
      url
    end
  end

  # Try to get license manager URL from environment variables
  defp get_license_manager_url_from_env do
    System.get_env("WANDERER_LICENSE_MANAGER_URL") ||
      System.get_env("LICENSE_MANAGER_API_URL")
  end

  @doc """
  Returns the web server port from the environment or the default (4000).
  """
  def web_port do
    # Try WANDERER_PORT first
    case get_port_from_env("WANDERER_PORT") do
      nil ->
        # Then try PORT
        case get_port_from_env("PORT") do
          nil -> get_port_from_config()
          port -> port
        end

      port ->
        port
    end
  end

  # Parse port from environment variable
  defp get_port_from_env(var_name) do
    case System.get_env(var_name) do
      nil -> nil
      port_str -> parse_port(port_str)
    end
  end

  # Parse port from config
  defp get_port_from_config do
    port = Application.get_env(:wanderer_notifier, :web_port, @default_web_port)
    if is_integer(port), do: port, else: @default_web_port
  end

  # Parse port string to integer
  defp parse_port(port_str) do
    case Integer.parse(port_str) do
      {port_num, _} when port_num > 0 -> port_num
      _ -> @default_web_port
    end
  end

  @doc """
  Returns the map name (slug) from the environment.
  If MAP_NAME is set, it will be used.
  Otherwise, it will extract the map name from MAP_URL_WITH_NAME.
  """
  def map_name do
    # First check for explicitly set map_name
    case Application.get_env(:wanderer_notifier, :map_name) do
      name when is_binary(name) and name != "" ->
        name

      _ ->
        # If not found, try to extract from map_url_with_name
        case Application.get_env(:wanderer_notifier, :map_url_with_name) do
          url when is_binary(url) and url != "" ->
            # Extract slug from URL - e.g., "http://example.com/flygd" -> "flygd"
            extract_slug_from_url(url)

          _ ->
            nil
        end
    end
  end

  # Helper function to extract the slug from URL
  defp extract_slug_from_url(url) when is_binary(url) do
    # Remove any trailing slashes
    url = String.trim_trailing(url, "/")

    # Split by "/" and take the last segment
    segments = String.split(url, "/")
    slug = List.last(segments)

    # Don't return empty strings
    if slug && slug != "", do: slug, else: nil
  end

  defp extract_slug_from_url(_), do: nil

  @doc """
  Returns the tracked characters from the environment.
  """
  def tracked_characters do
    Application.get_env(:wanderer_notifier, :tracked_characters, [])
  end

  @doc """
  Validates that required configuration is present.
  Returns :ok if all required configuration is present, or {:error, missing_keys} otherwise.
  """
  def validate_required_config do
    required_keys = [
      {:discord_bot_token, discord_bot_token()},
      {:discord_channel_id, discord_channel_id()},
      {:map_url, map_url()},
      {:license_key, license_key()}
    ]

    missing_keys = for {key, value} <- required_keys, is_nil(value) or value == "", do: key

    if Enum.empty?(missing_keys) do
      :ok
    else
      {:error, missing_keys}
    end
  end

  @doc """
  Returns whether character tracking is enabled in the configuration.
  Alias for feature_enabled?(:character_tracking)
  """
  def character_tracking_enabled? do
    feature_enabled?(:character_tracking)
  end

  @doc """
  Returns the public URL for the application.
  This is used for generating URLs to public assets like images.
  """
  def public_url do
    # First try to get from environment variable
    case Application.get_env(:wanderer_notifier, :public_url) do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        # If not set, try to construct from host and port
        host = Application.get_env(:wanderer_notifier, :host) || "localhost"
        port = Application.get_env(:wanderer_notifier, :port) || 4000
        scheme = Application.get_env(:wanderer_notifier, :scheme) || "http"

        "#{scheme}://#{host}:#{port}"
    end
  end

  @doc """
  Returns whether K-Space (non-wormhole) systems should be tracked in addition to wormhole systems.
  By default, only wormhole systems are tracked unless explicitly enabled.
  """
  def track_kspace_systems? do
    case System.get_env("WANDERER_FEATURE_TRACK_KSPACE") do
      "true" ->
        true

      "1" ->
        true

      nil ->
        false

      # Any other value is considered false
      _ ->
        false
    end
  end

  @doc """
  Legacy function for backward compatibility.
  @deprecated Use track_kspace_systems?/0 instead
  """
  def track_all_systems? do
    track_kspace_systems?()
  end

  @doc """
  Returns the TTL for cached system data.
  Default is 24 hours.
  """
  def systems_cache_ttl do
    # 24 hours in seconds
    86_400
  end

  @doc """
  Returns the TTL for cached static info data.
  Default is 7 days as this data rarely changes.
  """
  def static_info_cache_ttl do
    # 7 days in seconds
    7 * 86_400
  end

  @doc """
  Returns a map with information about all defined features.
  Useful for displaying feature status in the web dashboard.
  """
  def get_all_features do
    Enum.reduce(@features, %{}, fn {feature_key, feature_config}, acc ->
      display_name =
        feature_key
        |> Atom.to_string()
        |> String.replace("_", " ")
        |> String.split()
        |> Enum.map_join(" ", &String.capitalize/1)

      feature_data = %{
        name: feature_key,
        display_name: display_name,
        description: feature_config.description,
        enabled: feature_enabled?(feature_key),
        enabled_var: feature_config.enabled_var,
        channel_id: discord_channel_id_for(feature_key),
        channel_var: feature_config.channel_var
      }

      Map.put(acc, feature_key, feature_data)
    end)
  end
end
