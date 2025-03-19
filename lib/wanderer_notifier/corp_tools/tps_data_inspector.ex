defmodule WandererNotifier.CorpTools.TPSDataInspector do
  @moduledoc """
  Utility module to inspect and debug the TPS data structure.
  """
  require Logger
  alias WandererNotifier.CorpTools.CorpToolsClient

  @doc """
  Inspects the TPS data structure and logs the keys and sample data.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.TPSDataInspector.inspect_tps_data()
  ```
  """
  def inspect_tps_data do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        Logger.info("TPS data retrieved successfully")
        Logger.info("Top-level keys: #{inspect(Map.keys(data))}")

        # Inspect each top-level key
        Enum.each(Map.keys(data), fn key ->
          inspect_key(data, key)
        end)

        {:ok, data}

      {:loading, message} ->
        Logger.info("TPS data is still loading: #{message}")
        {:loading, message}

      {:error, reason} ->
        Logger.error("Failed to get TPS data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Inspects a specific key in the TPS data structure.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.TPSDataInspector.inspect_key(data, "Last12MonthsData")
  ```
  """
  def inspect_key(data, key) do
    value = Map.get(data, key)

    Logger.info("Inspecting key: #{key}")

    cond do
      is_map(value) ->
        Logger.info("#{key} is a map with #{map_size(value)} entries")
        Logger.info("#{key} keys: #{inspect(Map.keys(value))}")

        # Sample some entries if it's a large map
        if map_size(value) > 5 do
          sample = Enum.take(value, 3)
          Logger.info("Sample entries from #{key}: #{inspect(sample)}")
        end

      is_list(value) ->
        Logger.info("#{key} is a list with #{length(value)} entries")

        # Sample some entries if it's a large list
        if length(value) > 0 do
          sample = Enum.take(value, min(3, length(value)))
          Logger.info("Sample entries from #{key}: #{inspect(sample)}")

          # If the list contains maps, inspect the keys of the first map
          if length(sample) > 0 and is_map(hd(sample)) do
            Logger.info("First item keys in #{key}: #{inspect(Map.keys(hd(sample)))}")
          end
        end

      true ->
        Logger.info("#{key} is a #{typeof(value)}: #{inspect(value)}")
    end
  end

  @doc """
  Recursively inspects the TPS data structure to a specified depth.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.TPSDataInspector.deep_inspect_tps_data(2)
  ```
  """
  def deep_inspect_tps_data(max_depth \\ 3) do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        Logger.info("Deep inspecting TPS data (max depth: #{max_depth})")
        deep_inspect(data, "root", 0, max_depth)
        {:ok, data}

      {:loading, message} ->
        Logger.info("TPS data is still loading: #{message}")
        {:loading, message}

      {:error, reason} ->
        Logger.error("Failed to get TPS data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper function for deep inspection
  defp deep_inspect(data, path, current_depth, max_depth) do
    indent = String.duplicate("  ", current_depth)

    cond do
      current_depth >= max_depth ->
        Logger.info("#{indent}#{path}: <max depth reached>")

      is_map(data) ->
        Logger.info("#{indent}#{path} (map with #{map_size(data)} entries)")

        if map_size(data) > 0 do
          Enum.each(Enum.take(Map.keys(data), min(10, map_size(data))), fn key ->
            new_path = "#{path}.#{key}"
            deep_inspect(Map.get(data, key), new_path, current_depth + 1, max_depth)
          end)

          if map_size(data) > 10 do
            Logger.info("#{indent}  ... (#{map_size(data) - 10} more entries)")
          end
        end

      is_list(data) ->
        Logger.info("#{indent}#{path} (list with #{length(data)} entries)")

        if length(data) > 0 do
          # Sample the first few items
          Enum.each(Enum.with_index(Enum.take(data, min(5, length(data)))), fn {item, index} ->
            new_path = "#{path}[#{index}]"
            deep_inspect(item, new_path, current_depth + 1, max_depth)
          end)

          if length(data) > 5 do
            Logger.info("#{indent}  ... (#{length(data) - 5} more entries)")
          end
        end

      true ->
        Logger.info("#{indent}#{path} (#{typeof(data)}): #{inspect(data, limit: 100)}")
    end
  end

  # Helper function to get the type of a value
  defp typeof(value) do
    cond do
      is_binary(value) -> "string"
      is_integer(value) -> "integer"
      is_float(value) -> "float"
      is_boolean(value) -> "boolean"
      is_nil(value) -> "nil"
      is_atom(value) -> "atom"
      is_function(value) -> "function"
      is_pid(value) -> "pid"
      is_reference(value) -> "reference"
      is_tuple(value) -> "tuple"
      is_map(value) -> "map"
      is_list(value) -> "list"
      true -> "unknown"
    end
  end
end
