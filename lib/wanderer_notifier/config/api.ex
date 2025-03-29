defmodule WandererNotifier.Config.API do
  @moduledoc """
  Configuration module for API-related settings.
  Centralizes all API configuration and provides type-safe access to settings.
  """

  require Logger
  alias WandererNotifier.Config.Application

  @type api_config :: %{
          optional(:token) => String.t(),
          optional(:url) => String.t(),
          optional(:csrf_token) => String.t()
        }

  @doc """
  Gets the ESI API configuration.
  """
  @spec get_esi_config() :: api_config()
  def get_esi_config do
    %{
      token: get_env(:api_token) || get_env(:notifier_api_token)
    }
  end

  @doc """
  Gets the ZKillboard API configuration.
  """
  @spec get_zkillboard_config() :: api_config()
  def get_zkillboard_config do
    %{
      token: get_env(:zkillboard_api_token)
    }
  end

  @doc """
  Gets the license manager API configuration.
  """
  @spec get_license_manager_config() :: api_config()
  def get_license_manager_config do
    %{
      url: get_env(:license_manager_api_url),
      token: get_env(:license_key)
    }
  end

  @doc """
  Gets the map API configuration.
  """
  @spec get_map_config() :: api_config()
  def get_map_config do
    %{
      url: get_env(:map_url),
      token: get_env(:map_token),
      csrf_token: get_env(:map_csrf_token)
    }
  end

  @doc """
  Get the API configuration.
  """
  def get_api_config do
    {:ok, get_env(:api, %{})}
  end

  @doc """
  Get the API token.
  """
  def get_api_token do
    get_env(:api_token)
  end

  @doc """
  Gets the map token from configuration.
  """
  def map_token do
    Application.get_env(:wanderer_notifier, :api, %{})
    |> Map.get(:map_token)
  end

  defp get_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
