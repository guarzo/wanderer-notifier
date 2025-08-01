defmodule WandererNotifier.Domains.Universe.Services.CsvProcessor do
  @moduledoc """
  Processes CSV files from Fuzzworks to extract item types and ship data.
  
  This module handles parsing the invTypes.csv and invGroups.csv files
  to build a comprehensive database of EVE Online items and ships.
  """

  require Logger
  alias NimbleCSV.RFC4180, as: CSVParser
  alias WandererNotifier.Domains.Universe.Entities.ItemType
  alias WandererNotifier.Shared.Utils.ErrorHandler

  # Ship group IDs from EVE Online (these groups contain ships)
  @ship_group_ids [6, 7, 9, 11, 16, 17, 23, 25, 26, 27, 28, 29, 30, 31, 237, 324, 358, 380, 381, 463, 540, 541, 543, 547, 659, 830, 831, 832, 833, 834, 883, 893, 894, 906, 963, 1022, 1201, 1202, 1283, 1305, 1527, 1534, 1538, 1972, 2016]

  @type csv_result :: %{
    items: %{integer() => ItemType.t()},
    ships: %{integer() => ItemType.t()},
    stats: map()
  }

  @doc """
  Processes CSV files to extract all item types and ships.
  
  Returns a map containing items, ships, and processing statistics.
  """
  @spec process_csv_files(String.t(), String.t()) :: {:ok, csv_result()} | {:error, term()}
  def process_csv_files(types_path, groups_path) do
    ErrorHandler.safe_execute(
      fn -> do_process_csv_files(types_path, groups_path) end,
      context: %{types_path: types_path, groups_path: groups_path}
    )
  end

  @doc """
  Gets the list of ship group IDs.
  """
  @spec ship_group_ids() :: [integer()]
  def ship_group_ids, do: @ship_group_ids

  # Private functions

  defp do_process_csv_files(types_path, groups_path) do
    Logger.info("Processing CSV files for item types and ships")
    start_time = System.monotonic_time()

    with {:ok, groups_map} <- parse_groups_file(groups_path),
         {:ok, {items_map, ships_map, stats}} <- parse_types_file(types_path, groups_map) do
      
      processing_time = System.monotonic_time() - start_time
      final_stats = Map.put(stats, :processing_time_ms, System.convert_time_unit(processing_time, :native, :millisecond))
      
      Logger.info("CSV processing completed", 
        items: map_size(items_map),
        ships: map_size(ships_map),
        processing_time_ms: final_stats.processing_time_ms
      )

      {:ok, %{items: items_map, ships: ships_map, stats: final_stats}}
    end
  end

  defp parse_groups_file(groups_path) do
    Logger.debug("Parsing groups file: #{groups_path}")

    with {:ok, content} <- File.read(groups_path),
         {:ok, groups} <- parse_groups_csv(content) do
      
      groups_map = Map.new(groups, fn group -> {group.group_id, group.name} end)
      Logger.debug("Parsed #{map_size(groups_map)} groups")
      
      {:ok, groups_map}
    end
  end

  defp parse_groups_csv(content) do
    groups = 
      content
      |> CSVParser.parse_string()
      |> Stream.drop(1)  # Skip header
      |> Stream.map(&parse_group_row/1)
      |> Stream.filter(&(&1 != nil))
      |> Enum.to_list()

    {:ok, groups}
  rescue
    e ->
      Logger.error("Failed to parse groups CSV: #{inspect(e)}")
      {:error, :groups_parse_failed}
  end

  defp parse_group_row([group_id_str, _category_id_str, name | _rest]) do
    case Integer.parse(group_id_str) do
      {group_id, ""} ->
        %{group_id: group_id, name: String.trim(name)}
      
      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp parse_types_file(types_path, groups_map) do
    Logger.debug("Parsing types file: #{types_path}")

    with {:ok, content} <- File.read(types_path),
         {:ok, {items, ships, stats}} <- parse_types_csv(content, groups_map) do
      
      Logger.debug("Parsed #{length(items)} items and #{length(ships)} ships")
      {:ok, {Map.new(items, &{&1.type_id, &1}), Map.new(ships, &{&1.type_id, &1}), stats}}
    end
  end

  defp parse_types_csv(content, groups_map) do
    items_and_ships = 
      content
      |> CSVParser.parse_string()
      |> Stream.drop(1)  # Skip header
      |> Stream.map(&parse_type_row(&1, groups_map))
      |> Stream.filter(&(&1 != nil))
      |> Enum.to_list()

    {items, ships} = partition_items_and_ships(items_and_ships)
    
    stats = %{
      total_parsed: length(items_and_ships),
      items_count: length(items),
      ships_count: length(ships)
    }

    {:ok, {items, ships, stats}}
  rescue
    e ->
      Logger.error("Failed to parse types CSV: #{inspect(e)}")
      {:error, :types_parse_failed}
  end

  defp parse_type_row(row, groups_map) do
    case row do
      [type_id_str, group_id_str, name, _description | rest] ->
        with {type_id, ""} <- Integer.parse(type_id_str),
             {group_id, ""} <- Integer.parse(group_id_str),
             true <- valid_item?(name, type_id, group_id) do
          
          parse_full_type_data(type_id, group_id, name, rest, groups_map)
        else
          _ -> nil
        end
      
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp valid_item?(name, type_id, group_id) do
    is_binary(name) and 
    String.trim(name) != "" and 
    is_integer(type_id) and 
    type_id > 0 and
    is_integer(group_id) and 
    group_id > 0
  end

  defp parse_full_type_data(type_id, group_id, name, rest, groups_map) do
    # Extract additional fields from the CSV row
    [mass_str, volume_str, capacity_str, portion_size_str, race_id_str, 
     base_price_str, published_str, market_group_id_str, icon_id_str, 
     sound_id_str, graphic_id_str | _] = rest ++ List.duplicate("", 20)  # Pad with empty strings

    csv_data = %{
      type_id: type_id,
      name: String.trim(name),
      group_id: group_id,
      mass: parse_float(mass_str),
      volume: parse_float(volume_str),
      capacity: parse_float(capacity_str),
      portion_size: parse_integer(portion_size_str, 1),
      race_id: parse_integer(race_id_str),
      base_price: parse_float(base_price_str),
      published: parse_boolean(published_str),
      market_group_id: parse_integer(market_group_id_str),
      icon_id: parse_integer(icon_id_str),
      sound_id: parse_integer(sound_id_str),
      graphic_id: parse_integer(graphic_id_str)
    }

    group_name = Map.get(groups_map, group_id)
    is_ship = group_id in @ship_group_ids

    ItemType.from_csv_data(csv_data, group_name, is_ship)
  end

  defp partition_items_and_ships(items_and_ships) do
    Enum.reduce(items_and_ships, {[], []}, fn item, {items, ships} ->
      if ItemType.ship?(item) do
        {items, [item | ships]}
      else
        {[item | items], ships}
      end
    end)
  end

  # Parsing helpers

  defp parse_integer(""), do: nil
  defp parse_integer(nil), do: nil
  defp parse_integer(str) when is_binary(str) do
    case Integer.parse(String.trim(str)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(str, default) when is_binary(str) do
    parse_integer(str) || default
  end

  defp parse_float(""), do: 0.0
  defp parse_float(nil), do: 0.0
  defp parse_float(str) when is_binary(str) do
    case Float.parse(String.trim(str)) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  defp parse_boolean("1"), do: true
  defp parse_boolean("True"), do: true
  defp parse_boolean("true"), do: true
  defp parse_boolean(_), do: false
end