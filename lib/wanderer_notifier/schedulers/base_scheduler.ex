defmodule WandererNotifier.Schedulers.BaseMapScheduler do
  @moduledoc """
  Base scheduler module that provides common functionality for map-related schedulers.
  These schedulers handle periodic updates of data from the map API.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @callback feature_flag() :: atom()
  @callback update_data(any()) :: {:ok, any()} | {:error, any()}
  @callback cache_key() :: String.t()
  @callback primed_key() :: atom()
  @callback log_update(any(), any()) :: :ok

  @impl GenServer
  def init(opts) do
    {:ok, opts}
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour WandererNotifier.Schedulers.BaseMapScheduler
      use GenServer
      require Logger

      alias WandererNotifier.Logger.Logger, as: AppLogger

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl GenServer
      def init(opts) do
        cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
        primed? = Cachex.get(cache_name, primed_key()) == {:ok, true}

        # Get cached data, defaulting to empty list if not found
        cached_data =
          case Cachex.get(cache_name, cache_key()) do
            {:ok, data} when is_list(data) ->
              AppLogger.scheduler_info("Found cached data",
                count: length(data),
                key: cache_key()
              )

              data

            {:ok, data} ->
              AppLogger.scheduler_warn("Invalid cached data format",
                data_type: inspect(data),
                key: cache_key()
              )

              []

            {:error, reason} ->
              AppLogger.scheduler_warn("Failed to get cached data",
                error: inspect(reason),
                key: cache_key()
              )

              []
          end

        state = %{
          interval: Keyword.get(opts, :interval, 60_000),
          timer: nil,
          primed: primed?,
          cached_data: cached_data
        }

        AppLogger.scheduler_info("Initialized scheduler",
          module: __MODULE__,
          interval: state.interval,
          primed: state.primed,
          cached_count: length(cached_data)
        )

        {:ok, state, {:continue, :schedule}}
      end

      @impl GenServer
      def handle_continue(:schedule, state) do
        if WandererNotifier.Core.Application.Service.feature_enabled?(feature_flag()) do
          AppLogger.scheduler_info("Scheduling update",
            module: __MODULE__,
            feature_flag: feature_flag()
          )

          {:noreply, schedule_update(state)}
        else
          AppLogger.scheduler_info("Feature disabled, not scheduling",
            module: __MODULE__,
            feature_flag: feature_flag()
          )

          {:noreply, state}
        end
      end

      @impl GenServer
      def handle_info(:update, state) do
        cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

        AppLogger.scheduler_info("Starting update cycle",
          module: __MODULE__,
          cached_count: length(state.cached_data)
        )

        case update_data(state.cached_data) do
          {:ok, new_data} ->
            AppLogger.scheduler_info("Update successful",
              module: __MODULE__,
              new_count: length(new_data),
              old_count: length(state.cached_data)
            )

            Cachex.put(cache_name, primed_key(), true)
            Cachex.put(cache_name, cache_key(), new_data)
            log_update(new_data, state.cached_data)
            {:noreply, %{state | cached_data: new_data}, {:continue, :schedule}}

          {:error, reason} ->
            AppLogger.scheduler_error("Update failed",
              module: __MODULE__,
              error: inspect(reason),
              cached_count: length(state.cached_data)
            )

            # Don't update cached_data on error, keep the old value
            {:noreply, state, {:continue, :schedule}}
        end
      end

      defp schedule_update(state) do
        if state.timer, do: Process.cancel_timer(state.timer)
        timer = Process.send_after(self(), :update, state.interval)
        %{state | timer: timer}
      end

      @doc """
      Runs an update cycle.
      """
      def run do
        cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

        AppLogger.scheduler_info("Manual update triggered", module: __MODULE__)

        cached_data =
          case Cachex.get(cache_name, cache_key()) do
            {:ok, data} when is_list(data) ->
              AppLogger.scheduler_info("Found cached data for manual update",
                count: length(data),
                key: cache_key()
              )

              data

            {:ok, data} ->
              AppLogger.scheduler_warn("Invalid cached data format for manual update",
                data_type: inspect(data),
                key: cache_key()
              )

              []

            {:error, reason} ->
              AppLogger.scheduler_warn("Failed to get cached data for manual update",
                error: inspect(reason),
                key: cache_key()
              )

              []
          end

        update_data(cached_data)
      end
    end
  end
end
