defmodule WandererNotifier.Config.Cache do
  @moduledoc """
  Configuration module for cache-related settings.
  Handles cache directory, name, and TTL configurations.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @default_cache_dir "/app/data/cache"
  @default_cache_name :wanderer_notifier_cache

  @doc """
  Gets the cache directory path.
  Defaults to '/app/data/cache' if not set.
  """
  @spec get_cache_dir() :: String.t()
  def get_cache_dir do
    dir = get_env(:cache_dir, @default_cache_dir)
    AppLogger.cache_debug("Retrieved cache directory", %{dir: dir})
    dir
  end

  @doc """
  Gets the cache name.
  Defaults to :wanderer_notifier_cache if not set.
  """
  @spec get_cache_name() :: atom()
  def get_cache_name do
    name = get_env(:cache_name, @default_cache_name)
    AppLogger.cache_debug("Retrieved cache name", %{name: name})
    name
  end

  @doc """
  Gets the persistence configuration for cache.
  """
  @spec get_persistence_config() :: Keyword.t()
  def get_persistence_config do
    config = get_env(:persistence, [])
    AppLogger.cache_debug("Retrieved persistence configuration", %{config: config})
    config
  end

  @doc """
  Get the cache configuration.
  """
  def get_cache_config do
    config = get_env(:cache, %{})
    AppLogger.cache_debug("Retrieved cache configuration", %{config: config})
    {:ok, config}
  end

  @doc """
  Gets the TTL for character cache entries.
  """
  def characters_cache_ttl do
    ttl =
      Application.get_env(:wanderer_notifier, :cache, %{})
      |> Map.get(:characters_cache_ttl, 3600)

    AppLogger.cache_debug("Retrieved character cache TTL", %{ttl: ttl})
    ttl
  end

  @doc """
  Gets the TTL for system cache entries.
  """
  def systems_cache_ttl do
    ttl =
      Application.get_env(:wanderer_notifier, :cache, %{})
      |> Map.get(:systems_cache_ttl, 3600)

    AppLogger.cache_debug("Retrieved system cache TTL", %{ttl: ttl})
    ttl
  end

  @doc """
  Gets the TTL for static info cache entries.
  """
  def static_info_cache_ttl do
    ttl =
      Application.get_env(:wanderer_notifier, :cache, %{})
      |> Map.get(:static_info_cache_ttl, 86_400)

    AppLogger.cache_debug("Retrieved static info cache TTL", %{ttl: ttl})
    ttl
  end

  defp get_env(key, default) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
