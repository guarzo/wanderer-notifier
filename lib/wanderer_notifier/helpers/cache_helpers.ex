defmodule WandererNotifier.Helpers.CacheHelpers do
  @moduledoc """
  Helper functions for working with the cache.
  """
  require Logger
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

  @doc """
  Gets all tracked systems from the cache.
  Handles both the old format (list of system IDs) and the new format (list of system maps).
  """
  def get_tracked_systems do
    case CacheRepo.get("map:systems") do
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
              nil -> nil
              system -> system
            end
          end)
          |> Enum.filter(& &1)
        end

      _ ->
        []
    end
  end

  @doc """
  Gets all tracked characters from the cache.
  """
  def get_tracked_characters do
    characters = CacheRepo.get("map:characters")
    require Logger
    Logger.debug("CacheHelpers.get_tracked_characters: Retrieved #{inspect(length(characters || []))} characters from cache")
    Logger.debug("CacheHelpers.get_tracked_characters: Raw data: #{inspect(characters)}")
    characters || []
  end
end
