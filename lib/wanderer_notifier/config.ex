defmodule WandererNotifier.Config do
  @moduledoc """
  Configuration management for WandererNotifier.
  Provides access to application configuration with sensible defaults.
  """
  require Logger

  # Constants for API URLs
  @zkill_base_url "https://zkillboard.com"
  @esi_base_url "https://esi.evetech.net/latest"
  @default_license_manager_url "https://lm.wanderer.ltd"

  # Production bot API token - this will be used in production builds
  # This token needs to be valid for the license manager API
  @production_bot_api_token "d8ec01d6-9ee9-4fe5-874c-b091031c8083"

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
  Returns the license key from the environment.
  """
  def license_key do
    Application.get_env(:wanderer_notifier, :license_key)
  end

  @doc """
  Returns the bot API token.
  In production, this returns a constant value.
  In development and test environments, it uses the value from environment variables.
  """
  def bot_api_token do
    # Check if we're in a development container by looking for a specific environment variable
    # or by checking if the LICENSE_MANAGER_API_URL is set (which is only used in development)
    is_dev_container = System.get_env("LICENSE_MANAGER_API_URL") != nil

    if is_dev_container do
      # In development containers, always use the environment variable
      env_token = Application.get_env(:wanderer_notifier, :bot_api_token)
      if is_nil(env_token) || env_token == "" do
        # If the environment variable is not set, log a warning and use the production token
        require Logger
        Logger.warning("BOT_API_TOKEN environment variable is not set, using production token")
        @production_bot_api_token
      else
        env_token
      end
    else
      # For non-development containers, use the original logic
      env = Application.get_env(:wanderer_notifier, :env, :prod)

      case env do
        :prod ->
          # In production, use the hardcoded token
          @production_bot_api_token
        _ ->
          # In development and test, use the environment variable
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
    Application.get_env(:wanderer_notifier, :license_manager_api_url) || @default_license_manager_url
  end

  @doc """
  Returns the web server port from the environment or the default (4000).
  """
  def web_port do
    Application.get_env(:wanderer_notifier, :web_port, 4000)
  end

  @doc """
  Returns the map name from the environment.
  """
  def map_name do
    Application.get_env(:wanderer_notifier, :map_name)
  end

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
      nil -> true  # Default to true if not set
      _ -> true    # Any other value is considered true
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
      nil -> true  # Default to true if not set
      _ -> true    # Any other value is considered true
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
      nil -> true  # Default to true if not set
      _ -> true    # Any other value is considered true
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
end
