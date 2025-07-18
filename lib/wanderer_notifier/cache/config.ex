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
        hooks: [{:hook, Cachex.Stats, nil, nil}],
        compression: [threshold: 1024]
      ]
  """
  @spec cache_config(keyword()) :: keyword()
  def cache_config(opts \\ []) do
    # Import the hook macro from Cachex.Spec
    import Cachex.Spec

    base_config = [
      # Add stats hook to enable statistics
      hooks: [
        hook(module: Cachex.Stats)
      ],
      # Enable compression for larger values
      compression: [
        # Compress values larger than 1KB
        threshold: 1024
      ],
      # Memory limits to prevent excessive memory usage (reduced for debugging)
      limit: [
        # Maximum 50MB memory usage (in bytes) - reduced from 100MB
        memory: 50 * 1024 * 1024,
        # Maximum 10,000 cache entries - reduced from 50,000
        size: 10_000,
        # Use LRU eviction policy when limits are reached
        policy: Cachex.Policy.LRU
      ]
    ]

    # Use put_new to respect caller's name if provided
    merged_config = Keyword.merge(base_config, opts)
    Keyword.put_new(merged_config, :name, cache_name())
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
