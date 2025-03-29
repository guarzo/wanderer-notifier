defmodule WandererNotifier.Logger.JsonFormatter do
  @moduledoc """
  JSON formatter for Logger.
  """

  require Logger

  def format(level, message, timestamp, metadata) do
    if get_env() == :dev do
      format_dev(level, message, timestamp, metadata)
    else
      format_json(level, message, timestamp, metadata)
    end
  end

  defp get_env do
    Application.get_env(:wanderer_notifier, :logger, [])
  end

  defp format_dev(level, message, timestamp, metadata) do
    formatted_metadata = format_metadata(metadata)
    formatted_timestamp = format_timestamp(timestamp)

    "[#{formatted_timestamp}] #{level}: #{message}\n#{formatted_metadata}"
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp format_json(level, message, timestamp, metadata) do
    formatted_metadata = format_metadata(metadata)
    formatted_timestamp = format_timestamp(timestamp)

    %{
      level: level,
      message: message,
      timestamp: formatted_timestamp,
      metadata: formatted_metadata
    }
    |> Jason.encode!()
    |> Kernel.<>("\n")
  end

  defp format_metadata(metadata) do
    if get_env() == :dev do
      format_metadata_dev(metadata)
    else
      format_metadata_json(metadata)
    end
  end

  defp format_metadata_dev(metadata) do
    metadata
    |> Enum.map_join(" ", fn {key, value} -> "[#{key}: #{inspect(value)}]" end)
  end

  defp format_metadata_json(metadata) do
    metadata
    |> Enum.into(%{})
  end

  defp format_timestamp({date, {hours, minutes, seconds, milliseconds}}) do
    with {:ok, timestamp} <-
           NaiveDateTime.from_erl({date, {hours, minutes, seconds}}, {milliseconds * 1000, 3}) do
      NaiveDateTime.to_iso8601(timestamp)
    end
  end
end
