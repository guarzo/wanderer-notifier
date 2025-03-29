defmodule WandererNotifier.Schedulers.CharacterUpdateScheduler do
  @moduledoc """
  Scheduler for updating character data from the Map API.

  This scheduler periodically fetches and updates character data,
  detecting and notifying about new characters.
  """

  require WandererNotifier.Schedulers.Factory
  require Logger

  alias WandererNotifier.Api.Map.CharactersClient
  alias WandererNotifier.Config.{Features, Timing}
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Schedulers.Factory

  # Get the default interval from Timing module
  @default_interval Timing.get_character_update_scheduler_interval()

  # Create an interval-based scheduler with specific configuration
  Factory.create_scheduler(__MODULE__,
    type: :interval,
    default_interval: @default_interval,
    enabled_check: &Features.map_tools_enabled?/0
  )

  @impl true
  def execute(state) do
    AppLogger.scheduler_info("Executing character data update")

    # Get cached characters for comparison to detect new characters
    cached_characters = CacheRepo.get("map:characters")

    # Use the new CharactersClient module
    result = CharactersClient.update_tracked_characters(cached_characters)

    case result do
      {:ok, characters} ->
        AppLogger.scheduler_info("Successfully updated #{length(characters)} characters")
        {:ok, %{character_count: length(characters)}, state}

      {:error, :feature_disabled} ->
        # Log as info instead of error when feature is disabled
        AppLogger.scheduler_info("Character tracking feature is disabled, skipping update")
        {:ok, %{status: "skipped", reason: "feature_disabled"}, state}

      {:error, reason} ->
        AppLogger.scheduler_error("Failed to update characters: #{inspect(reason)}")
        {:error, reason, state}
    end
  end
end
