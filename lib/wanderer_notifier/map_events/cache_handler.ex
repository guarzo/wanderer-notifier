defmodule WandererNotifier.MapEvents.CacheHandler do
  @moduledoc """
  Handles cache updates for map events.

  This module manages updating the cache with real-time events,
  replacing the polling-based cache updates.
  """

  alias WandererNotifier.Cache
  alias WandererNotifier.Cache.Keys
  require Logger

  @doc """
  Add a new system to the cache
  """
  def add_system(system) do
    with {:ok, systems} <- get_cached_systems() do
      # Add the new system
      updated_systems = [system | systems]

      # Update cache
      cache_key = Keys.map_systems()

      case Cache.put(cache_key, updated_systems) do
        {:ok, _} ->
          # Update stats
          update_system_stats(updated_systems)

          Logger.debug("[MapEvents.Cache] Added system to cache",
            system_id: system["solar_system_id"],
            total_systems: length(updated_systems)
          )

          :ok

        {:error, reason} ->
          Logger.error("[MapEvents.Cache] Failed to add system to cache",
            system_id: system["solar_system_id"],
            error: inspect(reason)
          )

          {:error, reason}
      end
    end
  end

  @doc """
  Remove a system from the cache
  """
  def remove_system(system_id) do
    with {:ok, systems} <- get_cached_systems() do
      # Remove the system
      updated_systems =
        Enum.reject(systems, fn s ->
          s["solar_system_id"] == system_id
        end)

      # Update cache
      cache_key = Keys.map_systems()

      case Cache.put(cache_key, updated_systems) do
        {:ok, _} ->
          # Update stats
          update_system_stats(updated_systems)

          Logger.debug("[MapEvents.Cache] Removed system from cache",
            system_id: system_id,
            total_systems: length(updated_systems)
          )

          :ok

        {:error, reason} ->
          Logger.error("[MapEvents.Cache] Failed to remove system from cache",
            system_id: system_id,
            error: inspect(reason)
          )

          {:error, reason}
      end
    end
  end

  @doc """
  Update system metadata
  """
  def update_system_metadata(metadata) do
    with {:ok, systems} <- get_cached_systems() do
      # Update the specific system
      updated_systems =
        Enum.map(systems, fn system ->
          if system["solar_system_id"] == metadata["solar_system_id"] do
            Map.merge(system, metadata)
          else
            system
          end
        end)

      # Update cache
      cache_key = Keys.map_systems()

      case Cache.put(cache_key, updated_systems) do
        {:ok, _} ->
          Logger.debug("[MapEvents.Cache] Updated system metadata",
            system_id: metadata["solar_system_id"]
          )

          :ok

        {:error, reason} ->
          Logger.error("[MapEvents.Cache] Failed to update system metadata",
            system_id: metadata["solar_system_id"],
            error: inspect(reason)
          )

          {:error, reason}
      end
    end
  end

  @doc """
  Add a new character to the cache
  """
  def add_character(character) do
    with {:ok, characters} <- get_cached_characters() do
      # Add the new character
      updated_characters = [character | characters]

      # Update cache
      cache_key = Keys.character_list()

      case Cache.put(cache_key, updated_characters) do
        {:ok, _} ->
          # Update stats
          update_character_stats(updated_characters)

          Logger.debug("[MapEvents.Cache] Added character to cache",
            character_id: character["character_id"],
            total_characters: length(updated_characters)
          )

          :ok

        {:error, reason} ->
          Logger.error("[MapEvents.Cache] Failed to add character to cache",
            character_id: character["character_id"],
            error: inspect(reason)
          )

          {:error, reason}
      end
    end
  end

  @doc """
  Remove a character from the cache
  """
  def remove_character(character_id) do
    with {:ok, characters} <- get_cached_characters() do
      # Remove the character
      updated_characters =
        Enum.reject(characters, fn c ->
          c["character_id"] == character_id || c["eve_id"] == character_id
        end)

      # Update cache
      cache_key = Keys.character_list()

      case Cache.put(cache_key, updated_characters) do
        {:ok, _} ->
          # Update stats
          update_character_stats(updated_characters)

          Logger.debug("[MapEvents.Cache] Removed character from cache",
            character_id: character_id,
            total_characters: length(updated_characters)
          )

          :ok

        {:error, reason} ->
          Logger.error("[MapEvents.Cache] Failed to remove character from cache",
            character_id: character_id,
            error: inspect(reason)
          )

          {:error, reason}
      end
    end
  end

  @doc """
  Update a character in the cache
  """
  def update_character(updated_character) do
    with {:ok, characters} <- get_cached_characters() do
      # Update the specific character
      updated_characters =
        Enum.map(characters, fn character ->
          if character["character_id"] == updated_character["character_id"] ||
               character["eve_id"] == updated_character["character_id"] do
            Map.merge(character, updated_character)
          else
            character
          end
        end)

      # Update cache
      cache_key = Keys.character_list()

      case Cache.put(cache_key, updated_characters) do
        {:ok, _} ->
          Logger.debug("[MapEvents.Cache] Updated character",
            character_id: updated_character["character_id"]
          )

          :ok

        {:error, reason} ->
          Logger.error("[MapEvents.Cache] Failed to update character",
            character_id: updated_character["character_id"],
            error: inspect(reason)
          )

          {:error, reason}
      end
    end
  end

  # Private functions

  defp get_cached_systems do
    cache_key = Keys.map_systems()

    case Cache.get(cache_key) do
      {:ok, nil} -> {:ok, []}
      {:ok, systems} -> {:ok, systems}
      error -> error
    end
  end

  defp get_cached_characters do
    cache_key = Keys.character_list()

    case Cache.get(cache_key) do
      {:ok, nil} -> {:ok, []}
      {:ok, characters} -> {:ok, characters}
      error -> error
    end
  end

  defp update_system_stats(systems) do
    count = length(systems)
    WandererNotifier.Core.Stats.set_tracked_systems_count(count)
  end

  defp update_character_stats(characters) do
    count = length(characters)
    WandererNotifier.Core.Stats.set_tracked_characters_count(count)
  end
end
