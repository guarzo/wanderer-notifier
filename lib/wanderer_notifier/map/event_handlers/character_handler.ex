defmodule WandererNotifier.Map.EventHandlers.CharacterHandler do
  @moduledoc """
  Handles character events from the Wanderer map API.

  This module processes real-time character events to maintain character tracking state.
  """

  require Logger
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Map.MapCharacter
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier

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
  @spec handle_character_added(map(), String.t()) :: :ok | {:error, term()}
  def handle_character_added(event, map_slug) do
    payload = Map.get(event, "payload", %{})

    # Log the full payload for debugging and monitoring
    AppLogger.api_info("Character added payload received",
      map_slug: map_slug,
      payload: inspect(payload),
      payload_keys: Map.keys(payload)
    )

    AppLogger.api_info("Processing character added event",
      map_slug: map_slug,
      character_name: Map.get(payload, "name"),
      eve_id: Map.get(payload, "character_eve_id")
    )

    with {:ok, character} <- extract_character_from_event(payload),
         :ok <- add_character_to_cache(character),
         :ok <- maybe_notify_character_added(character) do
      AppLogger.api_info("Character added to tracking",
        map_slug: map_slug,
        character_name: character["name"],
        eve_id: character["eve_id"]
      )

      :ok
    else
      {:error, reason} = error ->
        AppLogger.api_error("Failed to process character added event",
          map_slug: map_slug,
          error: inspect(reason)
        )

        error
    end
  end

  @doc """
  Handles character removed events.
  """
  @spec handle_character_removed(map(), String.t()) :: :ok | {:error, term()}
  def handle_character_removed(event, map_slug) do
    payload = Map.get(event, "payload", %{})

    # Log the full payload for debugging and monitoring
    AppLogger.api_info("Character removed payload received",
      map_slug: map_slug,
      payload: inspect(payload),
      payload_keys: Map.keys(payload)
    )

    AppLogger.api_info("Processing character removed event",
      map_slug: map_slug,
      character_name: Map.get(payload, "name"),
      eve_id: Map.get(payload, "character_eve_id")
    )

    with {:ok, character} <- extract_character_from_event(payload),
         :ok <- remove_character_from_cache(character),
         :ok <- maybe_notify_character_removed(character) do
      AppLogger.api_info("Character removed from tracking",
        map_slug: map_slug,
        character_name: character["name"],
        eve_id: character["eve_id"]
      )

      :ok
    else
      {:error, reason} = error ->
        AppLogger.api_error("Failed to process character removed event",
          map_slug: map_slug,
          error: inspect(reason)
        )

        error
    end
  end

  @doc """
  Handles character updated events.
  """
  @spec handle_character_updated(map(), String.t()) :: :ok | {:error, term()}
  def handle_character_updated(event, map_slug) do
    payload = Map.get(event, "payload", %{})

    # Log the full payload to debug the structure
    AppLogger.api_info("Character updated payload received",
      map_slug: map_slug,
      payload: inspect(payload),
      payload_keys: Map.keys(payload)
    )

    AppLogger.api_info("Processing character updated event",
      map_slug: map_slug,
      character_name: Map.get(payload, "name"),
      eve_id: Map.get(payload, "character_eve_id"),
      online: Map.get(payload, "online"),
      ship_type_id: Map.get(payload, "ship_type_id")
    )

    with {:ok, character} <- extract_character_from_event(payload),
         :ok <- update_character_in_cache(character),
         :ok <- maybe_notify_character_updated(character) do
      AppLogger.api_info("Character updated in tracking",
        map_slug: map_slug,
        character_name: character["name"],
        eve_id: character["eve_id"]
      )

      :ok
    else
      {:error, reason} = error ->
        AppLogger.api_error("Failed to process character updated event",
          map_slug: map_slug,
          error: inspect(reason)
        )

        error
    end
  end

  # Private helper functions

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

  defp add_character_to_cache(character) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

    case Cachex.get(cache_name, CacheKeys.character_list()) do
      {:ok, cached_characters} when is_list(cached_characters) ->
        add_to_existing_cache(cache_name, cached_characters, character)

      {:ok, nil} ->
        # No cached characters, create new list
        Cachex.put(cache_name, CacheKeys.character_list(), [character])
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_to_existing_cache(cache_name, cached_characters, character) do
    eve_id = character["eve_id"]

    if Enum.any?(cached_characters, fn c -> c["eve_id"] == eve_id end) do
      :ok
    else
      # Add new character
      updated_characters = [character | cached_characters]
      Cachex.put(cache_name, CacheKeys.character_list(), updated_characters)
      :ok
    end
  end

  defp remove_character_from_cache(character) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

    case Cachex.get(cache_name, CacheKeys.character_list()) do
      {:ok, cached_characters} when is_list(cached_characters) ->
        # Remove character from the list
        eve_id = character["eve_id"]
        updated_characters = Enum.reject(cached_characters, fn c -> c["eve_id"] == eve_id end)
        Cachex.put(cache_name, CacheKeys.character_list(), updated_characters)
        :ok

      {:ok, nil} ->
        # No cached characters, nothing to remove
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_character_in_cache(character) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

    case Cachex.get(cache_name, CacheKeys.character_list()) do
      {:ok, cached_characters} when is_list(cached_characters) ->
        update_cached_characters(cache_name, cached_characters, character)

      {:ok, nil} ->
        # No cached characters, only create if we have eve_id
        if character["eve_id"] do
          Cachex.put(cache_name, CacheKeys.character_list(), [character])
        end

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_cached_characters(cache_name, cached_characters, character) do
    {matched, updated_characters} =
      if character["eve_id"] do
        update_by_eve_id(cached_characters, character)
      else
        update_by_name_or_id(cached_characters, character)
      end

    final_characters = add_if_new(updated_characters, character, matched)
    Cachex.put(cache_name, CacheKeys.character_list(), final_characters)
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

    updated =
      Enum.map(cached_characters, fn c ->
        if matches_name_or_id?(c, name, id) do
          # Preserve the eve_id from cache and merge the update
          Map.merge(c, character) |> Map.put("eve_id", c["eve_id"])
        else
          c
        end
      end)

    matched = Enum.any?(cached_characters, &matches_name_or_id?(&1, name, id))
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
    case MapCharacter.new_safe(character) do
      {:ok, map_character} ->
        DiscordNotifier.send_new_tracked_character_notification(map_character)
        :ok

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
