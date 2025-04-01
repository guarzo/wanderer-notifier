defmodule WandererNotifier.Logger.StartupTracker do
  @moduledoc """
  Tracks application startup phases and provides consolidated logging.

  This module helps reduce redundant startup logs by:
  - Tracking distinct startup phases
  - Consolidating logs within each phase
  - Only logging significant state changes
  - Providing summary logs at the end of each phase
  """

  require Logger
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Startup phases
  @phases [
    # Initial app boot
    :initialization,
    # Loading dependencies and setting up env
    :dependencies,
    # Starting core services
    :services,
    # Cache initialization
    :cache,
    # Network connections
    :network,
    # Database connections
    :database,
    # Scheduler initialization
    :schedulers,
    # Web server startup
    :web,
    # Final startup tasks
    :completion
  ]

  # Events that should always be logged regardless of phase
  @significant_events [
    # Any error event
    :error,
    # Any warning
    :warning,
    # Feature enablement/disablement
    :feature_status,
    # External API connections
    :api_connection,
    # Database connection status
    :database_status,
    # Scheduler status changes (reduce duplicate logs)
    :scheduler_summary
  ]

  @doc """
  Initializes the startup tracker.

  Should be called at the very beginning of application startup.
  Returns the initial state for the startup tracker.
  """
  def init do
    # Create initial state
    state = %{
      start_time: System.monotonic_time(:millisecond),
      current_phase: :initialization,
      completed_phases: [],
      phase_timing: %{},
      events: %{},
      counts: %{},
      errors: []
    }

    # Store in process dictionary
    Process.put(:startup_tracker, state)

    # Log startup beginning
    AppLogger.startup_info("Starting application (consolidated startup logs enabled)")

    state
  end

  @doc """
  Begins a new startup phase.

  ## Parameters

  - phase: The phase to begin
  - message: Optional message about this phase
  """
  def begin_phase(phase, message \\ nil) do
    if phase not in @phases do
      raise ArgumentError, "Invalid startup phase: #{inspect(phase)}"
    end

    # Get current state
    state = Process.get(:startup_tracker) || init()

    # Mark the previous phase as complete
    phase_timing =
      Map.put(
        state.phase_timing,
        state.current_phase,
        %{
          started_at: state.start_time,
          completed_at: System.monotonic_time(:millisecond)
        }
      )

    completed_phases = [state.current_phase | state.completed_phases]

    # Log the phase transition
    if message do
      AppLogger.startup_info("#{String.upcase(to_string(phase))}: #{message}")
    else
      AppLogger.startup_info("Beginning #{String.upcase(to_string(phase))} phase")
    end

    # Update state with new phase
    new_state = %{
      state
      | current_phase: phase,
        completed_phases: completed_phases,
        phase_timing: phase_timing,
        start_time: System.monotonic_time(:millisecond)
    }

    Process.put(:startup_tracker, new_state)

    new_state
  end

  @doc """
  Records a startup event without necessarily logging it.

  Events are accumulated and may be summarized later.

  ## Parameters

  - type: The type of event
  - details: Map of event details
  - force_log: If true, will log immediately regardless of significance
  """
  def record_event(type, details \\ %{}, force_log \\ false) do
    # Get current state
    state = Process.get(:startup_tracker) || init()

    # Update event counts
    event_key = "#{state.current_phase}_#{type}"
    counts = Map.update(state.counts, event_key, 1, &(&1 + 1))

    # Add to events list
    events =
      Map.update(
        state.events,
        event_key,
        [details],
        fn existing -> [details | existing] end
      )

    # Check if this should be logged immediately
    if force_log || type in @significant_events do
      log_level = get_log_level_for_event(type)
      AppLogger.log(log_level, "STARTUP", format_event(type, details))
    end

    # Update state
    new_state = %{state | counts: counts, events: events}
    Process.put(:startup_tracker, new_state)

    new_state
  end

  @doc """
  Records an error during startup.

  Errors are always logged immediately.

  ## Parameters

  - message: Error message
  - details: Additional error details
  """
  def record_error(message, details \\ %{}) do
    # Get current state
    state = Process.get(:startup_tracker) || init()

    # Add to errors list
    errors = [%{message: message, details: details, phase: state.current_phase} | state.errors]

    # Always log errors immediately
    AppLogger.startup_error("ERROR: #{message}", details)

    # Update state
    new_state = %{state | errors: errors}
    Process.put(:startup_tracker, new_state)

    new_state
  end

  @doc """
  Completes the startup process and logs a summary.
  """
  def complete_startup do
    # Get current state
    state = Process.get(:startup_tracker) || init()

    # Calculate total duration
    start_time = state.phase_timing[:initialization][:started_at] || 0
    total_duration_ms = System.monotonic_time(:millisecond) - start_time

    # Generate summary
    AppLogger.startup_info("Startup completed in #{format_duration(total_duration_ms)}")

    # Log phase timing
    phases_summary =
      Enum.map(state.phase_timing, fn {phase, timing} ->
        duration = timing[:completed_at] - timing[:started_at]
        "#{phase}: #{format_duration(duration)}"
      end)

    AppLogger.startup_debug("Startup phases: #{Enum.join(phases_summary, ", ")}")

    # Log event counts if there are any interesting ones
    interesting_counts = Enum.filter(state.counts, fn {_, count} -> count > 1 end)

    if !Enum.empty?(interesting_counts) do
      count_summary =
        Enum.map(interesting_counts, fn {key, count} ->
          "#{key}: #{count}"
        end)

      AppLogger.startup_debug("Event counts: #{Enum.join(count_summary, ", ")}")
    end

    # Log errors if any
    if !Enum.empty?(state.errors) do
      AppLogger.startup_warn("Startup completed with #{length(state.errors)} errors")
    end

    # Clear state
    Process.delete(:startup_tracker)

    :ok
  end

  @doc """
  Logs a significant state change during startup.

  These are always logged immediately.

  ## Parameters

  - type: The type of state change
  - message: The message about the state change
  - details: Additional details
  """
  def log_state_change(type, message, details \\ %{}) do
    # Log immediately and record
    AppLogger.startup_info("#{String.upcase(to_string(type))}: #{message}")
    record_event(type, Map.put(details, :message, message), true)
  end

  # Helper functions

  # Get the appropriate log level for an event
  defp get_log_level_for_event(:error), do: :error
  defp get_log_level_for_event(:warning), do: :warning
  defp get_log_level_for_event(_), do: :info

  # Format an event for logging
  defp format_event(type, details) do
    base = String.upcase(to_string(type))

    if Map.has_key?(details, :message) do
      "#{base}: #{details.message}"
    else
      "#{base} event recorded"
    end
  end

  # Format a duration in milliseconds
  defp format_duration(ms) do
    cond do
      ms < 1000 -> "#{ms}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{Float.round(ms / 60_000, 1)}m"
    end
  end
end
