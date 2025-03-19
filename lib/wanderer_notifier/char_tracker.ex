defmodule WandererNotifier.CharTracker do
  @moduledoc """
  Proxy module for WandererNotifier.Api.Map.Characters.
  This module delegates calls to the underlying service implementation.
  """

  require Logger
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Config.Timings

  @doc """
  Updates the tracked characters list and notifies about new characters.
  Delegates to WandererNotifier.Api.Map.Characters.update_tracked_characters/1.
  """
  def update_tracked_characters(cached_characters \\ nil) do
    result = WandererNotifier.Api.Map.Characters.update_tracked_characters(cached_characters)

    # Add cache consistency check
    case result do
      {:ok, characters} when is_list(characters) and length(characters) > 0 ->
        # Verify the characters were properly stored in cache
        cached_characters = CacheRepo.get("map:characters")
        if cached_characters == nil || (is_list(cached_characters) && length(cached_characters) == 0) do
          Logger.warning("[CharTracker] Cache integrity check: Characters were updated but cache is empty. Forcing manual cache update.")
          CacheRepo.set("map:characters", characters, Timings.characters_cache_ttl())
        else
          Logger.debug("[CharTracker] Cache integrity check: Characters properly stored in cache (#{length(cached_characters)} found)")
        end
      _ -> :ok
    end

    result
  end

  @doc """
  Checks if the characters endpoint is available by making a test request.
  Delegates to WandererNotifier.Api.Map.Characters.check_characters_endpoint_availability/0.
  """
  def check_characters_endpoint_availability do
    WandererNotifier.Api.Map.Characters.check_characters_endpoint_availability()
  end
end
