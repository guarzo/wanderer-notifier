defmodule WandererNotifier.Cache.Repository do
  @moduledoc """
  GenServer implementation for the cache repository.
  Provides a centralized interface for cache operations.
  """

  use GenServer
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Pick one behavior to implement properly - the repository behavior is a superset of cache behavior
  @behaviour WandererNotifier.Cache.RepositoryBehaviour

  @cache_impl Application.compile_env(
                :wanderer_notifier,
                :cache_impl,
                WandererNotifier.Cache.CachexImpl
              )

  # -- PUBLIC API --

  def start_link(args) do
    AppLogger.cache_debug("Starting cache repository", %{
      implementation: @cache_impl
    })

    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl WandererNotifier.Cache.RepositoryBehaviour
  def get(key), do: @cache_impl.get(key)

  @impl WandererNotifier.Cache.RepositoryBehaviour
  def set(key, value, ttl), do: @cache_impl.set(key, value, ttl)

  @impl WandererNotifier.Cache.RepositoryBehaviour
  def put(key, value), do: @cache_impl.put(key, value)

  @impl WandererNotifier.Cache.RepositoryBehaviour
  def delete(key), do: @cache_impl.delete(key)

  @impl WandererNotifier.Cache.RepositoryBehaviour
  def clear, do: @cache_impl.clear()

  @impl WandererNotifier.Cache.RepositoryBehaviour
  def get_and_update(key, update_fun, ttl \\ nil) do
    @cache_impl.get_and_update(key, update_fun)
  end

  @doc """
  Gets recent kills from cache
  """
  @impl WandererNotifier.Cache.RepositoryBehaviour
  def get_recent_kills do
    get(WandererNotifier.Cache.Keys.zkill_recent_kills()) || []
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
