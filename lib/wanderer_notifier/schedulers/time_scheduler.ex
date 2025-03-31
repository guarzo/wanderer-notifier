defmodule WandererNotifier.Schedulers.TimeScheduler do
  @moduledoc """
  Implements a time-based scheduler.

  This scheduler runs tasks at specific times of day (e.g., 12:00 UTC).
  """

  defmacro __using__(opts) do
    quote do
      use WandererNotifier.Schedulers.BaseScheduler,
        name: unquote(Keyword.get(opts, :name, __CALLER__.module))

      alias WandererNotifier.Config.Timings
      alias WandererNotifier.Logger, as: AppLogger

      # Default schedule time (hour and minute) if not specified
      @default_hour unquote(Keyword.get(opts, :default_hour, 12))
      @default_minute unquote(Keyword.get(opts, :default_minute, 0))

      # Environment variable names for configuration
      @hour_env_var unquote(Keyword.get(opts, :hour_env_var, nil))
      @minute_env_var unquote(Keyword.get(opts, :minute_env_var, nil))

      # Server Callbacks

      def initialize(opts) do
        # Get configured hour and minute
        hour = get_configured_hour()
        minute = get_configured_minute()

        # Initialize last run timestamp
        last_run = Keyword.get(opts, :last_run)

        # Schedule first execution
        if enabled?() do
          schedule_next_run(hour, minute)
        end

        # Return initial state
        {:ok, %{hour: hour, minute: minute, last_run: last_run}}
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
            schedule_next_run(new_state.hour, new_state.minute)
            # Update last run timestamp
            {:noreply, %{new_state | last_run: DateTime.utc_now()}}

          {:error, reason, new_state} ->
            AppLogger.scheduler_error(
              "#{inspect(@scheduler_name)}: Execution failed: #{inspect(reason)}"
            )

            # Schedule next execution even if this one failed
            schedule_next_run(new_state.hour, new_state.minute)
            # Update last run timestamp
            {:noreply, %{new_state | last_run: DateTime.utc_now()}}
        end
      end

      @impl true
      def handle_info(message, state) do
        handle_unexpected_message(message, state)
      end

      # Helper Functions

      defp schedule_next_run(hour, minute) do
        if enabled?() do
          now = DateTime.utc_now()

          # Calculate the next run time
          next_run = calculate_next_run(now, hour, minute)

          # Calculate milliseconds until next run
          milliseconds_until_next_run = DateTime.diff(next_run, now, :millisecond)

          AppLogger.scheduler_info(
            "Scheduled next execution",
            scheduler: inspect(@scheduler_name),
            next_run: DateTime.to_string(next_run),
            minutes_until: div(milliseconds_until_next_run, 60_000)
          )

          # Schedule the next run
          Process.send_after(self(), :execute, milliseconds_until_next_run)
        else
          AppLogger.scheduler_info("#{inspect(@scheduler_name)}: Not scheduling (disabled)")
        end
      end

      # Calculate the next run time based on the current time and the scheduled hour and minute
      defp calculate_next_run(now, hour, minute) do
        # Create a datetime for today at the scheduled time
        today_scheduled = %{now | hour: hour, minute: minute, second: 0, microsecond: {0, 0}}

        # If the scheduled time for today has already passed, schedule for tomorrow
        if DateTime.compare(today_scheduled, now) == :lt do
          # Add 1 day
          DateTime.add(today_scheduled, 86_400, :second)
        else
          today_scheduled
        end
      end

      # Get the configured hour from environment or use default
      defp get_configured_hour do
        if @hour_env_var do
          case Timings.chart_hour() do
            hour when is_integer(hour) and hour >= 0 and hour < 24 -> hour
            _ -> @default_hour
          end
        else
          @default_hour
        end
      end

      # Get the configured minute from environment or use default
      defp get_configured_minute do
        if @minute_env_var do
          case Timings.chart_minute() do
            minute when is_integer(minute) and minute >= 0 and minute < 60 -> minute
            _ -> @default_minute
          end
        else
          @default_minute
        end
      end

      @impl true
      def get_config do
        %{
          type: :time,
          hour: get_configured_hour(),
          minute: get_configured_minute()
        }
      end

      defoverridable get_config: 0
    end
  end
end
