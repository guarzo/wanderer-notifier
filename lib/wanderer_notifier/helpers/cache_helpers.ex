defmodule WandererNotifier.Helpers.CacheHelpers do
  @moduledoc """
  Helper functions for working with the cache.
  """

  @behaviour WandererNotifier.Helpers.CacheHelpersBehaviour

  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Data.Cache.Repository
  alias WandererNotifier.Api.ESI.Service, as: ESIService

  # Get the repository module to use - either the mock during testing or the real repo
  defp repo_module do
    Application.get_env(
      :wanderer_notifier,
      :cache_repository,
      WandererNotifier.Data.Cache.Repository
    )
  end

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
      repo_module().put("tracked:system:#{system_id_str}", true)

      # Ensure system data is stored
      ensure_system_data_cached(system, system_id_str)
    end
  end

  # Ensure system data is cached
  defp ensure_system_data_cached(system, system_id_str) do
    if !repo_module().get("map:system:#{system_id_str}") do
      # Create and store system data
      system_data = create_system_data(system, system_id_str)
      repo_module().put("map:system:#{system_id_str}", system_data)
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
    repo_module().put("tracked:system:#{system_id_str}", true)

    # Add to map:system:{id} if not already there
    add_to_system_map_if_needed(system_id_str, system_data)
  end

  # Update the tracked systems list
  defp update_tracked_systems_list(system_id_str, system_data) do
    repo_module().get_and_update("tracked:systems", fn systems ->
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
    if !repo_module().get("map:system:#{system_id_str}") do
      repo_module().put("map:system:#{system_id_str}", system_data)
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

  @impl true
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
      merge_characters_lists(map_characters_processed, tracked_characters_processed)
    catch
      kind, error ->
        AppLogger.cache_error("Error getting tracked characters",
          error: Exception.format(kind, error, __STACKTRACE__)
        )

        []
    end
  end

  # Get and validate data from cache by key
  defp get_and_validate_cache_data(cache_key) do
    data = repo_module().get(cache_key)

    # Validate expected data types
    if !(is_nil(data) || is_list(data)) do
      AppLogger.cache_error(
        "ERROR: Expected nil or list from #{cache_key} but got: #{inspect(data)}"
      )
    end

    # Return as list or empty list if nil/invalid
    if is_list(data), do: data, else: []
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
      repo_module().put("tracked:character:#{character_id_str}", true)

      # Ensure character data is stored
      ensure_character_data_cached(character, character_id_str)
    end
  end

  # Ensure character data is cached
  defp ensure_character_data_cached(character, character_id_str) do
    if !repo_module().get("map:character:#{character_id_str}") do
      # Create and store character data
      character_data = create_character_data(character, character_id_str)
      repo_module().put("map:character:#{character_id_str}", character_data)
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
    repo_module().put("tracked:character:#{character_id_str}", true)

    # Add to map:character:{id} if not already there
    add_to_character_map_if_needed(character_id_str, character_data)
  end

  # Update the tracked characters list
  defp update_tracked_characters_list(character_id_str, character_data) do
    repo_module().get_and_update("tracked:characters", fn characters ->
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
    if !repo_module().get("map:character:#{character_id_str}") do
      repo_module().put("map:character:#{character_id_str}", character_data)
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
    systems = repo_module().get(cache_key)

    if is_list(systems) do
      systems
    else
      []
    end
  end

  # Helper to find an ID from multiple possible keys in a map
  defp find_id_from_keys(map, possible_keys) do
    Enum.find_value(possible_keys, fn key ->
      value = Map.get(map, key)
      if value, do: value, else: nil
    end)
  end

  # Remove entity (system or character) from tracked list and cache
  defp remove_entity_from_tracked(entity_type, entity_id_str, id_extractor) do
    cache_key = "tracked:#{entity_type}"

    # Get current tracked list
    list = repo_module().get(cache_key) || []

    # Remove the entity from the list
    updated_list =
      Enum.reject(list, fn entity ->
        entity_id = id_extractor.(entity)
        entity_id_str == to_string(entity_id)
      end)

    # Update the list in the cache
    repo_module().put(cache_key, updated_list)

    # Remove the direct lookup entry
    repo_module().delete("tracked:#{String.slice(entity_type, 0..-2//1)}:#{entity_id_str}")

    :ok
  end

  # Helper to merge two lists of systems avoiding duplicates
  defp merge_systems_lists(map_systems, tracked_systems) do
    # Create lookup map of system IDs already seen
    {result, _seen} =
      Enum.reduce(map_systems, {[], %{}}, fn system, {acc, seen} ->
        system_id = extract_system_id(system)

        if is_nil(system_id) || seen[to_string(system_id)] do
          {acc, seen}
        else
          {[system | acc], Map.put(seen, to_string(system_id), true)}
        end
      end)

    # Add systems from tracked_systems if not already seen
    {merged, _seen} =
      Enum.reduce(tracked_systems, {result, %{}}, fn system, {acc, seen} ->
        system_id = extract_system_id(system)

        if is_nil(system_id) || seen[to_string(system_id)] do
          {acc, seen}
        else
          {[system | acc], Map.put(seen, to_string(system_id), true)}
        end
      end)

    merged
  end

  # Helper to check if an entity is already tracked
  defp entity_already_tracked?(entities, entity_id_str, id_extractor) do
    Enum.any?(entities, fn entity ->
      entity_id = id_extractor.(entity)
      entity_id && to_string(entity_id) == entity_id_str
    end)
  end

  # Helper to merge character lists, avoiding duplicates
  defp merge_characters_lists(map_characters, tracked_characters) do
    characters_map =
      Enum.reduce(map_characters ++ tracked_characters, %{}, fn char, acc ->
        char_id = extract_character_id(char)

        if is_nil(char_id) do
          acc
        else
          Map.put_new(acc, char_id, char)
        end
      end)

    Map.values(characters_map)
  end

  @impl true
  def get_character_name(nil), do: {:ok, "Unknown"}

  def get_character_name(character_id) do
    cache_key = "character:name:#{character_id}"

    case Repository.get(cache_key) do
      nil ->
        case ESIService.get_character_info(to_string(character_id)) do
          {:ok, char_info} ->
            name = char_info["name"]
            # Cache for 24 hours
            Repository.set(cache_key, name, 86_400)
            {:ok, name}

          error ->
            error
        end

      name ->
        {:ok, name}
    end
  end

  @impl true
  def get_ship_name(nil), do: {:ok, "Unknown"}

  def get_ship_name(ship_type_id) do
    cache_key = "ship:name:#{ship_type_id}"

    case Repository.get(cache_key) do
      nil ->
        case ESIService.get_type_info(ship_type_id) do
          {:ok, type_info} ->
            name = type_info["name"]
            # Cache for 24 hours
            Repository.set(cache_key, name, 86_400)
            {:ok, name}

          error ->
            error
        end

      name ->
        {:ok, name}
    end
  end
end
