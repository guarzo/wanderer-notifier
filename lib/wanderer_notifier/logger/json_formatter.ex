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
    # Convert metadata safely to ensure proper JSON serialization
    metadata_map =
      metadata
      |> Enum.filter(fn {key, _value} -> should_log_key?(key) end)
      |> Enum.map(fn {k, v} -> 
        # Ensure values are JSON serializable by converting complex types to strings
        {k, prepare_value_for_json(v)}
      end)
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
  
  # Helper function to ensure values are JSON serializable
  defp prepare_value_for_json(value) do
    cond do
      # Simple scalar types are directly serializable
      is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value) ->
        value
        
      # For atoms, convert to strings
      is_atom(value) ->
        Atom.to_string(value)
        
      # For maps, recursively prepare all values
      is_map(value) -> 
        value 
        |> Enum.map(fn {k, v} -> 
          # Convert key to string if it's an atom
          key_str = if is_atom(k), do: Atom.to_string(k), else: k
          {key_str, prepare_value_for_json(v)}
        end)
        |> Enum.into(%{})
        
      # For lists, recursively prepare all items
      is_list(value) -> 
        # Handle keyword lists specially to preserve their key-value nature
        if Keyword.keyword?(value) do
          value
          |> Enum.map(fn {k, v} -> {Atom.to_string(k), prepare_value_for_json(v)} end)
          |> Enum.into(%{})
        else
          Enum.map(value, &prepare_value_for_json/1)
        end
        
      # For tuples, convert to lists
      is_tuple(value) ->
        value
        |> Tuple.to_list()
        |> Enum.map(&prepare_value_for_json/1)
      
      # For other types (pids, refs, etc.) convert to strings
      true -> 
        inspect(value)
    end
  end
end
