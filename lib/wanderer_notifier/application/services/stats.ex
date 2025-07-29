defmodule WandererNotifier.Application.Services.Stats do
  @moduledoc """
  Backward compatibility adapter for the Stats service.
  
  This module maintains the existing Stats API while delegating
  to the new ApplicationService for actual functionality.
  
  This allows existing code to continue working without changes
  while we gradually migrate to the new unified service.
  """
  
  alias WandererNotifier.Application.Services.ApplicationService
  
  # ──────────────────────────────────────────────────────────────────────────────
  # GenServer API (for supervision compatibility)
  # ──────────────────────────────────────────────────────────────────────────────
  
  @doc """
  Starts the Stats adapter (no-op, actual service is ApplicationService).
  """
  def start_link(_opts \\ []) do
    # This is a no-op since ApplicationService handles the actual functionality
    # We return a fake GenServer to satisfy supervision requirements
    Agent.start_link(fn -> :ok end, name: __MODULE__)
  end

  @doc """
  Provides child specification for supervision.
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
  
  # ──────────────────────────────────────────────────────────────────────────────
  # Original Stats API - delegated to ApplicationService
  # ──────────────────────────────────────────────────────────────────────────────
  
  @doc "Increments the count for a specific notification type."
  def increment(type), do: ApplicationService.increment_metric(type)
  
  @doc "Alias for increment/1, provided for backward compatibility."
  def update(type), do: ApplicationService.increment_metric(type)
  
  @doc "Track the start of killmail processing."
  def track_processing_start, do: ApplicationService.increment_metric(:killmail_processing_start)
  
  @doc "Track the completion of killmail processing."
  def track_processing_complete(result) do
    ApplicationService.increment_metric(:killmail_processing_complete)
    
    # Also track success or error specifically
    status = if match?({:ok, _}, result), do: :success, else: :error
    ApplicationService.increment_metric(:"killmail_processing_complete_#{status}")
  end
  
  @doc "Track a skipped killmail."
  def track_processing_skipped, do: ApplicationService.increment_metric(:killmail_processing_skipped)
  
  @doc "Track a processing error."
  def track_processing_error, do: ApplicationService.increment_metric(:killmail_processing_error)
  
  @doc "Track a notification being sent."
  def track_notification_sent, do: ApplicationService.increment_metric(:notification_sent)
  
  @doc "Track a killmail received from RedisQ/zkill."
  def track_killmail_received, do: ApplicationService.increment_metric(:killmail_received)
  
  @doc "Updates the last activity timestamp."
  def update_last_activity, do: ApplicationService.update_health(:redisq, %{last_message: DateTime.utc_now()})
  
  @doc "Updates WebSocket connection stats."
  def update_websocket_stats(stats), do: ApplicationService.update_health(:websocket, stats)
  
  @doc "Returns the current statistics."
  def get_stats, do: ApplicationService.get_stats()
  
  @doc "Updates the redisq status."
  def update_redisq(status), do: ApplicationService.update_health(:redisq, status)
  
  @doc "Checks if this is the first notification of a specific type."
  def is_first_notification?(type), do: ApplicationService.first_notification?(type)
  
  @doc "Marks that the first notification of a specific type has been sent."
  def mark_notification_sent(type), do: ApplicationService.mark_notification_sent(type)
  
  @doc "Prints a summary of current statistics to the log."
  def print_summary do
    stats = ApplicationService.get_stats()
    require Logger
    
    # Use the original format for compatibility
    uptime = stats.uptime
    notifications = stats.notifications
    processing = stats.processing
    
    Logger.info("📊 Stats Summary:
    Uptime: #{uptime}
    Notifications: #{notifications.total} total (#{notifications.kills} kills, #{notifications.systems} systems, #{notifications.characters} characters)
    Processing: #{processing.kills_processed} kills processed, #{processing.kills_notified} kills notified",
      category: :processor
    )
  end
  
  @doc "Sets the tracked count for a specific type (:systems or :characters)."
  def set_tracked_count(type, count) when type in [:systems, :characters] and is_integer(count) do
    # This would need to be implemented in ApplicationService.MetricsTracker
    # For now, this is a no-op to maintain compatibility
    :ok
  end
end