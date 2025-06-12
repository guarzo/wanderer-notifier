defmodule WandererNotifier.Cache.Config do
  @moduledoc """
  Centralized configuration for cache-related settings.

  This module provides a single source of truth for cache configuration,
  eliminating the need for scattered Application.get_env calls throughout
  the codebase.
  """

  @default_cache_name :wanderer_cache
  @test_cache_name :wanderer_test_cache

  @doc """
  Returns the configured cache name.

  In test environment, returns `:wanderer_test_cache`.
  In other environments, returns the configured value or `:wanderer_cache` as default.

  ## Examples

      iex> WandererNotifier.Cache.Config.cache_name()
      :wanderer_cache
      
      # In test environment
      iex> WandererNotifier.Cache.Config.cache_name()
      :wanderer_test_cache
  """
  @spec cache_name() :: atom()
  def cache_name do
    if Application.get_env(:wanderer_notifier, :environment) == :test do
      @test_cache_name
    else
      Application.get_env(:wanderer_notifier, :cache_name, @default_cache_name)
    end
  end

  @doc """
  Returns the cache name from options, falling back to the default.

  ## Parameters

    - opts: Keyword list that may contain `:cache_name`

  ## Examples

      iex> WandererNotifier.Cache.Config.cache_name([])
      :wanderer_cache
      
      iex> WandererNotifier.Cache.Config.cache_name(cache_name: :custom_cache)
      :custom_cache
  """
  @spec cache_name(keyword()) :: atom()
  def cache_name(opts) when is_list(opts) do
    Keyword.get(opts, :cache_name, cache_name())
  end

  @doc """
  Returns the default cache name for the current environment.

  This is useful for configuration files and setup.
  """
  @spec default_cache_name() :: atom()
  def default_cache_name do
    if Application.get_env(:wanderer_notifier, :environment) == :test do
      @test_cache_name
    else
      @default_cache_name
    end
  end

  @doc """
  Returns cache configuration for Cachex.

  This includes standard configuration options that should be
  applied to all cache instances.

  ## Options

    - `:name` - The cache name (defaults to `cache_name/0`)
    - Additional options are passed through to Cachex

  ## Examples

      iex> WandererNotifier.Cache.Config.cache_config()
      [
        name: :wanderer_cache,
        stats: true,
        ...
      ]
  """
  @spec cache_config(keyword()) :: keyword()
  def cache_config(opts \\ []) do
    name = Keyword.get(opts, :name, cache_name())

    base_config = [
      name: name,
      stats: true,
      # Enable compression for larger values
      compression: [
        # Compress values larger than 1KB
        threshold: 1024
      ]
    ]

    # Merge with any provided options
    Keyword.merge(base_config, opts)
  end

  @doc """
  Checks if the cache is properly configured.

  Returns true if a cache name is configured, false otherwise.
  """
  @spec configured?() :: boolean()
  def configured? do
    Application.get_env(:wanderer_notifier, :cache_name) != nil or
      Application.get_env(:wanderer_notifier, :environment) == :test
  end

  @doc """
  Returns cache-related statistics configuration.

  This determines whether cache statistics should be collected.
  """
  @spec stats_enabled?() :: boolean()
  def stats_enabled? do
    Application.get_env(:wanderer_notifier, :cache_stats_enabled, true)
  end

  @doc """
  Returns the cache TTL (Time To Live) configuration for different types.

  ## Parameters

    - type: The type of cache entry (:character, :corporation, :alliance, etc.)

  ## Returns

  TTL in seconds, or `:infinity` for no expiration.

  ## Examples

      iex> WandererNotifier.Cache.Config.ttl_for(:character)
      86400  # 24 hours
      
      iex> WandererNotifier.Cache.Config.ttl_for(:killmail)
      3600   # 1 hour
  """
  @spec ttl_for(atom()) :: non_neg_integer() | :infinity
  def ttl_for(type) do
    ttls = Application.get_env(:wanderer_notifier, :cache_ttls, default_ttls())
    # First check the configured TTLs, then type-specific defaults, then global default
    Map.get(ttls, type) || Map.get(default_ttls(), type, default_ttl())
  end

  # Private functions

  defp default_ttls do
    %{
      # 24 hours
      character: 86_400,
      # 24 hours
      corporation: 86_400,
      # 24 hours
      alliance: 86_400,
      # 1 hour
      system: 3_600,
      # 24 hours
      type: 86_400,
      # 1 hour
      killmail: 3_600,
      # 30 minutes
      deduplication: 1_800,
      # 1 hour
      static_info: 3_600,
      # 5 minutes
      map_data: 300,
      # 1 hour
      default: 3_600
    }
  end

  defp default_ttl do
    # 1 hour default
    3_600
  end
end
