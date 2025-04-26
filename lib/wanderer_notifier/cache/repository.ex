defmodule WandererNotifier.Cache.Repository do
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
