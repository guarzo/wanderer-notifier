defmodule WandererNotifier.Helpers.CacheHelpers do
  @moduledoc """
  Helper functions for working with the cache.
  """
  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

  @doc """
  Gets all tracked systems from the cache.
  Handles both the old format (list of system IDs) and the new format (list of system maps).
  Also checks both "map:systems" and "tracked:systems" keys for comprehensive tracking.
  """
  def get_tracked_systems do
    map_systems = get_systems_from_cache("map:systems")
    tracked_systems = get_systems_from_cache("tracked:systems")

    # Merge both lists, avoiding duplicates based on system_id
    merged_systems = merge_systems_lists(map_systems, tracked_systems)

    # Only log system details occasionally (10% of requests)
    # This is also high-volume during kill processing
    if :rand.uniform(10) == 1 do
      AppLogger.cache_debug(
        "Retrieved tracked systems (sampled 10%)",
        total_count: length(merged_systems),
        map_systems_count: length(map_systems),
        tracked_systems_count: length(tracked_systems)
      )
    end

    # Ensure all systems are properly cached for direct lookup
    ensure_systems_individual_cache(merged_systems)

    merged_systems
  end

  @doc """
  Ensures that all tracked systems are also cached individually with the "tracked:system:ID" key
  for direct and efficient lookup.
  """
  def ensure_systems_individual_cache(systems) when is_list(systems) do
    Enum.each(systems, &cache_individual_system/1)
  end

  # Cache an individual system
  defp cache_individual_system(system) do
    with system_id when not is_nil(system_id) <- extract_system_id(system) do
      system_id_str = to_string(system_id)
      # Cache for direct lookup
      CacheRepo.put("tracked:system:#{system_id_str}", true)

      # Ensure system data is stored
      ensure_system_data_cached(system, system_id_str)
    end
  end

  # Ensure system data is cached
  defp ensure_system_data_cached(system, system_id_str) do
    if !CacheRepo.get("map:system:#{system_id_str}") do
      # Create and store system data
      system_data = create_system_data(system, system_id_str)
      CacheRepo.put("map:system:#{system_id_str}", system_data)
    end
  end

  # Create system data for caching
  defp create_system_data(system, system_id_str) do
    case system do
      # Already a map, use it
      s when is_map(s) -> s
      # Just an ID, create minimal map
      _ -> %{"system_id" => system_id_str, "solar_system_id" => system_id_str}
    end
  end

  @doc """
  Add a system to the tracked systems list and ensure it's properly cached
  for direct lookup.

  Returns :ok if successful, {:error, reason} otherwise.
  """
  def add_system_to_tracked(system_id, system_name \\ nil) do
    system_id_str = to_string(system_id)

    # Prepare system data and update caches
    system_data = prepare_system_data(system_id_str, system_name)

    # Use transaction-like approach to update all caches
    update_system_tracking(system_id_str, system_data)

    :ok
  end

  # Prepare system data map
  defp prepare_system_data(system_id_str, system_name) do
    base_data = %{
      "solar_system_id" => system_id_str,
      "system_id" => system_id_str
    }

    # Add name if provided
    if system_name, do: Map.put(base_data, "name", system_name), else: base_data
  end

  # Update all system tracking data in a single function
  defp update_system_tracking(system_id_str, system_data) do
    # Update tracking list
    update_tracked_systems_list(system_id_str, system_data)

    # Update direct lookup cache
    CacheRepo.put("tracked:system:#{system_id_str}", true)

    # Add to map:system:{id} if not already there
    add_to_system_map_if_needed(system_id_str, system_data)
  end

  # Update the tracked systems list
  defp update_tracked_systems_list(system_id_str, system_data) do
    CacheRepo.get_and_update("tracked:systems", fn systems ->
      systems = systems || []

      if system_already_tracked?(systems, system_id_str) do
        {systems, :already_tracked}
      else
        {[system_data | systems], :added}
      end
    end)
  end

  # Check if system is already tracked
  defp system_already_tracked?(systems, system_id_str) do
    entity_already_tracked?(systems, system_id_str, &extract_system_id/1)
  end

  # Add system to map cache if needed
  defp add_to_system_map_if_needed(system_id_str, system_data) do
    if !CacheRepo.get("map:system:#{system_id_str}") do
      CacheRepo.put("map:system:#{system_id_str}", system_data)
    end
  end

  @doc """
  Remove a system from the tracked systems lists and cache

  Returns :ok if successful, {:error, reason} otherwise.
  """
  def remove_system_from_tracked(system_id) do
    system_id_str = to_string(system_id)
    remove_entity_from_tracked("systems", system_id_str, &extract_system_id/1)
  end

  # Helper functions to extract system ID from different formats
  defp extract_system_id(system) when is_map(system) do
    extract_system_id_from_map(system)
  end

  defp extract_system_id(system) when is_integer(system) or is_binary(system) do
    system
  end

  defp extract_system_id(_), do: nil

  # Extract from map with atom or string keys
  defp extract_system_id_from_map(map) when is_map(map) do
    find_id_from_keys(map, [:solar_system_id, :system_id, "solar_system_id", "system_id"])
  end

  @doc """
  Gets all tracked characters from the cache.
  Handles both character objects and character IDs, similar to systems.
  Also checks both "map:characters" and "tracked:characters" keys for comprehensive tracking.
  """
  def get_tracked_characters do
    try do
      # Get and validate characters from each source
      map_characters_list = get_and_validate_cache_data("map:characters")
      tracked_characters_list = get_and_validate_cache_data("tracked:characters")

      # Process each list to standardize character data
      map_characters_processed = Enum.flat_map(map_characters_list, &normalize_character_data/1)

      tracked_characters_processed =
        Enum.flat_map(tracked_characters_list, &normalize_character_data/1)

      # Merge characters from both sources, removing duplicates by ID
      all_characters =
        merge_characters_lists(map_characters_processed, tracked_characters_processed)

      # Sample log character details occasionally
      sample_log_character_data(
        all_characters,
        map_characters_processed,
        tracked_characters_processed
      )

      all_characters
    rescue
      e ->
        # Log any errors in character processing
        AppLogger.cache_error(
          "ERROR retrieving tracked characters: #{Exception.message(e)}",
          stacktrace: Exception.format_stacktrace()
        )

        []
    end
  end

  # Get and validate data from cache by key
  defp get_and_validate_cache_data(cache_key) do
    data = CacheRepo.get(cache_key)

    # Validate expected data types
    if !(is_nil(data) || is_list(data)) do
      AppLogger.cache_error(
        "ERROR: Expected nil or list from #{cache_key} but got: #{inspect(data)}"
      )
    end

    # Return as list or empty list if nil/invalid
    if is_list(data), do: data, else: []
  end

  # Sample log character data occasionally for debugging
  defp sample_log_character_data(all_characters, map_characters, tracked_characters) do
    # Only log character details occasionally (10% of requests)
    # This is extremely high-volume during kill processing
    if :rand.uniform(10) == 1 do
      AppLogger.cache_debug(
        "Retrieved tracked characters (sampled 10%)",
        total_count: length(all_characters),
        map_characters_count: length(map_characters),
        tracked_characters_count: length(tracked_characters)
      )

      # Sample for debugging (only when sampling)
      if length(all_characters) > 0 do
        sample = Enum.take(all_characters, min(2, length(all_characters)))
        AppLogger.cache_debug("Sample character data (sampled): #{inspect(sample)}")
      end
    end
  end

  # Helper to normalize character data regardless of its format
  defp normalize_character_data(%WandererNotifier.Data.Character{} = char), do: [char]
  defp normalize_character_data(char) when is_map(char), do: [char]

  defp normalize_character_data(char_id) when is_binary(char_id) or is_integer(char_id),
    do: [%{"character_id" => to_string(char_id)}]

  defp normalize_character_data({:ok, data}) do
    AppLogger.cache_error(
      "ERROR: Received wrapped data {:ok, value} in normalize_character_data: #{inspect(data)}. This should not occur with the updated repository."
    )

    normalize_character_data(data)
  end

  defp normalize_character_data(data) when is_list(data),
    do: Enum.flat_map(data, &normalize_character_data/1)

  defp normalize_character_data(other) do
    AppLogger.cache_error(
      "ERROR: Received unexpected data type in normalize_character_data: #{inspect(other)}. This should be investigated and fixed at the source."
    )

    []
  end

  # Helper functions to extract character ID from different formats
  defp extract_character_id(char) when is_map(char) do
    extract_character_id_from_map(char)
  end

  defp extract_character_id(char) when is_integer(char) or is_binary(char) do
    to_string(char)
  end

  defp extract_character_id(_), do: nil

  # Extract from map with atom or string keys
  defp extract_character_id_from_map(map) when is_map(map) do
    id = find_id_from_keys(map, [:character_id, "character_id"])
    if id, do: to_string(id), else: nil
  end

  @doc """
  Ensures that all tracked characters are also cached individually with the "tracked:character:ID" key
  for direct and efficient lookup.
  """
  def ensure_characters_individual_cache(characters) when is_list(characters) do
    Enum.each(characters, &cache_individual_character/1)
  end

  # Cache an individual character
  defp cache_individual_character(character) do
    with character_id when not is_nil(character_id) <- extract_character_id(character) do
      character_id_str = to_string(character_id)
      # Cache for direct lookup
      CacheRepo.put("tracked:character:#{character_id_str}", true)

      # Ensure character data is stored
      ensure_character_data_cached(character, character_id_str)
    end
  end

  # Ensure character data is cached
  defp ensure_character_data_cached(character, character_id_str) do
    if !CacheRepo.get("map:character:#{character_id_str}") do
      # Create and store character data
      character_data = create_character_data(character, character_id_str)
      CacheRepo.put("map:character:#{character_id_str}", character_data)
    end
  end

  # Create character data for caching
  defp create_character_data(character, character_id_str) do
    case character do
      # Already a map, use it
      c when is_map(c) -> c
      # Just an ID, create minimal map
      _ -> %{"character_id" => character_id_str}
    end
  end

  @doc """
  Add a character to the tracked characters list and ensure it's properly cached
  for direct lookup.

  Returns :ok if successful, {:error, reason} otherwise.
  """
  def add_character_to_tracked(character_id, character_name \\ nil) do
    character_id_str = to_string(character_id)

    # Prepare character data and update caches
    character_data = prepare_character_data(character_id_str, character_name)

    # Use transaction-like approach to update all caches
    update_character_tracking(character_id_str, character_data)

    :ok
  end

  # Prepare character data map
  defp prepare_character_data(character_id_str, character_name) do
    base_data = %{"character_id" => character_id_str}

    # Add name if provided
    if character_name, do: Map.put(base_data, "name", character_name), else: base_data
  end

  # Update all character tracking data in a single function
  defp update_character_tracking(character_id_str, character_data) do
    # Update tracking list
    update_tracked_characters_list(character_id_str, character_data)

    # Update direct lookup cache
    CacheRepo.put("tracked:character:#{character_id_str}", true)

    # Add to map:character:{id} if not already there
    add_to_character_map_if_needed(character_id_str, character_data)
  end

  # Update the tracked characters list
  defp update_tracked_characters_list(character_id_str, character_data) do
    CacheRepo.get_and_update("tracked:characters", fn characters ->
      characters = characters || []

      if character_already_tracked?(characters, character_id_str) do
        {characters, :already_tracked}
      else
        {[character_data | characters], :added}
      end
    end)
  end

  # Check if character is already tracked
  defp character_already_tracked?(characters, character_id_str) do
    entity_already_tracked?(characters, character_id_str, &extract_character_id/1)
  end

  # Add character to map cache if needed
  defp add_to_character_map_if_needed(character_id_str, character_data) do
    if !CacheRepo.get("map:character:#{character_id_str}") do
      CacheRepo.put("map:character:#{character_id_str}", character_data)
    end
  end

  @doc """
  Remove a character from the tracked characters lists and cache

  Returns :ok if successful, {:error, reason} otherwise.
  """
  def remove_character_from_tracked(character_id) do
    character_id_str = to_string(character_id)
    remove_entity_from_tracked("characters", character_id_str, &extract_character_id/1)
  end

  # Helper to get systems from a specific cache key
  defp get_systems_from_cache(cache_key) do
    case CacheRepo.get(cache_key) do
      nil -> []
      systems when is_list(systems) -> process_systems_list(systems)
      _ -> []
    end
  end

  # Process a list of systems
  defp process_systems_list([]), do: []

  defp process_systems_list([first | _] = systems) when is_map(first) do
    # We have the full system objects
    systems
  end

  defp process_systems_list(system_ids) do
    # We have a list of system IDs, fetch each system
    fetch_systems_by_ids(system_ids)
  end

  # Helper to fetch systems by IDs
  defp fetch_systems_by_ids(system_ids) do
    system_ids
    |> Enum.map(&fetch_system_by_id/1)
    |> Enum.filter(& &1)
  end

  # Helper to fetch a single system by ID
  defp fetch_system_by_id(system_id) do
    case CacheRepo.get("map:system:#{system_id}") do
      # Keep the ID even if we can't fetch the system
      nil -> system_id
      system -> system
    end
  end

  # Helper to merge systems lists avoiding duplicates
  defp merge_systems_lists(list1, list2) do
    merge_entity_lists(list1, list2, &extract_system_id/1)
  end

  # Helper to merge characters lists avoiding duplicates
  defp merge_characters_lists(list1, list2) do
    merge_entity_lists(list1, list2, &extract_character_id/1)
  end

  # Generic function to merge entity lists (DRY principle)
  defp merge_entity_lists(list1, list2, id_extractor) do
    # Extract IDs from first list to check for duplicates
    list1_ids =
      list1
      |> Enum.map(id_extractor)
      |> Enum.filter(& &1)
      |> MapSet.new()

    # Filter out duplicates from second list
    unique_list2 =
      Enum.filter(list2, fn entity ->
        id = id_extractor.(entity)
        id && !MapSet.member?(list1_ids, id)
      end)

    # Combine lists
    list1 ++ unique_list2
  end

  # Generic entity removal function (DRY principle)
  defp remove_entity_from_tracked(entity_type, id_str, id_extractor) do
    # Remove from tracked list
    CacheRepo.get_and_update("tracked:#{entity_type}", fn entities ->
      entities = entities || []

      # Filter out the entity to remove
      updated_entities =
        Enum.reject(entities, fn entity ->
          id_extractor.(entity) == id_str
        end)

      {updated_entities, :removed}
    end)

    # Remove direct lookup cache entry
    CacheRepo.delete("tracked:#{entity_type |> String.slice(0..-2//1)}:#{id_str}")

    :ok
  end

  # Generic entity tracking check function (DRY principle)
  defp entity_already_tracked?(entities, id_str, id_extractor) do
    Enum.any?(entities, fn entity ->
      extracted_id = id_extractor.(entity)
      extracted_id && to_string(extracted_id) == id_str
    end)
  end

  # Helper to find an ID from a list of possible keys
  defp find_id_from_keys(map, keys) do
    Enum.find_value(keys, fn key ->
      Map.get(map, key)
    end)
  end
end
