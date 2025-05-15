defmodule WandererNotifier.Notifications.Determiner.Character do
  @moduledoc """
  Determines whether character notifications should be sent.
  Handles all character-related notification decision logic.
  """

  require Logger
  alias WandererNotifier.Config
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Notifications.Helpers.Deduplication
  alias WandererNotifier.Map.MapCharacter

  @doc """
  Determines if a notification should be sent for a character.

  ## Parameters
    - character_id: The ID of the character to check
    - character_data: The character data to check

  ## Returns
    - true if a notification should be sent
    - false otherwise
  """
  def should_notify?(character_id, _character_data) do
    if Config.character_notifications_enabled?() do
      case Deduplication.check(:character, character_id) do
        {:ok, :new} -> true
        {:ok, :duplicate} -> false
        {:error, _reason} -> true
      end
    else
      false
    end
  end

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
    case MapCharacter.is_tracked?(character_id_str) do
      {:ok, tracked} -> tracked
      _ -> false
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

    cached_data =
      case CacheRepo.get(cache_key) do
        {:ok, value} -> value
        _ -> nil
      end

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
end
