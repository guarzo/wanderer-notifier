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

  # Production bot API token - use environment variable or Application config
  # This should be set at runtime, not hardcoded
  @production_bot_token_env "WANDERER_PRODUCTION_BOT_TOKEN"

  @doc """
  Returns the Discord bot token from the environment.
  """
  def discord_bot_token do
    Application.get_env(:wanderer_notifier, :discord_bot_token)
  end

  @doc """
  Returns the Discord channel ID from the environment.
  """
  def discord_channel_id do
    Application.get_env(:wanderer_notifier, :discord_channel_id)
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
  Returns whether charts functionality is enabled.
  Defaults to false if not specified.
  """
  def charts_enabled? do
    case System.get_env("ENABLE_CHARTS") do
      "true" -> true
      "1" -> true
      _ -> false
    end
  end

  @doc """
  Returns whether corp tools functionality is enabled.
  Defaults to false if not specified.
  """
  def corp_tools_enabled? do
    case System.get_env("ENABLE_CORP_TOOLS") do
      "true" -> true
      "1" -> true
      # Fallback to charts_enabled for backward compatibility
      _ -> charts_enabled?()
    end
  end

  @doc """
  Returns whether map tools functionality is enabled.
  Defaults to false if not specified.
  """
  def map_tools_enabled? do
    case System.get_env("ENABLE_MAP_TOOLS") do
      "true" -> true
      "1" -> true
      _ -> false
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
          # In production, use environment variable or Application config
          production_token =
            System.get_env(@production_bot_token_env) ||
              Application.get_env(:wanderer_notifier, :production_bot_token)

          if is_nil(production_token) || production_token == "" do
            require Logger

            Logger.error(
              "Production bot token not configured. Please set #{@production_bot_token_env} environment variable."
            )

            raise "Missing required bot token for production environment"
          end

          production_token

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
    Application.get_env(:wanderer_notifier, :web_port, 4000)
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
  By default, character tracking is enabled unless explicitly disabled by setting
  ENABLE_CHARACTER_TRACKING to "false" or "0".
  """
  def character_tracking_enabled? do
    case System.get_env("ENABLE_CHARACTER_TRACKING") do
      "false" -> false
      "0" -> false
      # Default to true if not set
      nil -> true
      # Any other value is considered true
      _ -> true
    end
  end

  @doc """
  Returns whether system tracking notifications are enabled in the configuration.
  By default, system tracking notifications are enabled unless explicitly disabled by setting
  ENABLE_SYSTEM_NOTIFICATIONS to "false" or "0".
  """
  def system_notifications_enabled? do
    case System.get_env("ENABLE_SYSTEM_NOTIFICATIONS") do
      "false" -> false
      "0" -> false
      # Default to true if not set
      nil -> true
      # Any other value is considered true
      _ -> true
    end
  end

  @doc """
  Returns whether character tracking notifications are enabled in the configuration.
  By default, character tracking notifications are enabled unless explicitly disabled by setting
  ENABLE_CHARACTER_NOTIFICATIONS to "false" or "0".
  """
  def character_notifications_enabled? do
    case System.get_env("ENABLE_CHARACTER_NOTIFICATIONS") do
      "false" -> false
      "0" -> false
      # Default to true if not set
      nil -> true
      # Any other value is considered true
      _ -> true
    end
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
  By default, only specific systems are tracked unless explicitly enabled by setting
  TRACK_ALL_SYSTEMS to "true" or "1".
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
end
