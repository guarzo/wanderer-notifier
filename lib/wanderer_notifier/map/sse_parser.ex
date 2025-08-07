defmodule WandererNotifier.Map.SSEParser do
  require Logger

  @moduledoc """
  Handles parsing of Server-Sent Events (SSE) data.

  This module is responsible for parsing raw SSE chunks into structured events
  according to the SSE specification.
  """

  @doc """
  Parses an SSE chunk into a list of events.

  ## Parameters
  - `chunk` - Raw SSE data chunk

  ## Returns
  - `{:ok, events}` - List of parsed events
  - `{:error, reason}` - Parse error
  """
  @spec parse_chunk(binary()) :: {:ok, list(map())} | {:error, term()}
  def parse_chunk(chunk) do
    # Parse SSE chunk according to SSE specification
    # SSE format: "event: event_type\ndata: json_data\nid: event_id\n\n"

    try do
      events =
        for event_str <- String.split(chunk, "\n\n"),
            String.trim(event_str) != "",
            {:ok, event} <- [parse_single_event(event_str)],
            do: event

      {:ok, events}
    rescue
      error ->
        {:error, {:parse_error, error}}
    end
  end

  @doc """
  Parses a single SSE event string into a structured event.

  ## Parameters
  - `event_str` - Single SSE event as a string

  ## Returns
  - `{:ok, event}` - Parsed event map
  - `{:error, reason}` - Parse error
  """
  @spec parse_single_event(binary()) :: {:ok, map()} | {:error, term()}
  def parse_single_event(event_str) do
    event_str
    |> String.split("\n")
    |> parse_lines()
    |> decode_event_data()
  end

  # Private functions

  defp parse_lines(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      parse_line(line, acc)
    end)
  end

  defp parse_line(line, acc) do
    case String.split(line, ": ", parts: 2) do
      ["data", data] -> Map.update(acc, "data", data, fn existing -> existing <> "\n" <> data end)
      ["event", event_type] -> Map.put(acc, "event", event_type)
      ["id", event_id] -> Map.put(acc, "id", event_id)
      _ -> acc
    end
  end

  defp decode_event_data(%{"data" => data_str} = event_data) do
    case Jason.decode(data_str) do
      {:ok, parsed_data} ->
        event = build_event(parsed_data, event_data)
        log_parsed_event(event)
        {:ok, event}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp decode_event_data(_), do: {:error, :no_data}

  defp build_event(parsed_data, event_data) do
    Map.merge(parsed_data, %{
      "type" => Map.get(event_data, "event", "unknown"),
      "id" => Map.get(event_data, "id")
    })
  end

  defp log_parsed_event(event) do
    Logger.debug("Parsed SSE event",
      event_type: Map.get(event, "type"),
      event_id: Map.get(event, "id"),
      event_map_id: Map.get(event, "map_id")
    )
  end
end
