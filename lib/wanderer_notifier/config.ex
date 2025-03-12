defmodule WandererNotifier.Config do
  @moduledoc """
  Configuration management for WandererNotifier.
  Provides access to application configuration with sensible defaults.
  """
  require Logger

  # Constants for API URLs
  @zkill_base_url "https://zkillboard.com"
  @esi_base_url "https://esi.evetech.net/latest"
  @default_license_manager_url "https://license.wanderer-notifier.com"
  @default_bot_id "default_bot_id"

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
  Returns the bot ID from the environment.
  If not set, returns a default value.
  """
  def bot_id do
    Application.get_env(:wanderer_notifier, :bot_id) || @default_bot_id
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
    case Mix.env() do
      :dev ->
        # In development, allow override from environment
        Application.get_env(:wanderer_notifier, :license_manager_api_url) || @default_license_manager_url
      _ ->
        # In production, use the default URL
        @default_license_manager_url
    end
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
      # Removed bot_id from required keys since it now has a default value
    ]

    missing_keys = for {key, value} <- required_keys, is_nil(value) or value == "", do: key

    if Enum.empty?(missing_keys) do
      :ok
    else
      {:error, missing_keys}
    end
  end
end
