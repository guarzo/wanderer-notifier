# Caching Utilities

This document outlines the caching utilities available in the WandererNotifier application and best practices for their use.

## Overview

WandererNotifier uses an in-memory caching strategy to optimize performance and reduce load on external APIs. The caching system provides TTL-based expiration and a consistent interface for all components.

## Cache Repository

The central interface for caching operations is the `WandererNotifier.Cache.Repository` module, which provides a consistent API for cache operations:

```elixir
defmodule WandererNotifier.Cache.Repository do
  @moduledoc """
  Repository for cache operations providing consistent interface for cache storage.
  """

  @doc """
  Get a value from cache by key.
  Returns `{:ok, value}` if found, `{:error, :not_found}` if not found.
  """
  @spec get(String.t()) :: {:ok, any()} | {:error, :not_found}

  @doc """
  Put a value in cache with a specified TTL (in seconds).
  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec put(String.t(), any(), integer()) :: :ok | {:error, any()}

  @doc """
  Delete a key from cache.
  Returns `:ok` regardless of whether the key existed.
  """
  @spec delete(String.t()) :: :ok

  @doc """
  Get multiple values from cache by keys.
  Returns a map of found keys and their values.
  """
  @spec get_many([String.t()]) :: %{String.t() => any()}

  # Additional function specifications...
end
```

## Cache Keys

Cache keys follow a consistent naming convention to avoid collisions:

```
{namespace}:{entity_type}:{identifier}
```

For example:

- `zkill:recent_kills` - List of recent kill IDs
- `character:12345` - Character data for ID 12345
- `system:J123456` - System data for J123456

## Common Cache Namespaces

| Namespace     | Description                             | Typical TTL   |
| ------------- | --------------------------------------- | ------------- |
| `character`   | Character data from ESI and Map APIs    | 30-60 minutes |
| `corporation` | Corporation data from ESI               | 24 hours      |
| `alliance`    | Alliance data from ESI                  | 24 hours      |
| `system`      | Solar system data from Map API          | 24 hours      |
| `killmail`    | Killmail data from ESI and zKillboard   | 1-6 hours     |
| `zkill`       | zKillboard specific data                | 1 hour        |
| `static`      | Static game data (types, regions, etc.) | 7 days        |
| `chart`       | Generated chart data                    | 24 hours      |

## Cache TTL Configuration

Default TTL values are configured in `WandererNotifier.Core.Config.Timings`:

```elixir
def cache_ttl(:character), do: 1800  # 30 minutes
def cache_ttl(:system), do: 86400    # 24 hours
def cache_ttl(:static), do: 604800   # 7 days
def cache_ttl(:killmail), do: 3600   # 1 hour
def cache_ttl(_), do: 3600           # Default: 1 hour
```

## Cache Manager

The `WandererNotifier.Cache.Manager` module provides higher-level caching utilities:

```elixir
defmodule WandererNotifier.Cache.Manager do
  @moduledoc """
  Provides utilities for managing cache operations.
  """

  alias WandererNotifier.Cache.Repository
  require Logger

  @doc """
  Gets a value from cache with automatic deserialization.
  If not in cache, executes the fallback function and caches the result.
  """
  @spec fetch(String.t(), pos_integer(), (() -> any())) :: any()
  def fetch(key, ttl, fallback) when is_function(fallback, 0) do
    case Repository.get(key) do
      {:ok, value} ->
        Logger.debug(fn -> "[CACHE TRACE] Cache hit for key: #{key}" end)
        value

      {:error, :not_found} ->
        Logger.debug(fn -> "[CACHE TRACE] Cache miss for key: #{key}" end)
        value = fallback.()

        case Repository.put(key, value, ttl) do
          :ok -> value
          {:error, error} ->
            Logger.warning("[CACHE TRACE] Failed to cache key: #{key}, error: #{inspect(error)}")
            value
        end
    end
  end

  @doc """
  Gets multiple values from cache at once.
  Returns a map of keys to values, with missing keys omitted.
  """
  @spec get_many([String.t()]) :: %{String.t() => any()}
  def get_many(keys) do
    Repository.get_many(keys)
  end

  @doc """
  Invalidates cache for a specific key pattern.
  """
  @spec invalidate(String.t()) :: :ok
  def invalidate(key) do
    Logger.info("[CACHE TRACE] Invalidating cache for key: #{key}")
    Repository.delete(key)
  end

  @doc """
  Invalidates all cache entries for a character.
  """
  @spec invalidate_character(integer()) :: :ok
  def invalidate_character(character_id) do
    Logger.info("[CACHE TRACE] Invalidating cache for character #{character_id}")
    Repository.delete("character:#{character_id}")
    Repository.delete("character:#{character_id}:kills")
    Repository.delete("character:#{character_id}:affiliations")
    :ok
  end
end
```

## Cache Monitoring

Caching performance is monitored through:

1. Log messages with the `CACHE TRACE` tag
2. Cache hit/miss metrics
3. Cache size monitoring
4. TTL effectiveness tracking

```elixir
defmodule WandererNotifier.Cache.Metrics do
  @moduledoc """
  Collects and reports cache performance metrics.
  """

  @doc """
  Records a cache hit or miss.
  """
  @spec record_access(String.t(), boolean()) :: :ok
  def record_access(key_prefix, hit?) do
    # Implementation...
  end

  @doc """
  Gets the current cache hit rate for a key prefix.
  """
  @spec hit_rate(String.t()) :: float()
  def hit_rate(key_prefix) do
    # Implementation...
  end
end
```

## Cache Maintenance

Regular cache maintenance is performed by a scheduled task:

```elixir
defmodule WandererNotifier.Schedulers.CacheMaintenanceScheduler do
  @moduledoc """
  Scheduler for regular cache maintenance tasks.
  """

  use WandererNotifier.Schedulers.IntervalScheduler

  @impl true
  def interval, do: 86400  # 24 hours

  @impl true
  def task do
    Logger.info("[SCHEDULER TRACE] Running scheduled cache maintenance")
    WandererNotifier.Cache.Maintenance.run()
  end
end
```

The maintenance task:

1. Removes expired keys
2. Compacts the in-memory cache
3. Updates cache statistics
4. Reports any potential issues

## Future Enhancements

Planned improvements to the caching system include:

1. Circuit breakers for external services
2. Adaptive TTL based on data freshness requirements
3. More sophisticated cache eviction policies
4. Improved cache warming strategies
5. More granular cache metrics reporting
