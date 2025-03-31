defmodule WandererNotifier.Processing.Killmail.Stats do
  @moduledoc """
  Tracks and reports statistics about processed kills.

  Maintains counters for:
  - Total kills received
  - Total notifications sent
  - Last kill time
  - Application uptime
  """

  alias WandererNotifier.Core.Application.Service, as: AppService
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Process dictionary key for kill stats
  @kill_stats_key :kill_processor_stats
  # Process dictionary key for timer reference
  @log_timer_key :kill_stats_log_timer

  @doc """
  Initialize statistics tracking.
  Sets up the initial counters in process dictionary.
  """
  def init do
    # Cancel any existing timer to prevent duplicates
    cancel_existing_timer()

    Process.put(@kill_stats_key, %{
      total_kills_received: 0,
      total_notifications_sent: 0,
      last_kill_time: nil,
      start_time: :os.system_time(:second)
    })

    AppLogger.kill_info("Kill statistics tracking initialized")

    # Start the logging schedule
    schedule_logging()
  end

  @doc """
  Schedule periodic logging of kill statistics.
  Ensures only one timer is active at a time.
  """
  def schedule_logging do
    # Cancel any existing timer first
    cancel_existing_timer()

    # Send the message to the main Service module since that's where GenServer is implemented
    timer_ref =
      Process.send_after(
        AppService,
        :log_kill_stats,
        # Changed from Timings.cache_check_interval() (5 seconds) to 60 seconds
        60_000
      )

    # Store the timer reference in process dictionary
    Process.put(@log_timer_key, timer_ref)

    AppLogger.kill_debug("Kill statistics logging scheduled")
  end

  # Helper to cancel any existing timer
  defp cancel_existing_timer do
    case Process.get(@log_timer_key) do
      nil ->
        :ok

      timer_ref ->
        Process.cancel_timer(timer_ref)
        Process.put(@log_timer_key, nil)
    end
  end

  @doc """
  Log the current kill statistics.
  Shows processed kills, notifications, last kill time, and uptime.
  """
  def log do
    stats =
      Process.get(@kill_stats_key) ||
        %{
          total_kills_received: 0,
          total_notifications_sent: 0,
          last_kill_time: nil,
          start_time: :os.system_time(:second)
        }

    current_time = :os.system_time(:second)
    uptime_seconds = current_time - stats.start_time
    hours = div(uptime_seconds, 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)
    seconds = rem(uptime_seconds, 60)

    # Format the last kill time if available
    last_kill_ago =
      if stats.last_kill_time do
        time_diff = current_time - stats.last_kill_time

        cond do
          time_diff < 60 -> "#{time_diff} seconds ago"
          time_diff < 3600 -> "#{div(time_diff, 60)} minutes ago"
          true -> "#{div(time_diff, 3600)} hours ago"
        end
      else
        "none received"
      end

    AppLogger.kill_info(
      "📊 KILL STATS: Processed #{stats.total_kills_received} kills, sent #{stats.total_notifications_sent} notifications. Last kill: #{last_kill_ago}. Uptime: #{hours}h #{minutes}m #{seconds}s"
    )

    # Reschedule stats logging - make sure we only have one active timer
    schedule_logging()
  end

  @doc """
  Update kill statistics.

  ## Parameters
  - type: The type of event to update, either :kill_received or :notification_sent
  """
  def update(type) when type in [:kill_received, :notification_sent] do
    stats =
      Process.get(@kill_stats_key) ||
        %{
          total_kills_received: 0,
          total_notifications_sent: 0,
          last_kill_time: nil,
          start_time: :os.system_time(:second)
        }

    # Update the appropriate counter
    updated_stats =
      case type do
        :kill_received ->
          %{
            stats
            | total_kills_received: stats.total_kills_received + 1,
              last_kill_time: :os.system_time(:second)
          }

        :notification_sent ->
          %{stats | total_notifications_sent: stats.total_notifications_sent + 1}
      end

    # Store the updated stats
    Process.put(@kill_stats_key, updated_stats)
  end

  @doc """
  Get the current kill statistics.
  """
  def get do
    Process.get(@kill_stats_key) ||
      %{
        total_kills_received: 0,
        total_notifications_sent: 0,
        last_kill_time: nil,
        start_time: :os.system_time(:second)
      }
  end
end
