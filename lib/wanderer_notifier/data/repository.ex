defmodule WandererNotifier.Data.Repository do
  @moduledoc """
  Repository for data operations. Acts as the single source of truth for data access,
  coordinating between cache and external data sources.
  """

  alias WandererNotifier.Helpers.CacheHelpers

  @doc """
  Gets tracked characters from the data store.
  Returns a list of character data maps.
  """
  @spec get_tracked_characters() :: [map()]
  def get_tracked_characters do
    CacheHelpers.get_tracked_characters()
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
