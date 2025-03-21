defmodule WandererNotifier.Core.Config do
  @moduledoc """
  Configuration management for WandererNotifier.
  Provides access to application configuration with sensible defaults.
  """
  require Logger

  # Constants for API URLs
  @zkill_base_url "https://zkillboard.com"
  @esi_base_url "https://esi.evetech.net/latest"
  @default_license_manager_url "https://lm.wanderer.ltd"
  @default_chart_service_port 3001
  @default_web_port 4000

  # Production bot API token - use environment variable or Application config
  # This should be set at runtime, not hardcoded
  @production_bot_token_env "WANDERER_PRODUCTION_BOT_TOKEN"

  # Feature definitions with their environment variables
  @features %{
    general: %{
      enabled_var: "ENABLE_NOTIFICATIONS",
      channel_var: "DISCORD_CHANNEL_ID",
      default_enabled: true,
      description: "General notifications"
    },
    kill_notifications: %{
      enabled_var: "ENABLE_KILL_NOTIFICATIONS",
      channel_var: "DISCORD_KILL_CHANNEL_ID",
      default_enabled: true,
      description: "Kill notifications"
    },
    system_tracking: %{
      enabled_var: "ENABLE_SYSTEM_NOTIFICATIONS",
      channel_var: "DISCORD_SYSTEM_CHANNEL_ID",
      default_enabled: true,
      description: "System tracking notifications"
    },
    character_tracking: %{
      enabled_var: "ENABLE_CHARACTER_NOTIFICATIONS",
      channel_var: "DISCORD_CHARACTER_CHANNEL_ID",
      default_enabled: true,
      description: "Character tracking notifications"
    },
    corp_tools: %{
      enabled_var: "ENABLE_CORP_TOOLS",
      channel_var: "DISCORD_CORP_TOOLS_CHANNEL_ID",
      default_enabled: false,
      description: "Corporation tools integration"
    },
    map_tools: %{
      enabled_var: "ENABLE_MAP_TOOLS",
      channel_var: "DISCORD_MAP_TOOLS_CHANNEL_ID",
      default_enabled: true,
      description: "Map tools integration"
    },
    charts: %{
      enabled_var: "ENABLE_CHARTS",
      channel_var: "DISCORD_CHARTS_CHANNEL_ID",
      default_enabled: true,
      description: "Chart generation"
    },
    tps_charts: %{
      enabled_var: "ENABLE_TPS_CHARTS",
      channel_var: "DISCORD_TPS_CHARTS_CHANNEL_ID",
      default_enabled: false,
      description: "TPS charts generation and notifications"
    },
    activity_charts: %{
      enabled_var: "ENABLE_ACTIVITY_CHARTS",
      channel_var: "DISCORD_ACTIVITY_CHARTS_CHANNEL_ID",
      default_enabled: true,
      description: "Activity charts generation and notifications"
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
      Logger.warning("Unknown feature #{feature} when looking up Discord channel ID")
      discord_channel_id()
    end
  end

  @doc """
  Returns the Discord channel ID specifically for activity charts.
  This function implements the priority order:
  1. DISCORD_MAP_CHARTS_CHANNEL_ID (newer name)
  2. DISCORD_ACTIVITY_CHARTS_CHANNEL_ID (older name)
  3. Main Discord channel ID

  This specialized function is needed because these features
  use multiple environment variables for backward compatibility.
  """
  def discord_channel_id_for_activity_charts do
    # Check for map charts channel ID first (newer name)
    map_charts_channel = System.get_env("DISCORD_MAP_CHARTS_CHANNEL_ID")
    activity_charts_channel = System.get_env("DISCORD_ACTIVITY_CHARTS_CHANNEL_ID")

    cond do
      # If map charts channel is set, use it (highest priority)
      is_binary(map_charts_channel) && map_charts_channel != "" ->
        map_charts_channel

      # If activity charts channel is set, use it (second priority)
      is_binary(activity_charts_channel) && activity_charts_channel != "" ->
        activity_charts_channel

      # Otherwise fall back to main channel ID
      true ->
        discord_channel_id()
    end
  end

  @doc """
  Returns the EVE Corp Tools API URL from the environment.
  """
  def corp_tools_api_url do
    Application.get_env(:wanderer_notifier, :corp_tools_api_url)
  end

  @doc """
  Returns the EVE Corp Tools API token from the environment.
  """
  def corp_tools_api_token do
    Application.get_env(:wanderer_notifier, :corp_tools_api_token)
  end

  @doc """
  Returns whether a specific feature is enabled based on its environment variable.

  ## Parameters
    - feature: The feature to check (atom matching a key in @features)
  """
  def feature_enabled?(feature) when is_atom(feature) do
    feature_config = Map.get(@features, feature)

    if feature_config do
      env_var = feature_config.enabled_var
      default_enabled = feature_config.default_enabled

      case System.get_env(env_var) do
        "true" -> true
        "1" -> true
        "false" -> false
        "0" -> false
        nil -> default_enabled
        _ -> default_enabled
      end
    else
      # Unknown feature, default to false for safety
      Logger.warning("Unknown feature #{feature} when checking if enabled")
      false
    end
  end

  @doc """
  Returns whether charts functionality is enabled.
  Enabled if explicitly set to true or if corp_tools or map_tools are enabled.
  """
  def charts_enabled? do
    explicit_charts_enabled = feature_enabled?(:charts)
    corp_tools_enabled = feature_enabled?(:corp_tools)
    map_tools_enabled = feature_enabled?(:map_tools)

    explicit_charts_enabled || corp_tools_enabled || map_tools_enabled
  end

  @doc """
  Returns whether corp tools functionality is enabled.
  """
  def corp_tools_enabled? do
    feature_enabled?(:corp_tools)
  end

  @doc """
  Returns whether map tools functionality is enabled.
  """
  def map_tools_enabled? do
    feature_enabled?(:map_tools)
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
  Returns whether TPS charts are enabled.
  """
  def tps_charts_enabled? do
    feature_enabled?(:tps_charts) || corp_tools_enabled?()
  end

  @doc """
  Returns whether activity charts are enabled.
  """
  def activity_charts_enabled? do
    feature_enabled?(:activity_charts) || map_tools_enabled?()
  end

  @doc """
  Returns the chart service port from the environment.
  Defaults to 3001 if not specified.
  """
  def chart_service_port do
    case System.get_env("CHART_SERVICE_PORT") do
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
  Returns the bot API token.
  In production, this returns a value from environment variable.
  In development and test environments, it requires a development token to be set.
  """
  def bot_api_token do
    # Check if we're in a development container by looking for a specific environment variable
    # or by checking if the LICENSE_MANAGER_API_URL is set (which is only used in development)
    is_dev_container = System.get_env("LICENSE_MANAGER_API_URL") != nil

    if is_dev_container do
      # In development containers, require the environment variable
      env_token = Application.get_env(:wanderer_notifier, :bot_api_token)

      if is_nil(env_token) || env_token == "" do
        # Fail fast in development mode if token is not set
        require Logger

        Logger.error(
          "BOT_API_TOKEN environment variable is not set. Development requires a valid token."
        )

        raise "Missing required BOT_API_TOKEN environment variable for development"
      else
        env_token
      end
    else
      # For non-development containers (production), use environment variable
      env = Application.get_env(:wanderer_notifier, :env, :prod)

      case env do
        :prod ->
          # In production, ONLY use the hardcoded production token
          # Do not accept tokens from environment variables for security
          production_token = Application.get_env(:wanderer_notifier, :production_bot_token)

          if is_binary(production_token) && production_token != "" do
            # Log that we're using the baked-in token, but don't show the token itself
            require Logger
            prefix = String.slice(production_token, 0, 3)

            Logger.info(
              "Using baked-in production token from application config (starts with: #{prefix}...)"
            )

            production_token
          else
            # As a fallback, check the production environment variable
            # This should only be used during build time, not runtime
            backup_token = System.get_env(@production_bot_token_env)

            if is_binary(backup_token) && backup_token != "" do
              require Logger
              prefix = String.slice(backup_token, 0, 3)

              Logger.warning(
                "Using token from environment variable rather than baked-in value (starts with: #{prefix}...)"
              )

              backup_token
            else
              require Logger

              Logger.error(
                "Production bot token not configured properly. Token should be compiled into the release."
              )

              raise "Missing required production bot token. This release was not built correctly."
            end
          end

        _ ->
          # In test or other environments, use the environment variable
          Application.get_env(:wanderer_notifier, :bot_api_token)
      end
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
  Returns the License Manager API URL.
  In development environment, this can be overridden with LICENSE_MANAGER_API_URL.
  In production, it uses the default URL.
  """
  def license_manager_api_url do
    # Allow override from environment in all environments
    Application.get_env(:wanderer_notifier, :license_manager_api_url) ||
      @default_license_manager_url
  end

  @doc """
  Returns the web server port from the environment or the default (4000).
  """
  def web_port do
    case System.get_env("PORT") do
      nil ->
        Application.get_env(:wanderer_notifier, :web_port, @default_web_port)

      port ->
        case Integer.parse(port) do
          {port_num, _} when port_num > 0 -> port_num
          _ -> Application.get_env(:wanderer_notifier, :web_port, @default_web_port)
        end
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
  Returns whether all systems should be tracked.
  By default, only specific systems are tracked unless explicitly enabled.
  """
  def track_all_systems? do
    case System.get_env("TRACK_ALL_SYSTEMS") do
      "true" -> true
      "1" -> true
      # Default to false if not set
      nil -> false
      # Any other value is considered false
      _ -> false
    end
  end

  @doc """
  Returns the TTL for cached system data.
  Default is 24 hours.
  """
  def systems_cache_ttl do
    # 24 hours in seconds
    86400
  end

  @doc """
  Returns the TTL for cached static info data.
  Default is 7 days as this data rarely changes.
  """
  def static_info_cache_ttl do
    # 7 days in seconds
    7 * 86400
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
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")

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
