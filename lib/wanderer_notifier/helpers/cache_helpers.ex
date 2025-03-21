defmodule WandererNotifier.Helpers.CacheHelpers do
  @moduledoc """
  Helper functions for working with the cache.
  """
  require Logger
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

    Logger.debug(
      "CacheHelpers.get_tracked_systems: Retrieved #{length(merged_systems)} total systems (#{length(map_systems)} from map:systems, #{length(tracked_systems)} from tracked:systems)"
    )

    # Ensure all systems are properly cached for direct lookup
    ensure_systems_individual_cache(merged_systems)

    merged_systems
  end

  @doc """
  Ensures that all tracked systems are also cached individually with the "tracked:system:ID" key
  for direct and efficient lookup.
  """
  def ensure_systems_individual_cache(systems) when is_list(systems) do
    Enum.each(systems, fn system ->
      case extract_system_id(system) do
        nil ->
          nil

        system_id ->
          # Normalize to string
          system_id_str = to_string(system_id)

          # Cache for direct lookup
          CacheRepo.put("tracked:system:#{system_id_str}", true)

          # Also make sure the system data is stored
          unless CacheRepo.get("map:system:#{system_id_str}") do
            # Build a system data structure to cache
            system_data =
              case system do
                # Already a map, use it
                s when is_map(s) -> s
                # Just an ID, create minimal map
                _ -> %{"system_id" => system_id_str, "solar_system_id" => system_id_str}
              end

            # Store in main system cache
            CacheRepo.put("map:system:#{system_id_str}", system_data)
          end
      end
    end)
  end

  @doc """
  Add a system to the tracked systems list and ensure it's properly cached
  for direct lookup.

  Returns :ok if successful, {:error, reason} otherwise.
  """
  def add_system_to_tracked(system_id, system_name \\ nil) do
    system_id_str = to_string(system_id)

    # System data to add
    system_data = %{
      "solar_system_id" => system_id_str,
      "system_id" => system_id_str
    }

    # Add name if provided
    system_data = if system_name, do: Map.put(system_data, "name", system_name), else: system_data

    # First, add to the tracked:systems list
    CacheRepo.get_and_update("tracked:systems", fn systems ->
      systems = systems || []

      # Check if system is already tracked
      if Enum.any?(systems, fn s -> extract_system_id(s) == system_id_str end) do
        {systems, :already_tracked}
      else
        # Add to tracked systems
        {[system_data | systems], :added}
      end
    end)

    # Also add direct lookup cache entry
    CacheRepo.put("tracked:system:#{system_id_str}", true)

    # Also add to map:system:{id} if not already there
    unless CacheRepo.get("map:system:#{system_id_str}") do
      CacheRepo.put("map:system:#{system_id_str}", system_data)
    end

    :ok
  end

  @doc """
  Remove a system from the tracked systems lists and cache

  Returns :ok if successful, {:error, reason} otherwise.
  """
  def remove_system_from_tracked(system_id) do
    system_id_str = to_string(system_id)

    # Remove from tracked:systems list
    CacheRepo.get_and_update("tracked:systems", fn systems ->
      systems = systems || []

      # Filter out the system to remove
      updated_systems =
        Enum.reject(systems, fn s ->
          extract_system_id(s) == system_id_str
        end)

      {updated_systems, :removed}
    end)

    # Remove direct lookup cache entry
    CacheRepo.delete("tracked:system:#{system_id_str}")

    :ok
  end

  # Helper function to extract system ID from different formats
  defp extract_system_id(system) do
    cond do
      is_map(system) && Map.has_key?(system, :solar_system_id) ->
        system.solar_system_id

      is_map(system) && Map.has_key?(system, "solar_system_id") ->
        system["solar_system_id"]

      is_map(system) && Map.has_key?(system, :system_id) ->
        system.system_id

      is_map(system) && Map.has_key?(system, "system_id") ->
        system["system_id"]

      is_integer(system) || is_binary(system) ->
        system

      true ->
        nil
    end
  end

  @doc """
  Gets all tracked characters from the cache.
  Handles both character objects and character IDs, similar to systems.
  Also checks both "map:characters" and "tracked:characters" keys for comprehensive tracking.
  """
  def get_tracked_characters do
    map_characters = get_characters_from_cache("map:characters")
    tracked_characters = get_characters_from_cache("tracked:characters")

    # Merge both lists, avoiding duplicates based on character_id
    merged_characters = merge_characters_lists(map_characters, tracked_characters)

    Logger.debug(
      "CacheHelpers.get_tracked_characters: Retrieved #{length(merged_characters)} total characters (#{length(map_characters)} from map:characters, #{length(tracked_characters)} from tracked:characters)"
    )

    # Log sample for debugging
    if length(merged_characters) > 0 do
      sample = Enum.take(merged_characters, min(2, length(merged_characters)))
      Logger.debug("CacheHelpers.get_tracked_characters: Sample data: #{inspect(sample)}")
    end

    # Ensure all characters are properly cached for direct lookup
    ensure_characters_individual_cache(merged_characters)

    merged_characters
  end

  @doc """
  Ensures that all tracked characters are also cached individually with the "tracked:character:ID" key
  for direct and efficient lookup.
  """
  def ensure_characters_individual_cache(characters) when is_list(characters) do
    Enum.each(characters, fn character ->
      case extract_character_id(character) do
        nil ->
          nil

        character_id ->
          # Normalize to string
          character_id_str = to_string(character_id)

          # Cache for direct lookup
          CacheRepo.put("tracked:character:#{character_id_str}", true)

          # Also make sure the character data is stored
          unless CacheRepo.get("map:character:#{character_id_str}") do
            # Build a character data structure to cache
            character_data =
              case character do
                # Already a map, use it
                c when is_map(c) -> c
                # Just an ID, create minimal map
                _ -> %{"character_id" => character_id_str}
              end

            # Store in main character cache
            CacheRepo.put("map:character:#{character_id_str}", character_data)
          end
      end
    end)
  end

  @doc """
  Add a character to the tracked characters list and ensure it's properly cached
  for direct lookup.

  Returns :ok if successful, {:error, reason} otherwise.
  """
  def add_character_to_tracked(character_id, character_name \\ nil) do
    character_id_str = to_string(character_id)

    # Character data to add
    character_data = %{"character_id" => character_id_str}

    # Add name if provided
    character_data =
      if character_name, do: Map.put(character_data, "name", character_name), else: character_data

    # First, add to the tracked:characters list
    CacheRepo.get_and_update("tracked:characters", fn characters ->
      characters = characters || []

      # Check if character is already tracked
      if Enum.any?(characters, fn c -> extract_character_id(c) == character_id_str end) do
        {characters, :already_tracked}
      else
        # Add to tracked characters
        {[character_data | characters], :added}
      end
    end)

    # Also add direct lookup cache entry
    CacheRepo.put("tracked:character:#{character_id_str}", true)

    # Also add to map:character:{id} if not already there
    unless CacheRepo.get("map:character:#{character_id_str}") do
      CacheRepo.put("map:character:#{character_id_str}", character_data)
    end

    :ok
  end

  @doc """
  Remove a character from the tracked characters lists and cache

  Returns :ok if successful, {:error, reason} otherwise.
  """
  def remove_character_from_tracked(character_id) do
    character_id_str = to_string(character_id)

    # Remove from tracked:characters list
    CacheRepo.get_and_update("tracked:characters", fn characters ->
      characters = characters || []

      # Filter out the character to remove
      updated_characters =
        Enum.reject(characters, fn c ->
          extract_character_id(c) == character_id_str
        end)

      {updated_characters, :removed}
    end)

    # Remove direct lookup cache entry
    CacheRepo.delete("tracked:character:#{character_id_str}")

    :ok
  end

  # Helper to get systems from a specific cache key
  defp get_systems_from_cache(cache_key) do
    case CacheRepo.get(cache_key) do
      nil ->
        []

      systems when is_list(systems) ->
        # Check if we have a list of system objects or just IDs
        if length(systems) > 0 and is_map(List.first(systems)) do
          # We have the full system objects
          systems
        else
          # We have a list of system IDs, fetch each system
          Enum.map(systems, fn system_id ->
            case CacheRepo.get("map:system:#{system_id}") do
              # Keep the ID even if we can't fetch the system
              nil -> system_id
              system -> system
            end
          end)
          |> Enum.filter(& &1)
        end

      _ ->
        []
    end
  end

  # Helper to get characters from a specific cache key
  defp get_characters_from_cache(cache_key) do
    case CacheRepo.get(cache_key) do
      nil ->
        []

      characters when is_list(characters) ->
        # Check if we have a list of character objects or just IDs
        if length(characters) > 0 and is_map(List.first(characters)) do
          # We have the full character objects
          characters
        else
          # We have a list of character IDs, fetch each character
          Enum.map(characters, fn character_id ->
            case CacheRepo.get("map:character:#{character_id}") do
              # Keep the ID even if we can't fetch the character
              nil -> character_id
              character -> character
            end
          end)
          |> Enum.filter(& &1)
        end

      _ ->
        []
    end
  end

  # Helper to merge systems lists avoiding duplicates
  defp merge_systems_lists(list1, list2) do
    # Extract IDs from first list to check for duplicates
    list1_ids =
      list1
      |> Enum.map(&extract_system_id/1)
      |> Enum.filter(& &1)
      |> MapSet.new()

    # Filter out duplicates from second list
    unique_list2 =
      Enum.filter(list2, fn system ->
        id = extract_system_id(system)
        id && !MapSet.member?(list1_ids, id)
      end)

    # Combine lists
    list1 ++ unique_list2
  end

  # Helper to merge characters lists avoiding duplicates
  # Similar to merge_systems_lists but for characters
  defp merge_characters_lists(list1, list2) do
    # Extract IDs from first list to check for duplicates
    list1_ids =
      list1
      |> Enum.map(&extract_character_id/1)
      |> Enum.filter(& &1)
      |> MapSet.new()

    # Filter out duplicates from second list
    unique_list2 =
      Enum.filter(list2, fn char ->
        id = extract_character_id(char)
        id && !MapSet.member?(list1_ids, id)
      end)

    # Combine lists
    list1 ++ unique_list2
  end

  # Helper function to extract character ID from different formats
  defp extract_character_id(char) do
    cond do
      is_map(char) && Map.has_key?(char, :character_id) -> to_string(char.character_id)
      is_map(char) && Map.has_key?(char, "character_id") -> to_string(char["character_id"])
      is_integer(char) || is_binary(char) -> to_string(char)
      true -> nil
    end
  end
end
