defmodule WandererNotifier.Shared.Telemetry do
  @moduledoc """
  Telemetry and metrics instrumentation for WandererNotifier.
  """

  alias WandererNotifier.Shared.Metrics
  require Logger
  alias WandererNotifier.Shared.Config

  @doc """
  Emits a telemetry event for killmail processing.
  """
  def killmail_processed(kill_id, system_name \\ "unknown") do
    Metrics.increment(:kill_processed)
    emit(:killmail, :processed, %{kill_id: kill_id, system: system_name})
  end

  @doc """
  Emits a telemetry event for killmail notification.
  """
  def killmail_notified(kill_id, system_name \\ "unknown") do
    Metrics.increment(:kill_notified)
    Metrics.increment(:notification_sent)
    emit(:killmail, :notified, %{kill_id: kill_id, system: system_name})
  end

  @doc """
  Emits a telemetry event for processing start.
  """
  def processing_started(kill_id) do
    Metrics.increment(:killmail_processing_start)
    emit(:killmail, :processing_started, %{kill_id: kill_id})
  end

  @doc """
  Emits a telemetry event for processing completion.
  """
  def processing_completed(kill_id, result) do
    Metrics.increment(:killmail_processing_complete)
    status = if match?({:ok, _}, result), do: :success, else: :error
    emit(:killmail, :processing_completed, %{kill_id: kill_id, status: status})
  end

  @doc """
  Emits a telemetry event for processing skip.
  """
  def processing_skipped(kill_id, reason) do
    Metrics.increment(:killmail_processing_skipped)
    emit(:killmail, :processing_skipped, %{kill_id: kill_id, reason: reason})
  end

  @doc """
  Emits a telemetry event for processing error.
  """
  def processing_error(kill_id, error) do
    Metrics.increment(:killmail_processing_error)
    emit(:killmail, :processing_error, %{kill_id: kill_id, error: inspect(error)})
  end

  @doc """
  Emits a telemetry event for killmail received.
  """
  def killmail_received(kill_id) do
    Metrics.increment(:killmail_received)
    # Health status is now tracked by simple process checks
    emit(:killmail, :received, %{kill_id: kill_id})
  end

  @doc """
  Emits a telemetry event for system notification.
  """
  def system_notification_sent(system_id, system_name) do
    Metrics.increment(:systems)
    emit(:notification, :system, %{system_id: system_id, system_name: system_name})
  end

  @doc """
  Emits a telemetry event for character notification.
  """
  def character_notification_sent(character_id, character_name) do
    Metrics.increment(:characters)
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
    measurements = %{timestamp: WandererNotifier.Shared.Utils.TimeUtils.monotonic_ms()}

    :telemetry.execute(event, measurements, metadata)

    # Log for debugging if enabled
    if Config.telemetry_logging_enabled?() do
      Logger.debug("Telemetry event",
        event: event,
        measurements: measurements,
        metadata: metadata
      )
    end
  rescue
    error ->
      # Don't let telemetry errors crash the application
      Logger.debug("Telemetry error: #{inspect(error)}")
  end
end
