defmodule WandererNotifier.Telemetry do
  @moduledoc """
  Centralized telemetry and metrics tracking for WandererNotifier.

  This module provides a standardized interface for emitting events and tracking metrics
  across the application. It uses the built-in Telemetry library for event emission
  and integrates with the Stats module for persistent metrics storage.
  """

  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Event names for different types of telemetry
  @events [
    # Killmail processing events
    :killmail_processing_start,
    :killmail_processing_complete,
    :killmail_processing_error,
    :killmail_processing_skipped,
    :killmail_received,

    # Notification events
    :notification_sent,
    :notification_skipped,
    :notification_error,

    # RedisQ events
    :redisq_connected,
    :redisq_disconnected,
    :redisq_message_received,

    # Cache events
    :cache_hit,
    :cache_miss,
    :cache_error,

    # HTTP events
    :http_request_start,
    :http_request_complete,
    :http_request_error,

    # Scheduler events
    :scheduler_update_start,
    :scheduler_update_complete,
    :scheduler_update_error
  ]

  # Metric types for different categories of measurements
  @metric_types [
    # Counters
    :counter,
    # Gauges
    :gauge,
    # Histograms
    :histogram
  ]

  @doc """
  Emits a telemetry event with the given name and measurements.

  ## Parameters
    - event_name: The name of the event to emit (must be one of @events)
    - measurements: A map of measurements to include with the event
    - metadata: Additional metadata to include with the event

  ## Examples
      iex> Telemetry.emit(:killmail_processing_start, %{duration_ms: 100})
      :ok
  """
  @spec emit(atom(), map(), map()) :: :ok
  def emit(event_name, measurements \\ %{}, metadata \\ %{}) when event_name in @events do
    # Emit the telemetry event
    :telemetry.execute([:wanderer_notifier, event_name], measurements, metadata)

    # Update stats if this is a counter-type event
    if counter_event?(event_name) do
      Stats.increment(event_name)
    end

    # Log the event for debugging
    AppLogger.telemetry_debug("Telemetry event emitted",
      event: event_name,
      measurements: measurements,
      metadata: metadata
    )
  end

  @doc """
  Records a metric value for the given name.

  ## Parameters
    - metric_name: The name of the metric to record
    - value: The value to record
    - type: The type of metric (must be one of @metric_types)
    - metadata: Additional metadata to include with the metric

  ## Examples
      iex> Telemetry.record_metric(:processing_duration_ms, 100, :histogram)
      :ok
  """
  @spec record_metric(atom(), number(), atom(), map()) :: :ok
  def record_metric(metric_name, value, type \\ :gauge, metadata \\ %{})
      when type in @metric_types do
    # Emit the telemetry event with the metric
    :telemetry.execute(
      [:wanderer_notifier, :metric, type],
      %{value: value},
      Map.put(metadata, :metric_name, metric_name)
    )

    # Log the metric for debugging
    AppLogger.telemetry_debug("Metric recorded",
      metric: metric_name,
      value: value,
      type: type,
      metadata: metadata
    )
  end

  @doc """
  Records a duration metric by measuring the time taken to execute a function.

  ## Parameters
    - metric_name: The name of the metric to record
    - fun: The function to measure
    - metadata: Additional metadata to include with the metric

  ## Examples
      iex> Telemetry.measure_duration(:processing_time, fn -> Process.sleep(100) end)
      :ok
  """
  @spec measure_duration(atom(), (-> any()), map()) :: :ok
  def measure_duration(metric_name, fun, metadata \\ %{}) do
    start_time = System.monotonic_time()
    result = fun.()
    end_time = System.monotonic_time()

    duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    record_metric(metric_name, duration, :histogram, metadata)

    result
  end

  # Private helper functions

  defp counter_event?(event_name) do
    # List of events that should increment counters in Stats
    event_name in [
      :killmail_processing_start,
      :killmail_processing_complete,
      :killmail_processing_error,
      :killmail_processing_skipped,
      :killmail_received,
      :notification_sent,
      :notification_skipped,
      :notification_error,
      :redisq_connected,
      :redisq_disconnected,
      :redisq_message_received,
      :cache_hit,
      :cache_miss,
      :cache_error
    ]
  end
end
