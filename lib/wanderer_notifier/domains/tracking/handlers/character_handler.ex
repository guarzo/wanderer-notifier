defmodule WandererNotifier.Domains.Tracking.Handlers.CharacterHandler do
  @moduledoc """
  Handles character events from the Wanderer map API using unified tracking infrastructure.

  This module processes real-time character events to maintain character tracking state
  while using the shared event handling patterns.
  """

  require Logger
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Domains.CharacterTracking.Character
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Domains.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Domains.Tracking.Handlers.SharedEventLogic

  @behaviour WandererNotifier.Domains.Tracking.Handlers.EventHandlerBehaviour

  # ══════════════════════════════════════════════════════════════════════════════
  # Event Handler Implementation
  # ══════════════════════════════════════════════════════════════════════════════

  @impl true
  @spec handle_entity_added(map(), String.t()) :: :ok | {:error, term()}
  def handle_entity_added(event, map_slug) do
    SharedEventLogic.handle_entity_event(
      event,
      map_slug,
      :character_added,
      &extract_character_from_event/1,
      &add_character_to_cache/1,
      &maybe_notify_character_added/1
    )
  end

  @impl true
  @spec handle_entity_removed(map(), String.t()) :: :ok | {:error, term()}
  def handle_entity_removed(event, map_slug) do
    SharedEventLogic.handle_entity_event(
      event,
      map_slug,
      :character_removed,
      &extract_character_from_event/1,
      &remove_character_from_cache/1,
      &maybe_notify_character_removed/1
    )
  end

  @impl true
  @spec handle_entity_updated(map(), String.t()) :: :ok | {:error, term()}
  def handle_entity_updated(event, map_slug) do
    SharedEventLogic.handle_entity_event(
      event,
      map_slug,
      :character_updated,
      &extract_character_from_event/1,
      &update_character_in_cache/1,
      &maybe_notify_character_updated/1
    )
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Character-Specific Implementation
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Handles character added events.

  Expected payload structure:
  ```
  %{
    "id" => "536ad050-51b1-4732-8dc3-90f1823e36b9",
    "character_id" => "536ad050-51b1-4732-8dc3-90f1823e36b9",
    "character_eve_id" => "2000000263",
    "name" => "Character Name",
    "corporation_id" => 1000000263,
    "alliance_id" => null,
    "ship_type_id" => 670,
    "online" => true
  }
  ```
  """
  def handle_character_added(event, map_slug) do
    handle_entity_added(event, map_slug)
  end

  def handle_character_removed(event, map_slug) do
    handle_entity_removed(event, map_slug)
  end

  def handle_character_updated(event, map_slug) do
    handle_entity_updated(event, map_slug)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Character-Specific Data Extraction and Processing
  # ══════════════════════════════════════════════════════════════════════════════

  defp extract_character_from_event(payload) do
    # Try different field names for EVE ID
    eve_id =
      Map.get(payload, "character_eve_id") ||
        Map.get(payload, "eve_id") ||
        Map.get(payload, "character_id")

    character = %{
      "id" => Map.get(payload, "id"),
      "character_id" => Map.get(payload, "character_id"),
      "eve_id" => eve_id,
      "name" => Map.get(payload, "name"),
      "corporation_id" => Map.get(payload, "corporation_id"),
      "alliance_id" => Map.get(payload, "alliance_id"),
      "ship_type_id" => Map.get(payload, "ship_type_id"),
      "online" => Map.get(payload, "online")
    }

    # For character_updated events, we might only get partial data
    # Only require name for updates (we can look up eve_id from cache if needed)
    cond do
      character["eve_id"] && character["name"] ->
        {:ok, character}

      character["name"] && character["id"] ->
        # If we have name and id but no eve_id, try to find it in cache
        AppLogger.api_info("Character update without eve_id, will try to find in cache",
          name: character["name"],
          id: character["id"]
        )

        {:ok, character}

      true ->
        AppLogger.api_error("Missing required fields in character event",
          eve_id: eve_id,
          name: character["name"],
          payload_keys: Map.keys(payload)
        )

        {:error, :missing_required_fields}
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Character-Specific Cache Operations
  # ══════════════════════════════════════════════════════════════════════════════

  defp add_character_to_cache(character) do
    case Cache.get(Cache.Keys.map_characters()) do
      {:ok, cached_characters} when is_list(cached_characters) ->
        add_to_existing_cache(cached_characters, character)

      {:error, :not_found} ->
        # No cached characters, create new list
        Cache.put(Cache.Keys.map_characters(), [character])
        :ok
    end
  end

  defp add_to_existing_cache(cached_characters, character) do
    eve_id = character["eve_id"]

    if Enum.any?(cached_characters, fn c -> c["eve_id"] == eve_id end) do
      :ok
    else
      # Add new character
      updated_characters = [character | cached_characters]
      Cache.put(Cache.Keys.map_characters(), updated_characters)
      :ok
    end
  end

  defp remove_character_from_cache(character) do
    case Cache.get(Cache.Keys.map_characters()) do
      {:ok, cached_characters} when is_list(cached_characters) ->
        # Remove character from the list
        eve_id = character["eve_id"]
        updated_characters = Enum.reject(cached_characters, fn c -> c["eve_id"] == eve_id end)
        Cache.put(Cache.Keys.map_characters(), updated_characters)
        :ok

      {:error, :not_found} ->
        # No cached characters, nothing to remove
        :ok
    end
  end

  defp update_character_in_cache(character) do
    case Cache.get(Cache.Keys.map_characters()) do
      {:ok, cached_characters} when is_list(cached_characters) ->
        update_cached_characters(cached_characters, character)

      {:error, :not_found} ->
        # No cached characters, only create if we have eve_id
        if character["eve_id"] do
          Cache.put(Cache.Keys.map_characters(), [character])
        end

        :ok
    end
  end

  defp update_cached_characters(cached_characters, character) do
    {matched, updated_characters} =
      if character["eve_id"] do
        update_by_eve_id(cached_characters, character)
      else
        update_by_name_or_id(cached_characters, character)
      end

    final_characters = add_if_new(updated_characters, character, matched)
    Cache.put(Cache.Keys.map_characters(), final_characters)
    :ok
  end

  defp update_by_eve_id(cached_characters, character) do
    eve_id = character["eve_id"]

    updated =
      Enum.map(cached_characters, fn c ->
        if c["eve_id"] == eve_id do
          Map.merge(c, character)
        else
          c
        end
      end)

    matched = Enum.any?(cached_characters, fn c -> c["eve_id"] == eve_id end)
    {matched, updated}
  end

  defp update_by_name_or_id(cached_characters, character) do
    name = character["name"]
    id = character["id"]

    # Try to find matching character to get eve_id
    matched_character = Enum.find(cached_characters, &matches_name_or_id?(&1, name, id))

    if matched_character do
      AppLogger.api_info("Found cached character for update",
        character_name: name,
        character_id: id,
        cached_eve_id: matched_character["eve_id"],
        cached_name: matched_character["name"]
      )
    else
      AppLogger.api_warn("No cached character found for update",
        character_name: name,
        character_id: id,
        total_cached: length(cached_characters),
        cached_names: Enum.map(cached_characters, & &1["name"]) |> Enum.take(5)
      )
    end

    updated =
      Enum.map(cached_characters, fn c ->
        if matches_name_or_id?(c, name, id) do
          # Preserve the eve_id from cache and merge the update
          Map.merge(c, character) |> Map.put("eve_id", c["eve_id"])
        else
          c
        end
      end)

    matched = matched_character != nil
    {matched, updated}
  end

  defp matches_name_or_id?(character, name, id) do
    (name && character["name"] == name) || (id && character["id"] == id)
  end

  defp add_if_new(characters, new_character, matched) do
    if not matched and new_character["eve_id"] do
      [new_character | characters]
    else
      characters
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Character-Specific Notification Logic
  # ══════════════════════════════════════════════════════════════════════════════

  defp maybe_notify_character_added(character) do
    if should_notify_character_added(character) do
      send_character_added_notification(character)
    end

    :ok
  end

  defp maybe_notify_character_removed(character) do
    if should_notify_character_removed(character) do
      send_character_removed_notification(character)
    end

    :ok
  end

  defp maybe_notify_character_updated(character) do
    if should_notify_character_updated(character) do
      send_character_updated_notification(character)
    end

    :ok
  end

  defp should_notify_character_added(character) do
    character_id = character["eve_id"]
    # Don't try to notify if we don't have an eve_id
    if character_id do
      CharacterDeterminer.should_notify?(character_id, character)
    else
      false
    end
  end

  defp should_notify_character_removed(character) do
    character_id = character["eve_id"]
    # Don't try to notify if we don't have an eve_id
    if character_id do
      CharacterDeterminer.should_notify?(character_id, character)
    else
      false
    end
  end

  defp should_notify_character_updated(character) do
    character_id = character["eve_id"]
    # Don't try to notify if we don't have an eve_id
    if character_id do
      CharacterDeterminer.should_notify?(character_id, character)
    else
      false
    end
  end

  defp send_character_added_notification(character) do
    # Create a MapCharacter struct for the notification
    case Character.new_safe(character) do
      {:ok, map_character} ->
        case WandererNotifier.Application.Services.NotificationService.notify_character(
               map_character
             ) do
          :ok -> :ok
          {:error, :notifications_disabled} -> :ok
          error -> error
        end

      {:error, reason} ->
        AppLogger.api_error("Failed to create MapCharacter for notification",
          character: inspect(character),
          error: inspect(reason)
        )

        :ok
    end
  end

  defp send_character_removed_notification(character) do
    # For now, we don't have a specific "character removed" notification
    AppLogger.api_info("Character removed from tracking",
      character_name: character["name"],
      eve_id: character["eve_id"]
    )

    :ok
  end

  defp send_character_updated_notification(character) do
    # For now, we don't have a specific "character updated" notification
    AppLogger.api_info("Character updated in tracking",
      character_name: character["name"],
      eve_id: character["eve_id"],
      online: character["online"],
      ship_type_id: character["ship_type_id"]
    )

    :ok
  end
end
