defmodule WandererNotifier.Notifications.Determiner.Character do
  @moduledoc """
  Determines whether character notifications should be sent.
  Handles all character-related notification decision logic.
  """

  require Logger
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Helpers.DeduplicationHelper
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Determines if a notification should be sent for a character.

  ## Parameters
    - character_id: The ID of the character to check
    - character_data: The character data to check

  ## Returns
    - true if a notification should be sent
    - false otherwise
  """
  def should_notify?(character_id, character_data) when is_map(character_data) do
    with true <- Features.character_notifications_enabled?(),
         true <- tracked_character?(character_id),
         true <- character_changed?(character_id, character_data) do
      check_deduplication_and_decide(character_id)
    else
      false -> false
      _ -> false
    end
  end

  def should_notify?(_, _), do: false

  @doc """
  Checks if a character is being tracked.

  ## Parameters
    - character_id: The ID of the character to check

  ## Returns
    - true if the character is tracked
    - false otherwise
  """
  def tracked_character?(character_id) when is_integer(character_id) do
    character_id_str = Integer.to_string(character_id)
    tracked_character?(character_id_str)
  end

  def tracked_character?(character_id_str) when is_binary(character_id_str) do
    AppLogger.processor_debug("[Determiner] Checking if character #{character_id_str} is tracked")

    # First check if the character is in the exclude_list
    character_exclude_list = Application.get_env(:wanderer_notifier, :character_exclude_list, [])

    if character_id_str in character_exclude_list do
      AppLogger.processor_debug(
        "[Determiner] Character #{character_id_str} is in exclude_list, skipping"
      )

      false
    else
      # Check if we have a direct tracking entry for the character
      cache_key = CacheKeys.tracked_character(character_id_str)
      cache_value = CacheRepo.get(cache_key)

      # Log the cache check
      AppLogger.processor_debug("[Determiner] Tracked character cache check",
        character_id: character_id_str,
        value: inspect(cache_value)
      )

      # Get the character details from cache too
      character_cache_key = CacheKeys.character(character_id_str)
      character_in_cache = CacheRepo.get(character_cache_key)

      AppLogger.processor_debug("[Determiner] Character cache check",
        character_id: character_id_str,
        character: inspect(character_in_cache)
      )

      # Return tracking status with detailed logging
      tracked = cache_value != nil

      AppLogger.processor_debug("[Determiner] Character tracking check result",
        character_id: character_id_str,
        tracked: tracked,
        character_cache_key: character_cache_key,
        character_in_cache: character_in_cache != nil
      )

      tracked
    end
  end

  def tracked_character?(_), do: false

  @doc """
  Checks if a character's data has changed from what's in cache.

  ## Parameters
    - character_id: The ID of the character to check
    - character_data: The new character data to compare against cache

  ## Returns
    - true if the character data has changed
    - false otherwise
  """
  def character_changed?(character_id, character_data) when is_map(character_data) do
    # Get cached character data
    cache_key = CacheKeys.character(character_id)
    cached_data = CacheRepo.get(cache_key)

    # Compare relevant fields
    case cached_data do
      nil ->
        # No cached data, consider it changed
        true

      cached when is_map(cached) ->
        # Compare relevant fields
        changed?(cached, character_data, [
          "character_name",
          "corporation_id",
          "corporation_name",
          "alliance_id",
          "alliance_name",
          "security_status",
          "ship_type_id",
          "ship_name",
          "location_id",
          "location_name"
        ])

      _ ->
        # Invalid cache data, consider it changed
        true
    end
  end

  def character_changed?(_, _), do: false

  # Check if any of the specified fields have changed
  defp changed?(old_data, new_data, fields) do
    Enum.any?(fields, fn field ->
      old_value = Map.get(old_data, field)
      new_value = Map.get(new_data, field)
      old_value != new_value
    end)
  end

  # Apply deduplication check and decide whether to send notification
  defp check_deduplication_and_decide(character_id) do
    case DeduplicationHelper.duplicate?(:character, character_id) do
      {:ok, :new} ->
        # Not a duplicate, allow sending
        true

      {:ok, :duplicate} ->
        # Duplicate, skip notification
        false

      {:error, reason} ->
        # Error during deduplication check - default to allowing
        AppLogger.processor_warn(
          "Deduplication check failed, allowing notification by default",
          %{
            character_id: character_id,
            error: inspect(reason)
          }
        )

        true
    end
  end
end
