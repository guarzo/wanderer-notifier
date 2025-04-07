defmodule WandererNotifier.Data.Repository do
  @moduledoc """
  Repository for data operations. Acts as the single source of truth for data access,
  coordinating between cache and external data sources.
  """

  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.AppLogger, as: Logger
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  require Ash.Query

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

  @doc """
  Counts the number of kills for a specific character.
  Returns 0 if no kills are found.
  """
  @spec count_kills_for_character(integer()) :: integer()
  def count_kills_for_character(character_id) do
    # Use Ash.Query to count kills for this character
    query =
      Killmail
      |> Ash.Query.new()
      |> Ash.Query.filter(
        fragment(
          "(esi_data->>'character_id' = ? OR esi_data->'attackers'->>'character_id' = ?)",
          ^to_string(character_id),
          ^to_string(character_id)
        )
      )
      |> Ash.Query.aggregate(:count, :id, :total)

    case Api.read(query) do
      {:ok, [%{total: count}]} -> count
      _ -> 0
    end
  rescue
    _ -> 0
  end

  @doc """
  Gets the timestamp of the last kill for a specific character.
  Returns nil if no kills are found.
  """
  @spec get_last_kill_timestamp_for_character(integer()) :: DateTime.t() | nil
  def get_last_kill_timestamp_for_character(character_id) do
    # Use Ash.Query to get the most recent kill for this character
    query =
      Killmail
      |> Ash.Query.new()
      |> Ash.Query.filter(
        fragment(
          "(esi_data->>'character_id' = ? OR esi_data->'attackers'->>'character_id' = ?)",
          ^to_string(character_id),
          ^to_string(character_id)
        )
      )
      |> Ash.Query.sort(updated_at: :desc)
      |> Ash.Query.limit(1)

    case Api.read(query) do
      {:ok, [kill]} -> kill.updated_at
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Caches character information for later retrieval.
  Uses the cache helper to store the character data.

  ## Parameters
    - character_data: Map containing character data with "character_id" and "name" fields

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  @spec cache_character_info(map()) :: :ok | {:error, term()}
  def cache_character_info(character_data) do
    CacheHelpers.cache_character_info(character_data)
  end
end
