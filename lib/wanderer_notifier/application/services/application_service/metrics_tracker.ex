defmodule WandererNotifier.Application.Services.ApplicationService.MetricsTracker do
  @moduledoc """
  Handles metrics tracking for the ApplicationService.

  Consolidates the functionality from the original Stats module into
  a focused metrics tracking component.
  """

  require Logger
  alias WandererNotifier.Application.Services.ApplicationService.State
  alias WandererNotifier.Shared.Utils.TimeUtils

  @killmail_metrics [
    :killmail_processing_start,
    :killmail_processing_complete,
    :killmail_processing_complete_success,
    :killmail_processing_complete_error,
    :killmail_processing_skipped,
    :killmail_processing_error,
    :notification_sent
  ]

  @doc """
  Initializes the metrics tracker.
  """
  @spec initialize(State.t()) :: {:ok, State.t()}
  def initialize(state) do
    Logger.debug("Initializing metrics tracker...", category: :startup)
    {:ok, state}
  end

  @doc """
  Increments a metric counter.
  """
  @spec increment_metric(State.t(), atom()) :: {:ok, State.t()}
  def increment_metric(state, type) do
    new_state = State.update_metrics(state, fn metrics ->
      update_metric_by_type(metrics, type)
    end)

    {:ok, new_state}
  end

  defp update_metric_by_type(metrics, :kill_processed) do
    update_processing_metric(metrics, :kills_processed)
  end

  defp update_metric_by_type(metrics, :kill_notified) do
    update_processing_metric(metrics, :kills_notified)
  end

  defp update_metric_by_type(metrics, type) when type in @killmail_metrics do
    counters = Map.update(metrics.counters, type, 1, &(&1 + 1))
    %{metrics | counters: counters}
  end

  defp update_metric_by_type(metrics, type) do
    # Handle notification type increments
    notifications =
      metrics.notifications
      |> Map.update(type, 1, &(&1 + 1))
      |> Map.update(:total, 1, &(&1 + 1))

    %{metrics | notifications: notifications}
  end

  defp update_processing_metric(metrics, key) do
    processing = Map.update(metrics.processing, key, 1, &(&1 + 1))
    %{metrics | processing: processing}
  end

  @doc """
  Checks if this is the first notification of a specific type.
  """
  @spec first_notification?(State.t(), atom()) :: boolean()
  def first_notification?(state, type) when type in [:kill, :character, :system] do
    Map.get(state.metrics.first_notifications, type, true)
  end

  @doc """
  Marks that a notification of the given type has been sent.
  """
  @spec mark_notification_sent(State.t(), atom()) :: {:ok, State.t()}
  def mark_notification_sent(state, type) when type in [:kill, :character, :system] do
    new_state = State.update_metrics(state, fn metrics ->
      first_notifications = Map.put(metrics.first_notifications, type, false)
      %{metrics | first_notifications: first_notifications}
    end)

    Logger.debug("Marked #{type} notification as sent - no longer first notification",
      category: :config
    )

    {:ok, new_state}
  end

  @doc """
  Sets the tracked count for systems or characters.
  """
  @spec set_tracked_count(State.t(), atom(), non_neg_integer()) :: {:ok, State.t()}
  def set_tracked_count(state, type, count) when type in [:systems, :characters] and is_integer(count) do
    new_state = State.update_metrics(state, fn metrics ->
      key = case type do
        :systems -> :systems_count
        :characters -> :characters_count
      end
      Map.put(metrics, key, count)
    end)

    {:ok, new_state}
  end

  @doc """
  Gets comprehensive statistics from the current state.
  """
  @spec get_stats(State.t()) :: map()
  def get_stats(state) do
    metrics = state.metrics

    uptime_seconds =
      case metrics.startup_time do
        nil -> 0
        startup_time -> TimeUtils.elapsed_seconds(startup_time)
      end

    %{
      uptime: TimeUtils.format_uptime(uptime_seconds),
      uptime_seconds: uptime_seconds,
      startup_time: metrics.startup_time,
      notifications: metrics.notifications,
      processing: metrics.processing,
      first_notifications: metrics.first_notifications,
      systems_count: metrics.systems_count,
      characters_count: metrics.characters_count,
      counters: metrics.counters,
      health: state.health
    }
  end

  @doc """
  Prints a summary of current statistics to the log.
  """
  @spec print_summary(State.t()) :: :ok
  def print_summary(state) do
    stats = get_stats(state)

    # Format key metrics
    uptime = stats.uptime
    notifications = stats.notifications
    processing = stats.processing
    counters = stats.counters

    # Extract key counters
    processing_start = Map.get(counters, :killmail_processing_start, 0)
    processing_complete = Map.get(counters, :killmail_processing_complete, 0)
    processing_skipped = Map.get(counters, :killmail_processing_skipped, 0)
    processing_error = Map.get(counters, :killmail_processing_error, 0)

    Logger.info("📊 Application Stats Summary:
    Uptime: #{uptime}
    Notifications: #{notifications.total} total (#{notifications.kills} kills, #{notifications.systems} systems, #{notifications.characters} characters)
    Processing: #{processing.kills_processed} kills processed, #{processing.kills_notified} kills notified
    Killmail Metrics: #{processing_start} started, #{processing_complete} completed, #{processing_skipped} skipped, #{processing_error} errors
    Tracked: #{stats.systems_count} systems, #{stats.characters_count} characters",
      category: :application
    )
  end
end
