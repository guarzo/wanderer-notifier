defmodule WandererNotifier.Cache.CacheHelper do
  @moduledoc """
  Provides higher-order functions for common caching patterns across the application.

  This module abstracts the repetitive cache fetch pattern used throughout the codebase,
  providing a consistent interface for cache operations with built-in logging and error handling.
  """

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.Config, as: CacheConfig
  alias WandererNotifier.Cache.Adapter
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type cache_key_type :: atom()
  @type id :: String.t() | integer()
  @type opts :: keyword()
  @type fetch_fn :: (id(), opts() -> {:ok, term()} | {:error, term()})
  @type cache_validator :: (term() -> boolean())

  @doc """
  Fetches data with caching, using a standardized pattern.

  This is the primary caching abstraction that handles:
  - Cache key generation using the CacheKeys module
  - Cache lookups with configurable cache names
  - Automatic cache population on misses
  - Logging of cache hits/misses
  - Validation of cached data

  ## Parameters

    * `cache_type` - Atom used to generate the cache key (e.g., `:character`, `:corporation`)
    * `id` - The ID of the entity being fetched
    * `opts` - Options including:
      * `:cache_name` - Override the default cache name
      * `:ttl_override` - Override the default TTL (in seconds or :infinity)
      * Any other options to pass to the fetch function
    * `fetch_fn` - Function to call when data is not in cache
    * `log_name` - Human-readable name for logging (e.g., "character", "corporation")
    * `validator` - Optional function to validate cached data (defaults to checking non-empty map)

  ## Examples

      # Simple usage with default validation
      fetch_with_cache(:character, "123", [],
        &esi_client().get_character_info/2,
        "character"
      )
      
      # With custom TTL override (cache for 30 minutes)
      fetch_with_cache(:character, "123", [ttl: 1800],
        &esi_client().get_character_info/2,
        "character"
      )
      
      # With custom validation and infinite TTL
      fetch_with_cache(:system, "30000142", [ttl: :infinity],
        &esi_client().get_system/2,
        "solar system",
        fn data -> is_map(data) and Map.has_key?(data, "name") end
      )

  ## Returns

    * `{:ok, data}` - When data is successfully retrieved (from cache or API)
    * `{:error, reason}` - When the fetch operation fails
  """
  @spec fetch_with_cache(
          cache_key_type(),
          id(),
          opts(),
          fetch_fn(),
          String.t(),
          cache_validator() | nil
        ) :: {:ok, term()} | {:error, term()}
  def fetch_with_cache(cache_type, id, opts, fetch_fn, log_name, validator \\ nil) do
    cache_name = get_cache_name(opts)
    cache_key = apply(CacheKeys, cache_type, [id])

    case get_from_cache(cache_name, cache_key) do
      {:ok, cached_data} when cached_data != nil ->
        if validate_cached_data(cached_data, validator) do
          AppLogger.cache_debug("Cache hit for #{log_name}",
            id: id,
            cache_key: cache_key
          )

          {:ok, cached_data}
        else
          # Invalid cached data, fetch fresh
          fetch_and_cache(cache_name, cache_key, id, opts, fetch_fn, log_name)
        end

      _ ->
        # Cache miss or error
        fetch_and_cache(cache_name, cache_key, id, opts, fetch_fn, log_name)
    end
  end

  @doc """
  Fetches data with caching using a custom cache key.

  Similar to `fetch_with_cache/6` but allows for custom cache key generation
  when the standard pattern doesn't apply.

  ## Parameters

    * `custom_key` - Pre-generated cache key
    * `opts` - Options including:
      * `:cache_name` - Override the default cache name
      * `:ttl` - Override the default TTL (in seconds, or `:infinity`)
    * `fetch_fn` - Function to call when data is not in cache
    * `log_context` - Map of context for logging
    * `validator` - Optional function to validate cached data

  ## Returns

    * `{:ok, data}` - When data is successfully retrieved
    * `{:error, reason}` - When the fetch operation fails
  """
  @spec fetch_with_custom_key(
          String.t(),
          opts(),
          (-> {:ok, term()} | {:error, term()}),
          map(),
          cache_validator() | nil
        ) :: {:ok, term()} | {:error, term()}
  def fetch_with_custom_key(custom_key, opts, fetch_fn, log_context, validator \\ nil) do
    cache_name = get_cache_name(opts)

    case get_from_cache(cache_name, custom_key) do
      {:ok, cached_data} when cached_data != nil ->
        if validate_cached_data(cached_data, validator) do
          AppLogger.cache_debug(
            "Cache hit",
            Map.merge(log_context, %{cache_key: custom_key})
          )

          {:ok, cached_data}
        else
          # Invalid cached data, fetch fresh
          fetch_and_cache_custom(cache_name, custom_key, opts, fetch_fn, log_context)
        end

      _ ->
        # Cache miss or error
        fetch_and_cache_custom(cache_name, custom_key, opts, fetch_fn, log_context)
    end
  end

  @doc """
  Creates a caching wrapper for a function.

  Returns a new function that automatically caches the results of the wrapped function.
  This is useful for creating cached versions of API functions.

  ## Parameters

    * `cache_type` - Atom used to generate cache keys
    * `fetch_fn` - The function to wrap with caching
    * `log_name` - Human-readable name for logging
    * `validator` - Optional validation function

  ## Examples

      cached_get_character = with_cache(:character,
        &esi_client().get_character_info/2,
        "character"
      )
      
      # Now you can call it like a normal function
      {:ok, character} = cached_get_character.("123", [])

  ## Returns

  A function with the same signature as the wrapped function, but with caching.
  """
  @spec with_cache(
          cache_key_type(),
          fetch_fn(),
          String.t(),
          cache_validator() | nil
        ) :: fetch_fn()
  def with_cache(cache_type, fetch_fn, log_name, validator \\ nil) do
    fn id, opts ->
      fetch_with_cache(cache_type, id, opts, fetch_fn, log_name, validator)
    end
  end

  @doc """
  Invalidates a cached entry.

  Removes the specified entry from the cache, forcing a fresh fetch on next access.

  ## Parameters

    * `cache_type` - The cache type atom
    * `id` - The ID of the cached entity
    * `opts` - Options including cache name override

  ## Returns

    * `:ok` - Entry was invalidated or didn't exist
    * `{:error, reason}` - If cache operation failed
  """
  @spec invalidate(cache_key_type(), id(), opts()) :: :ok | {:error, term()}
  def invalidate(cache_type, id, opts \\ []) do
    cache_name = get_cache_name(opts)
    cache_key = apply(CacheKeys, cache_type, [id])

    case Adapter.del(cache_name, cache_key) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # Private functions

  defp get_cache_name(opts) do
    CacheConfig.cache_name(opts)
  end

  defp get_from_cache(cache_name, cache_key) do
    Adapter.get(cache_name, cache_key)
  end

  defp validate_cached_data(data, nil) do
    # Default validation: must be a non-empty map
    is_map(data) and data != %{}
  end

  defp validate_cached_data(data, validator) when is_function(validator, 1) do
    validator.(data)
  end

  defp fetch_and_cache(cache_name, cache_key, id, opts, fetch_fn, log_name) do
    AppLogger.cache_debug("Cache miss for #{log_name}, fetching from API",
      id: id,
      cache_key: cache_key
    )

    case fetch_fn.(id, opts) do
      {:ok, data} = success ->
        # Cache the successful result with appropriate TTL
        ttl = get_ttl_from_opts(opts, log_name)
        Adapter.set(cache_name, cache_key, data, ttl)
        success

      error ->
        error
    end
  end

  defp fetch_and_cache_custom(cache_name, cache_key, opts, fetch_fn, log_context) do
    AppLogger.cache_debug(
      "Cache miss, fetching fresh data",
      Map.merge(log_context, %{cache_key: cache_key})
    )

    case fetch_fn.() do
      {:ok, data} = success ->
        # Cache the successful result with TTL
        ttl = get_ttl_from_opts(opts, "custom", :timer.hours(1))
        Adapter.set(cache_name, cache_key, data, ttl)
        success

      error ->
        error
    end
  end

  # Helper function to get TTL from options with fallback to config
  defp get_ttl_from_opts(opts, log_name, default_ttl \\ nil) do
    case Keyword.get(opts, :ttl) do
      nil -> get_config_ttl(log_name)
      :infinity -> :infinity
      ttl_seconds when is_integer(ttl_seconds) -> :timer.seconds(ttl_seconds)
      _other -> get_fallback_ttl(default_ttl, log_name)
    end
  end

  defp get_config_ttl(log_name) do
    cache_type = log_name_to_cache_type(log_name)

    case CacheConfig.ttl_for(cache_type) do
      :infinity -> :infinity
      seconds -> :timer.seconds(seconds)
    end
  end

  defp get_fallback_ttl(default_ttl, log_name) do
    if default_ttl do
      default_ttl
    else
      get_config_ttl(log_name)
    end
  end

  # Helper function to safely convert log names to cache type atoms
  defp log_name_to_cache_type(log_name) when is_binary(log_name) do
    case log_name do
      "character" -> :character
      "corporation" -> :corporation
      "alliance" -> :alliance
      "system" -> :system
      "killmail" -> :killmail
      "notification" -> :notification
      _ -> :default
    end
  end

  defp log_name_to_cache_type(_), do: :default
end
