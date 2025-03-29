defmodule WandererNotifier.Config.SystemTracking do
  @moduledoc """
  Configuration module for system tracking settings.
  Handles map URLs, system tracking, and related configurations.
  """

  require Logger
  alias WandererNotifier.Config.Application

  @type map_config :: %{
          url_with_name: String.t() | nil,
          url_base: String.t() | nil,
          name: String.t() | nil,
          token: String.t() | nil,
          csrf_token: String.t() | nil
        }

  @doc """
  Gets the complete map configuration.
  """
  @spec get_map_config() :: map_config()
  def get_map_config do
    {:ok, get_env(:map, %{})}
  end

  @doc """
  Gets the map URL with name.
  """
  @spec get_map_url_with_name() :: String.t() | nil
  def get_map_url_with_name do
    get_env(:map_url_with_name)
  end

  @doc """
  Gets the base map URL.
  """
  @spec get_map_url_base() :: String.t() | nil
  def get_map_url_base do
    get_env(:map_url)
  end

  @doc """
  Gets the map name.
  """
  @spec get_map_name() :: String.t() | nil
  def get_map_name do
    get_env(:map_name)
  end

  @doc """
  Gets the map token.
  """
  @spec get_map_token() :: String.t() | nil
  def get_map_token do
    get_env(:map_token)
  end

  @doc """
  Gets the map CSRF token.
  """
  @spec get_map_csrf_token() :: String.t() | nil
  def get_map_csrf_token do
    get_env(:map_csrf_token)
  end

  @doc """
  Checks if K-space systems tracking is enabled.
  """
  @spec track_kspace_systems?() :: boolean()
  def track_kspace_systems? do
    case get_env("WANDERER_FEATURE_TRACK_KSPACE") do
      "true" -> true
      "1" -> true
      _ -> false
    end
  end

  @doc """
  Gets the systems cache TTL in seconds.
  Defaults to 24 hours.
  """
  @spec systems_cache_ttl() :: integer()
  def systems_cache_ttl do
    # 24 hours in seconds
    86_400
  end

  @doc """
  Gets the static info cache TTL in seconds.
  Defaults to 7 days.
  """
  @spec static_info_cache_ttl() :: integer()
  def static_info_cache_ttl do
    # 7 days in seconds
    7 * 86_400
  end

  @doc """
  Get the system tracking configuration.
  """
  def get_system_tracking_config do
    {:ok, get_env(:system_tracking, %{})}
  end

  defp get_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
