defmodule WandererNotifierWeb.Telemetry.EndpointHandler do
  @moduledoc """
  Custom telemetry handler for Phoenix endpoint events.
  Filters out health check endpoints from logging to reduce noise.
  """

  require Logger

  @health_paths ["/api/health", "/health", "/api/status"]

  def attach do
    :telemetry.attach_many(
      "wanderer-notifier-endpoint-handler",
      [
        [:phoenix, :endpoint, :start],
        [:phoenix, :endpoint, :stop]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:phoenix, :endpoint, :stop], measurements, metadata, _config) do
    # Only log non-health-check requests
    if should_log?(metadata) do
      duration = System.convert_time_unit(measurements.duration, :native, :microsecond)

      Logger.info(
        "#{metadata.conn.method} #{metadata.conn.request_path} - " <>
          "Responded in #{duration}µs"
      )
    end
  end

  def handle_event([:phoenix, :endpoint, :start], _measurements, _metadata, _config) do
    # We don't need to log request starts
    :ok
  end

  # Check if we should log this request
  defp should_log?(%{conn: conn}) do
    conn.request_path not in @health_paths
  end

  defp should_log?(_), do: true
end
