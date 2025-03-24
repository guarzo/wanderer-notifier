defmodule WandererNotifier.Logger.JsonFormatter do
  @moduledoc """
  JSON formatter for Logger that outputs log messages as structured JSON objects.

  This makes logs easier to parse and analyze with tools like ELK stack or other
  log management systems.
  """
  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  @doc """
  Formats a log entry as a JSON object.
  """
  def format(level, message, timestamp, metadata) do
    # Only log formatter debug in development environment
    if Application.get_env(:wanderer_notifier, :env) == :dev do
      AppLogger.processor_debug("Formatting log entry as JSON",
        level: level,
        message_length: String.length(message),
        metadata_count: length(metadata)
      )
    end

    # Convert timestamp to ISO8601 format
    {:ok, formatted_time} = format_timestamp(timestamp)

    # Build the base log entry with most important fields first for readability
    base_object = %{
      timestamp: formatted_time,
      level: level,
      category: metadata[:category] || "GENERAL",
      message: String.trim(message),
      pid: metadata[:pid] || self() |> inspect(),
      trace_id: metadata[:trace_id] || ""
    }

    # Add metadata fields, filtering out any that shouldn't be logged
    metadata_map =
      metadata
      |> Enum.filter(fn {key, _value} -> should_log_key?(key) end)
      |> Enum.into(%{})

    # Merge and encode as JSON
    Map.merge(base_object, metadata_map)
    |> Jason.encode!()
    |> Kernel.<>("\n")
  end

  # Format the timestamp as ISO8601
  defp format_timestamp({date, {hour, minute, second, millisecond}} = timestamp) do
    NaiveDateTime.from_erl!(
      {date, {hour, minute, second}},
      {millisecond * 1000, 3}
    )
    |> NaiveDateTime.to_iso8601()
    |> (&{:ok, &1}).()
  rescue
    _ -> {:ok, "#{inspect(timestamp)}"}
  end

  # Keys that should be excluded from the JSON output
  defp should_log_key?(:pid), do: false
  defp should_log_key?(:gl), do: false
  defp should_log_key?(:time), do: false
  defp should_log_key?(:report_cb), do: false
  defp should_log_key?(_), do: true
end
