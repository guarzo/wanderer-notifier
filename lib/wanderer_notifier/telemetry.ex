defmodule WandererNotifier.Telemetry do
  @moduledoc """
  Centralized telemetry and metrics instrumentation for WandererNotifier.
  Provides a unified interface for emitting events and metrics.
  """

  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Config

  @doc """
  Emits a telemetry event for killmail processing.
  """
  def killmail_processed(kill_id, system_name \\ "unknown") do
    Stats.increment(:kill_processed)
    emit(:killmail, :processed, %{kill_id: kill_id, system: system_name})
  end

  @doc """
  Emits a telemetry event for killmail notification.
  """
  def killmail_notified(kill_id, system_name \\ "unknown") do
    Stats.increment(:kill_notified)
    Stats.track_notification_sent()
    emit(:killmail, :notified, %{kill_id: kill_id, system: system_name})
  end

  @doc """
  Emits a telemetry event for processing start.
  """
  def processing_started(kill_id) do
    Stats.track_processing_start()
    emit(:killmail, :processing_started, %{kill_id: kill_id})
  end

  @doc """
  Emits a telemetry event for processing completion.
  """
  def processing_completed(kill_id, result) do
    Stats.track_processing_complete(result)
    status = if match?({:ok, _}, result), do: :success, else: :error
    emit(:killmail, :processing_completed, %{kill_id: kill_id, status: status})
  end

  @doc """
  Emits a telemetry event for processing skip.
  """
  def processing_skipped(kill_id, reason) do
    Stats.track_processing_skipped()
    emit(:killmail, :processing_skipped, %{kill_id: kill_id, reason: reason})
  end

  @doc """
  Emits a telemetry event for processing error.
  """
  def processing_error(kill_id, error) do
    Stats.track_processing_error()
    emit(:killmail, :processing_error, %{kill_id: kill_id, error: inspect(error)})
  end

  @doc """
  Emits a telemetry event for RedisQ connection status.
  """
  def redisq_status_changed(status) do
    Stats.update_redisq(status)
    emit(:redisq, :status_changed, status)
  end

  @doc """
  Emits a telemetry event for killmail received.
  """
  def killmail_received(kill_id) do
    Stats.track_killmail_received()
    Stats.update_last_activity()
    emit(:killmail, :received, %{kill_id: kill_id})
  end

  @doc """
  Emits a telemetry event for system notification.
  """
  def system_notification_sent(system_id, system_name) do
    Stats.increment(:systems)
    emit(:notification, :system, %{system_id: system_id, system_name: system_name})
  end

  @doc """
  Emits a telemetry event for character notification.
  """
  def character_notification_sent(character_id, character_name) do
    Stats.increment(:characters)
    emit(:notification, :character, %{character_id: character_id, character_name: character_name})
  end

  @doc """
  Emits a telemetry event for cache hit/miss.
  """
  def cache_event(operation, key, hit?) do
    metric = if hit?, do: :hit, else: :miss
    emit(:cache, metric, %{operation: operation, key: key})
  end

  @doc """
  Emits a telemetry event for API calls.
  """
  def api_call(service, endpoint, duration_ms, success?) do
    status = if success?, do: :success, else: :error

    emit(:api, status, %{
      service: service,
      endpoint: endpoint,
      duration_ms: duration_ms
    })
  end

  @doc """
  Emits a telemetry event for scheduler runs.
  """
  def scheduler_run(scheduler, duration_ms, result) do
    status = if match?({:ok, _}, result), do: :success, else: :error

    emit(:scheduler, :run, %{
      scheduler: scheduler,
      duration_ms: duration_ms,
      status: status
    })
  end

  # Private helper to emit telemetry events
  defp emit(event_type, event_name, metadata) do
    event = [:wanderer_notifier, event_type, event_name]
    measurements = %{timestamp: WandererNotifier.Utils.TimeUtils.monotonic_ms()}

    :telemetry.execute(event, measurements, metadata)

    # Log for debugging if enabled
    if Config.telemetry_logging_enabled?() do
      AppLogger.processor_debug("Telemetry event",
        event: event,
        measurements: measurements,
        metadata: metadata
      )
    end
  rescue
    error ->
      # Don't let telemetry errors crash the application
      AppLogger.processor_debug("Telemetry error: #{inspect(error)}")
  end
end
