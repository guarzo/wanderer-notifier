defmodule WandererNotifier.Cache.Repository do
  @moduledoc """
  GenServer implementation for the cache repository.
  Provides a centralized interface for cache operations.
  """

  use GenServer
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @behaviour WandererNotifier.Cache.Behaviour

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

  @impl WandererNotifier.Cache.Behaviour
  def get(key), do: @cache_impl.get(key)

  @impl WandererNotifier.Cache.Behaviour
  def set(key, value, ttl), do: @cache_impl.set(key, value, ttl)

  @impl WandererNotifier.Cache.Behaviour
  def put(key, value), do: @cache_impl.put(key, value)

  @impl WandererNotifier.Cache.Behaviour
  def delete(key), do: @cache_impl.delete(key)

  @impl WandererNotifier.Cache.Behaviour
  def clear, do: @cache_impl.clear()

  @impl WandererNotifier.Cache.Behaviour
  def get_and_update(key, update_fun) do
    @cache_impl.get_and_update(key, update_fun)
  end

  @impl WandererNotifier.Cache.Behaviour
  def get_recent_kills do
    @cache_impl.get_recent_kills()
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
