defmodule WandererNotifier.Data.Repository do
  @moduledoc """
  Repository for data operations. Acts as the single source of truth for data access,
  coordinating cache operations.
  """

  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.AppLogger, as: Logger

  @doc """
  Gets tracked characters from the data store.
  Returns a list of character data maps.
  """
  @spec get_tracked_characters() :: [map()]
  def get_tracked_characters do
    characters = CacheRepo.get(CacheKeys.character_list()) || []

    Logger.processor_info("Retrieved tracked characters from cache",
      character_count: length(characters),
      sample_ids: Enum.take(Enum.map(characters, & &1["character_id"]), 3)
    )

    characters
  end

  @doc """
  Gets a cached ship name by its type ID.
  Returns nil if not found in cache.
  """
  @spec get_ship_name(integer()) :: String.t() | nil
  def get_ship_name(ship_type_id) do
    CacheHelpers.get_ship_name(ship_type_id)
  end

  @doc """
  Gets a cached character name by their ID.
  Returns nil if not found in cache.
  """
  @spec get_character_name(integer()) :: String.t() | nil
  def get_character_name(character_id) do
    CacheHelpers.get_character_name(character_id)
  end

  @doc """
  Gets cached kills for a given system ID.
  Returns an empty list if no kills are cached.
  """
  @spec get_cached_kills(integer()) :: [map()]
  def get_cached_kills(system_id) do
    CacheHelpers.get_cached_kills(system_id)
  end
end
