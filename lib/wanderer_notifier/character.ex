defmodule WandererNotifier.Character do
  @moduledoc """
  Character context
  """

  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Gets all characters from the cache
  """
  def get_all_characters do
    characters = CacheRepo.get(CacheKeys.character_list()) || []

    AppLogger.processor_info("Retrieved tracked characters from cache",
      character_count: length(characters),
      sample_ids:
        Enum.take(
          Enum.map(characters, fn char ->
            Map.get(char, "character_id") || Map.get(char, :character_id)
          end),
          3
        )
    )

    characters
  end
end
