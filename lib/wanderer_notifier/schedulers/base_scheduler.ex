defmodule WandererNotifier.Schedulers.BaseMapScheduler do
  @moduledoc """
  Base scheduler module that provides common functionality for map-related schedulers.
  These schedulers handle periodic updates of data from the map API.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Constants

  @callback feature_flag() :: atom()
  @callback update_data(any()) :: {:ok, any()} | {:error, any()}
  @callback cache_key() :: String.t()
  @callback primed_key() :: atom()
  @callback log_emoji() :: String.t()
  @callback log_label() :: String.t()
  @callback interval_key() :: atom()
  @callback stats_type() :: atom() | nil

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

        # Get the configured interval for this scheduler type
        interval = get_scheduler_interval(opts)

        # Get cached data, defaulting to empty list if not found
        cached_data = get_cached_data(cache_name)

        state = %{
          interval: interval,
          timer: nil,
          primed: primed?,
          cached_data: cached_data
        }

        AppLogger.scheduler_info("Scheduler initialized",
          module: __MODULE__,
          interval: state.interval,
          primed: state.primed,
          cached_count: length(cached_data)
        )

        # Return with continue to trigger handle_continue
        {:ok, state, {:continue, :schedule}}
      end

      # Get the interval configuration for different scheduler types
      defp get_scheduler_interval(opts) do
        # Get the default interval from opts
        default_interval = Keyword.get(opts, :interval, Constants.default_service_interval())

        # Get the config key from the callback
        config_key = interval_key()

        # Fetch from application config with the callback-provided key and default
        Application.get_env(:wanderer_notifier, config_key, default_interval)
      end

      # Get cached data with error handling
      defp get_cached_data(cache_name) do
        case Cachex.get(cache_name, cache_key()) do
          {:ok, data} when is_list(data) ->
            data

          {:ok, nil} ->
            []

          {:ok, data} ->
            AppLogger.scheduler_error("Invalid cached data format",
              key: cache_key(),
              data: inspect(data)
            )

            []

          {:error, reason} ->
            AppLogger.scheduler_error("Failed to get cached data",
              key: cache_key(),
              error: inspect(reason)
            )

            []
        end
      end

      @impl GenServer
      def handle_continue(:schedule, state) do
        # Use the Config module's feature_enabled? function which handles both maps and keyword lists
        feature_enabled = WandererNotifier.Config.feature_enabled?(feature_flag())

        if feature_enabled do
          AppLogger.scheduler_info("Scheduling update",
            module: __MODULE__,
            feature: feature_flag(),
            enabled: true
          )

          # Start with an immediate timer
          timer = Process.send_after(self(), :update, 0)
          {:noreply, %{state | timer: timer}}
        else
          AppLogger.scheduler_info("Feature disabled",
            module: __MODULE__,
            feature: feature_flag(),
            enabled: false
          )

          # Even if feature is disabled, we should still schedule the next check
          timer = Process.send_after(self(), :check_feature, Constants.feature_check_interval())
          {:noreply, %{state | timer: timer}}
        end
      end

      @impl GenServer
      def handle_info(:check_feature, state) do
        # Re-check the feature flag and schedule if enabled
        handle_continue(:schedule, state)
      end

      @impl GenServer
      def handle_info(:update, state) do
        cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

        case update_data(state.cached_data) do
          {:ok, new_data} ->
            handle_update_success(new_data, state, cache_name)

          {:error, reason} ->
            handle_update_error(reason, state)
        end
      end

      # Handle successful data update
      defp handle_update_success(new_data, state, cache_name) do
        Cachex.put(cache_name, primed_key(), true)
        Cachex.put(cache_name, cache_key(), new_data)
        log_update(__MODULE__, new_data, state.cached_data)

        # Update Stats module with the tracked count
        update_stats_count(__MODULE__, length(new_data))

        # Schedule next update and update state
        new_state = schedule_update(%{state | cached_data: new_data})
        {:noreply, new_state}
      end

      # Handle update error
      defp handle_update_error(reason, state) do
        error_type = get_error_type(reason)

        AppLogger.scheduler_error("Update failed",
          module: __MODULE__,
          error: inspect(reason),
          error_type: error_type
        )

        # Reschedule after error with a shorter delay
        new_state = schedule_update(state)
        {:noreply, new_state}
      end

      defp get_error_type({:http_error, status, _}) when status >= 500, do: :server_error
      defp get_error_type({:http_error, status, _}) when status >= 400, do: :client_error
      defp get_error_type(:cache_error), do: :cache_error
      defp get_error_type(:invalid_data), do: :invalid_data
      defp get_error_type(_), do: :unknown_error

      defp schedule_update(state) do
        # Cancel any existing timer
        if state.timer, do: Process.cancel_timer(state.timer)

        # Schedule next update
        timer = Process.send_after(self(), :update, state.interval)
        %{state | timer: timer}
      end

      @doc """
      Runs an update cycle.
      """
      def run do
        cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
        cached_data = get_cached_data_for_run(cache_name)

        case update_data(cached_data) do
          {:ok, new_data} ->
            handle_successful_run(new_data, cache_name)

          {:error, reason} ->
            handle_failed_run(reason)
        end
      end

      # Get cached data for manual run operation
      defp get_cached_data_for_run(cache_name) do
        case Cachex.get(cache_name, cache_key()) do
          {:ok, data} when is_list(data) ->
            data

          {:ok, nil} ->
            AppLogger.scheduler_info("No cached data found")
            []

          {:ok, data} ->
            AppLogger.scheduler_error("Invalid cached data format",
              data: inspect(data)
            )

            []

          {:error, reason} ->
            AppLogger.scheduler_error("Failed to get cached data",
              error: inspect(reason)
            )

            []
        end
      end

      # Handle successful manual run
      defp handle_successful_run(new_data, cache_name) do
        Cachex.put(cache_name, cache_key(), new_data)
        {:ok, new_data}
      end

      # Handle failed manual run
      defp handle_failed_run(reason) do
        AppLogger.scheduler_error("Manual update failed",
          error: inspect(reason)
        )

        {:error, reason}
      end

      def log_update(module, new_data, old_data) do
        new_count = length(new_data)
        old_count = length(old_data)
        change = new_count - old_count

        change_indicator =
          cond do
            change > 0 -> "📈 + #{change}"
            change < 0 -> "📉 #{change}"
            true -> "➡️  No change"
          end

        emoji = module.log_emoji()
        label = module.log_label()

        AppLogger.api_info(
          "#{emoji} #{label} updated | #{old_count} → #{new_count} | #{change_indicator}"
        )
      end

      defp update_stats_count(module, count) do
        # Call module.stats_type() and update stats if it returns a valid type
        # This function will only be called from schedulers that return :systems or :characters
        case module.stats_type() do
          stat_type when stat_type in [:systems, :characters] ->
            Stats.set_tracked_count(stat_type, count)

          _ ->
            :ok
        end
      end
    end
  end
end
