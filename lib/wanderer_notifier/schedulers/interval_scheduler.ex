defmodule WandererNotifier.Schedulers.IntervalScheduler do
  @moduledoc """
  Implements an interval-based scheduler.

  This scheduler runs tasks at regular intervals specified in milliseconds.
  """

  defmacro __using__(opts) do
    quote do
      use WandererNotifier.Schedulers.BaseScheduler,
        name: unquote(Keyword.get(opts, :name, __CALLER__.module))

      # Add the aliases
      alias WandererNotifier.Config.Timings
      alias WandererNotifier.Logger.Logger, as: AppLogger

      # Default interval is 1 hour (in milliseconds) if not specified
      @default_interval unquote(Keyword.get(opts, :default_interval, 60 * 60 * 1000))

      # Client API

      @doc """
      Changes the interval for automatic execution.
      """
      def set_interval(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
        GenServer.call(__MODULE__, {:set_interval, interval_ms})
      end

      # Server Callbacks

      def initialize(opts) do
        # Get interval from options or use default
        interval = get_configured_interval() || Keyword.get(opts, :interval, @default_interval)

        # Initialize last run timestamp
        last_run = Keyword.get(opts, :last_run)

        # Schedule first execution
        if enabled?() do
          schedule_next(interval)
        end

        # Return initial state - only return :ok tuple (removing the error case that will never match)
        {:ok, %{interval: interval, last_run: last_run}}
      end

      @impl true
      def handle_call({:set_interval, interval_ms}, _from, state) do
        # Update interval in state
        new_state = %{state | interval: interval_ms}

        # Reschedule with new interval if enabled
        if enabled?() do
          schedule_next(interval_ms)

          AppLogger.scheduler_info(
            "#{inspect(@scheduler_name)}: Interval updated to #{interval_ms}ms"
          )
        end

        {:reply, :ok, new_state}
      end

      @impl true
      def handle_info(:execute, %{disabled: true} = state) do
        AppLogger.scheduler_info(
          "#{inspect(@scheduler_name)}: Skipping scheduled execution (disabled)"
        )

        {:noreply, state}
      end

      @impl true
      def handle_info(:execute, state) do
        AppLogger.scheduler_info("#{inspect(@scheduler_name)}: Running scheduled execution")

        case execute(state) do
          {:ok, _result, new_state} ->
            # Schedule next execution
            schedule_next(new_state.interval)
            # Update last run timestamp
            {:noreply, %{new_state | last_run: DateTime.utc_now()}}

          {:error, reason, new_state} ->
            AppLogger.scheduler_error(
              "#{inspect(@scheduler_name)}: Execution failed: #{inspect(reason)}"
            )

            # Schedule next execution even if this one failed
            schedule_next(new_state.interval)
            # Update last run timestamp
            {:noreply, %{new_state | last_run: DateTime.utc_now()}}
        end
      end

      @impl true
      def handle_info(message, state) do
        handle_unexpected_message(message, state)
      end

      # Helper Functions

      defp schedule_next(interval) do
        if enabled?() do
          Process.send_after(self(), :execute, interval)

          AppLogger.scheduler_debug(
            "Scheduled next execution",
            scheduler: inspect(@scheduler_name),
            minutes: Float.round(interval / 1000 / 60, 2)
          )
        else
          AppLogger.scheduler_info("#{inspect(@scheduler_name)}: Not scheduling (disabled)")
        end
      end

      # Get the configured interval based on scheduler name
      defp get_configured_interval do
        case @scheduler_name do
          WandererNotifier.Schedulers.CharacterUpdateScheduler ->
            Timings.character_update_scheduler_interval()

          WandererNotifier.Schedulers.SystemUpdateScheduler ->
            Timings.system_update_scheduler_interval()

          WandererNotifier.Schedulers.MaintenanceScheduler ->
            Timings.maintenance_interval()

          WandererNotifier.Schedulers.CacheCheckScheduler ->
            Timings.cache_check_interval()

          WandererNotifier.Schedulers.CacheSyncScheduler ->
            Timings.cache_sync_interval()

          WandererNotifier.Schedulers.CacheCleanupScheduler ->
            Timings.cache_cleanup_interval()

          WandererNotifier.Schedulers.LicenseRefreshScheduler ->
            Timings.license_refresh_interval()

          _ ->
            nil
        end
      end

      @impl true
      def get_config do
        %{
          type: :interval,
          interval: get_configured_interval() || @default_interval
        }
      end

      defoverridable get_config: 0
    end
  end
end
