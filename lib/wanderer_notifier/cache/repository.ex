defmodule WandererNotifier.Cache.Repository do
  @moduledoc """
  GenServer implementation for the cache repository.
  Provides a centralized interface for cache operations with process management.

  This module:
  1. Manages the cache implementation as a supervised process
  2. Delegates cache operations to the configured implementation
  3. Provides a consistent API for cache access
  4. Handles process lifecycle and supervision
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

  @doc """
  Starts the cache repository process.
  """
  def start_link(args) do
    AppLogger.cache_debug("Starting cache repository", %{
      implementation: @cache_impl
    })

    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Child spec for supervisor integration.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  # -- CACHE BEHAVIOUR IMPLEMENTATION --

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

  @impl WandererNotifier.Cache.Behaviour
  def init_batch_logging do
    @cache_impl.init_batch_logging()
  end

  # -- GENSERVER CALLBACKS --

  @impl true
  def init(args) do
    # Initialize batch logging
    init_batch_logging()

    AppLogger.cache_info("Cache repository initialized")
    {:ok, args}
  end
end
