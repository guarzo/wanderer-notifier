defmodule WandererNotifier.Data.Cache.Repository do
  @moduledoc """
  GenServer implementation for the cache repository.
  Provides a centralized interface for cache operations.
  """

  use GenServer
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @behaviour WandererNotifier.Data.Cache.CacheBehaviour

  @cache_impl Application.compile_env(
                :wanderer_notifier,
                :cache_implementation,
                WandererNotifier.Data.Cache.CachexImpl
              )

  # -- PUBLIC API --

  def start_link(args) do
    AppLogger.cache_debug("Starting cache repository", %{
      implementation: @cache_impl
    })

    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl WandererNotifier.Data.Cache.CacheBehaviour
  def get(key), do: @cache_impl.get(key)

  @impl WandererNotifier.Data.Cache.CacheBehaviour
  def set(key, value, ttl), do: @cache_impl.set(key, value, ttl)

  @impl WandererNotifier.Data.Cache.CacheBehaviour
  def put(key, value), do: @cache_impl.put(key, value)

  @impl WandererNotifier.Data.Cache.CacheBehaviour
  def delete(key), do: @cache_impl.delete(key)

  @impl WandererNotifier.Data.Cache.CacheBehaviour
  def clear, do: @cache_impl.clear()

  @impl WandererNotifier.Data.Cache.CacheBehaviour
  def get_and_update(key, update_fun, ttl \\ nil)

  def get_and_update(key, update_fun, nil) do
    @cache_impl.get_and_update(key, update_fun)
  end

  def get_and_update(key, update_fun, ttl) when is_integer(ttl) do
    current = get(key)
    {old_value, new_value} = update_fun.(current)
    set(key, new_value, ttl)
    {old_value, new_value}
  end

  @doc """
  Syncs cache with database
  """
  def sync_with_db(cache_key, db_read_fun, ttl) do
    case get(cache_key) do
      nil ->
        AppLogger.cache_debug("Cache miss, loading from database", %{
          key: cache_key,
          ttl: ttl
        })

        with {:ok, data} <- db_read_fun.() do
          set(cache_key, data, ttl)
          {:ok, data}
        end

      data ->
        AppLogger.cache_debug("Cache hit, using cached data", %{
          key: cache_key
        })

        {:ok, data}
    end
  end

  @doc """
  Updates cache after database write
  """
  def update_after_db_write(cache_key, data, ttl) do
    AppLogger.cache_debug("Updating cache after database write", %{
      key: cache_key,
      ttl: ttl
    })

    set(cache_key, data, ttl)
    {:ok, data}
  end

  @doc """
  Gets recent kills from cache
  """
  def get_recent_kills do
    get("zkill:recent_kills") || []
  end

  # -- GENSERVER CALLBACKS --

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @impl true
  def init(args) do
    AppLogger.cache_info("Cache repository initialized")
    {:ok, args}
  end
end
