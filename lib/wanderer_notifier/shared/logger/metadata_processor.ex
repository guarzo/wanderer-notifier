defmodule WandererNotifier.Shared.Logger.MetadataProcessor do
  @moduledoc """
  Handles metadata processing and normalization for the logging system.

  This module extracts ~190 lines of metadata handling logic from the main Logger module,
  providing consistent metadata conversion and formatting across all logging operations.

  ## Features
  - Converts various metadata formats to keyword lists
  - Handles maps, keyword lists, and invalid formats gracefully
  - Adds diagnostic information for debugging
  - Provides safe atom conversion
  - Formats values for debug output

  ## Usage
  ```elixir
  alias WandererNotifier.Shared.Logger.MetadataProcessor

  # Convert metadata to keyword list
  metadata = MetadataProcessor.convert_to_keyword_list(%{user_id: 123, action: "login"})

  # Prepare metadata with category
  prepared = MetadataProcessor.prepare_metadata(metadata, :api)

  # Format debug output
  debug_string = MetadataProcessor.format_debug_metadata(metadata)
  ```
  """

  require Logger

  @doc """
  Prepares metadata by converting to keyword list, adding diagnostics, and merging with Logger context.
  """
  def prepare_metadata(metadata, category) do
    # Convert to proper format
    converted_metadata = convert_to_keyword_list(metadata)

    # Add original type info
    metadata_with_type = add_type_info(metadata, converted_metadata)

    # Add category with proper formatting for visibility in the logs
    metadata_with_category = Keyword.put(metadata_with_type, :category, category)

    # Merge with Logger context, but ensure our category takes precedence
    Logger.metadata()
    |> Keyword.delete(:category)
    |> Keyword.merge(metadata_with_category)
  end

  @doc """
  Converts various metadata formats to a keyword list.
  """
  def convert_to_keyword_list(metadata) when is_map(metadata) do
    metadata
    |> Enum.map(fn {k, v} -> {safe_to_atom(k), v} end)
    |> Keyword.put(:_metadata_source, "map")
  end

  def convert_to_keyword_list(metadata) when is_list(metadata) do
    if valid_keyword_list?(metadata) do
      add_metadata_source(metadata, "keyword_list")
    else
      handle_invalid_list(metadata)
    end
  end

  def convert_to_keyword_list(metadata) do
    # Handle any other metadata type
    metadata_type = typeof(metadata)

    Logger.warning("[LOGGER] Invalid metadata type #{metadata_type} - converted to keyword list")

    [
      _metadata_source: "invalid_type",
      _metadata_warning: "Invalid metadata type converted to keyword list",
      _original_type: metadata_type,
      _original_data: "truncated_for_memory",
      _caller: "unavailable_for_performance"
    ]
  end

  @doc """
  Formats metadata for debug output, showing both keys and values.
  """
  def format_debug_metadata(metadata) do
    all_metadata = extract_metadata_for_debug(metadata)
    if all_metadata != "", do: " (#{all_metadata})", else: ""
  end

  @doc """
  Generates a unique trace ID for request tracking.
  """
  def generate_trace_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  @doc """
  Sets Logger metadata context for the current process.
  """
  def set_context(metadata) do
    normalized_metadata = convert_to_keyword_list(metadata)
    Logger.metadata(normalized_metadata)
  end

  @doc """
  Adds trace ID to metadata and sets context.
  """
  def with_trace_id(metadata \\ []) do
    trace_id = generate_trace_id()

    normalized_metadata =
      metadata
      |> convert_to_keyword_list()
      |> Keyword.put(:trace_id, trace_id)

    set_context(normalized_metadata)
    trace_id
  end

  # Private functions

  defp add_type_info(original_metadata, converted_metadata) do
    orig_type = determine_metadata_type(original_metadata)
    Keyword.put(converted_metadata, :orig_metadata_type, orig_type)
  end

  defp determine_metadata_type(metadata) do
    cond do
      is_map(metadata) ->
        "map"

      is_list(metadata) && metadata == [] ->
        "empty_list"

      is_list(metadata) && Enum.all?(metadata, &is_tuple/1) &&
          Enum.all?(metadata, fn {k, _v} -> is_atom(k) end) ->
        "keyword_list"

      is_list(metadata) ->
        "non_keyword_list"

      true ->
        "other_type:#{typeof(metadata)}"
    end
  end

  defp extract_metadata_for_debug(metadata) do
    metadata
    |> Enum.reject(fn {k, _v} ->
      k in [:_metadata_source, :_metadata_warning, :_original_data, :_caller, :orig_metadata_type]
    end)
    |> Enum.map_join(", ", fn {k, v} ->
      formatted_value = format_value_for_debug(v)
      "#{k}=#{formatted_value}"
    end)
  end

  defp format_value_for_debug(value) when is_binary(value),
    do: "\"#{String.slice(value, 0, 100)}\""

  defp format_value_for_debug(value) when is_list(value), do: "list[#{length(value)}]"
  defp format_value_for_debug(value) when is_map(value), do: "map{#{map_size(value)}}"
  defp format_value_for_debug(value), do: inspect(value, limit: 10)

  defp valid_keyword_list?(metadata) do
    metadata == [] ||
      (Enum.all?(metadata, &is_tuple/1) && Enum.all?(metadata, fn {k, _v} -> is_atom(k) end))
  end

  defp handle_invalid_list(metadata) do
    log_invalid_list_warning(metadata)
    convert_invalid_list_to_keyword_list(metadata)
  end

  defp log_invalid_list_warning(metadata) do
    Logger.warning(
      "[LOGGER] Non-keyword list passed as metadata! List size: #{length(metadata)} items"
    )
  end

  defp convert_invalid_list_to_keyword_list(metadata) do
    # Limit conversion to first 10 items to prevent memory issues
    limited_metadata = Enum.take(metadata, 10)

    limited_metadata
    |> Enum.with_index()
    |> Enum.map(fn {value, index} -> {"item_#{index}", value} end)
    |> Enum.into(%{})
    |> Enum.map(fn {k, v} -> {safe_to_atom(k), v} end)
    |> add_metadata_source("invalid_list_converted")
    |> Keyword.put(:_metadata_warning, "Non-keyword list converted to keyword list")
    |> Keyword.put(:_original_data, "truncated_for_memory")
    |> Keyword.put(:_caller, "unavailable_for_performance")
  end

  defp add_metadata_source(metadata, source) do
    Keyword.put(metadata, :_metadata_source, source)
  end

  @doc """
  Safely converts strings or atoms to atoms.
  """
  def safe_to_atom(key) when is_atom(key), do: key

  def safe_to_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError ->
        # For known safe keys, we can create new atoms
        case key do
          "_metadata_source" -> :_metadata_source
          "_metadata_warning" -> :_metadata_warning
          "_original_type" -> :_original_type
          "_original_data" -> :_original_data
          "_caller" -> :_caller
          _ -> String.to_atom("metadata_#{key}")
        end
    end
  end

  def safe_to_atom(key), do: String.to_atom("metadata_#{inspect(key)}")

  @doc """
  Returns the type of a value as a string.
  """
  def typeof(value) when is_binary(value), do: "string"
  def typeof(value) when is_boolean(value), do: "boolean"
  def typeof(value) when is_integer(value), do: "integer"
  def typeof(value) when is_float(value), do: "float"
  def typeof(value) when is_list(value), do: "list"
  def typeof(value) when is_map(value), do: "map"
  def typeof(value) when is_tuple(value), do: "tuple"
  def typeof(value) when is_atom(value), do: "atom"
  def typeof(value) when is_function(value), do: "function"
  def typeof(value) when is_pid(value), do: "pid"
  def typeof(value) when is_reference(value), do: "reference"
  def typeof(value) when is_port(value), do: "port"
  def typeof(_value), do: "unknown"
end
