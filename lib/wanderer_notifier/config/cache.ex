defmodule WandererNotifier.Config.Cache do
  @moduledoc """
  Configuration module for cache-related settings.
  Handles cache directory, name, and TTL configurations.
  """

  require Logger

  @default_cache_dir "/app/data/cache"
  @default_cache_name :wanderer_notifier_cache

  @doc """
  Gets the cache directory path.
  Defaults to '/app/data/cache' if not set.
  """
  @spec get_cache_dir() :: String.t()
  def get_cache_dir do
    get_env(:cache_dir, @default_cache_dir)
  end

  @doc """
  Gets the cache name.
  Defaults to :wanderer_notifier_cache if not set.
  """
  @spec get_cache_name() :: atom()
  def get_cache_name do
    get_env(:cache_name, @default_cache_name)
  end

  @doc """
  Gets the persistence configuration for cache.
  """
  @spec get_persistence_config() :: Keyword.t()
  def get_persistence_config do
    get_env(:persistence, [])
  end

  @doc """
  Get the cache configuration.
  """
  def get_cache_config do
    {:ok, get_env(:cache, %{})}
  end

  @doc """
  Gets the TTL for character cache entries.
  """
  def characters_cache_ttl do
    Application.get_env(:wanderer_notifier, :cache, %{})
    |> Map.get(:characters_cache_ttl, 3600)
  end

  @doc """
  Gets the TTL for static info cache entries.
  """
  def static_info_cache_ttl do
    Application.get_env(:wanderer_notifier, :cache, %{})
    |> Map.get(:static_info_cache_ttl, 86_400)
  end

  defp get_env(key, default) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
