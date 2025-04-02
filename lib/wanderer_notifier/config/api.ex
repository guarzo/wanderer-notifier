defmodule WandererNotifier.Config.API do
  @moduledoc """
  Configuration module for API-related settings.

  This module centralizes all API configuration access,
  providing a standardized interface for retrieving API settings
  and validating configuration values. It handles settings for:

  - ESI (EVE Swagger Interface) API
  - ZKillboard API
  - License Manager API
  - Map API
  """

  require Logger

  @type api_config :: %{
          optional(:token) => String.t(),
          optional(:url) => String.t(),
          optional(:base_url) => String.t(),
          optional(:csrf_token) => String.t(),
          optional(:timeout) => integer()
        }

  @doc """
  Returns the complete API configuration map.
  """
  @spec config() :: map()
  def config do
    %{
      esi: esi_config(),
      zkillboard: zkillboard_config(),
      license_manager: license_manager_config(),
      map: map_config(),
      notifier: notifier_config()
    }
  end

  @doc """
  Returns the ESI (EVE Swagger Interface) API configuration.
  """
  @spec esi_config() :: api_config()
  def esi_config do
    %{
      base_url: get_env(:esi_base_url, "https://esi.evetech.net"),
      timeout: get_env(:esi_timeout, 30_000),
      retry_limit: get_env(:esi_retry_limit, 3),
      user_agent: "WandererNotifier/#{get_app_version()} (EVE ESI API Client)"
    }
  end

  @doc """
  Returns the ZKillboard API configuration.
  """
  @spec zkillboard_config() :: api_config()
  def zkillboard_config do
    %{
      base_url: get_env(:zkillboard_base_url, "https://zkillboard.com/api"),
      token: get_env(:zkillboard_api_token),
      timeout: get_env(:zkillboard_timeout, 30_000),
      user_agent: "WandererNotifier/#{get_app_version()} (ZKillboard API Client)"
    }
  end

  @doc """
  Returns the license manager API configuration.
  """
  @spec license_manager_config() :: api_config()
  def license_manager_config do
    %{
      url: get_env(:license_manager_api_url),
      token: get_env(:license_key),
      timeout: get_env(:license_manager_timeout, 10_000)
    }
  end

  @doc """
  Returns the map API configuration.
  """
  @spec map_config() :: api_config()
  def map_config do
    %{
      url: get_env(:map_url),
      token: get_env(:map_token),
      csrf_token: get_env(:map_csrf_token),
      timeout: get_env(:map_api_timeout, 30_000)
    }
  end

  @doc """
  Returns the notifier API configuration.
  """
  @spec notifier_config() :: api_config()
  def notifier_config do
    %{
      token: get_env(:notifier_api_token)
    }
  end

  @doc """
  Returns the API token for the notifier.
  """
  @spec api_token() :: String.t() | nil
  def api_token do
    get_env(:notifier_api_token)
  end

  @doc """
  Returns the map token from configuration.
  """
  @spec map_token() :: String.t() | nil
  def map_token do
    get_env(:map_token)
  end

  @doc """
  Validates that all required API configuration values are present and valid.

  Returns :ok if the configuration is valid, or a list of errors if not.
  """
  @spec validate() :: :ok | {:error, [String.t()]}
  def validate do
    # Collect errors from all validation functions
    errors =
      []
      |> validate_license_manager_config()
      |> validate_map_config()

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  # Validates the license manager configuration
  defp validate_license_manager_config(errors) do
    case license_manager_config() do
      %{url: nil} -> ["License manager URL is not configured" | errors]
      %{url: ""} -> ["License manager URL cannot be empty" | errors]
      %{token: nil} -> ["License key is not configured" | errors]
      %{token: ""} -> ["License key cannot be empty" | errors]
      _ -> errors
    end
  end

  # Validates the map configuration
  defp validate_map_config(errors) do
    case map_config() do
      %{url: nil} -> ["Map URL is not configured" | errors]
      %{url: ""} -> ["Map URL cannot be empty" | errors]
      %{token: nil} -> ["Map token is not configured" | errors]
      %{token: ""} -> ["Map token cannot be empty" | errors]
      _ -> errors
    end
  end

  # Helper to get application version
  defp get_app_version do
    if Code.ensure_loaded?(WandererNotifier.Config.Version) do
      WandererNotifier.Config.Version.version()
    else
      "dev"
    end
  end

  # Private helper function to get configuration values
  defp get_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
