defmodule WandererNotifier.Schedulers.CharacterUpdateScheduler do
  @moduledoc """
  Scheduler for updating character data from the Map API.

  This scheduler periodically fetches and updates character data,
  detecting and notifying about new characters.
  """

  require WandererNotifier.Schedulers.Factory
  require Logger

  alias WandererNotifier.Core.Config.Timings
  alias WandererNotifier.Api.Map.CharactersClient
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

  # Get the default interval from Timings module
  @default_interval Timings.character_update_scheduler_interval()

  # Create an interval-based scheduler with specific configuration
  WandererNotifier.Schedulers.Factory.create_scheduler(
    type: :interval,
    default_interval: @default_interval,
    enabled_check: &WandererNotifier.Core.Config.map_tools_enabled?/0
  )

  @impl true
  def execute(state) do
    Logger.info("Executing character data update")

    # Get cached characters for comparison to detect new characters
    cached_characters = CacheRepo.get("map:characters")

    # Use the new CharactersClient module
    result = CharactersClient.update_tracked_characters(cached_characters)

    case result do
      {:ok, characters} ->
        Logger.info("Successfully updated #{length(characters)} characters")
        {:ok, %{character_count: length(characters)}, state}

      {:error, reason} ->
        Logger.error("Failed to update characters: #{inspect(reason)}")
        {:error, reason, state}
    end
  end
end
