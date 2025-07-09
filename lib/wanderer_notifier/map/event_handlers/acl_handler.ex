defmodule WandererNotifier.Map.EventHandlers.AclHandler do
  @moduledoc """
  Handles ACL (Access Control List) events from the Wanderer map API.

  This module processes real-time ACL events to maintain character tracking state,
  working in conjunction with the initial character loading at startup.
  """

  require Logger
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Map.MapCharacter
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier

  @doc """
  Handles ACL member added events.

  When a new member (character) is added to the map's ACL, this function:
  1. Extracts character information from the event
  2. Adds the character to the tracked characters cache
  3. Sends notifications if applicable

  ## Event payload structure:
  ```
  %{
    "acl_id" => "660e8400-e29b-41d4-a716-446655440001",
    "member_id" => "770e8400-e29b-41d4-a716-446655440002",
    "member_name" => "Pilot Name",
    "member_type" => "character",
    "eve_id" => "95123456",
    "role" => "viewer"
  }
  ```
  """
  @spec handle_acl_member_added(map(), String.t()) :: :ok | {:error, term()}
  def handle_acl_member_added(event, map_slug) do
    payload = Map.get(event, "payload", %{})
    log_acl_event("Processing ACL member added event", payload, map_slug)

    with {:ok, character} <- extract_character_from_acl_event(payload),
         :ok <- add_character_to_cache(character),
         :ok <- maybe_notify_character_added(character) do
      log_character_added(character, map_slug)
      :ok
    else
      {:error, :extract_failed} = error ->
        log_extraction_error(payload, map_slug, error)
        error

      {:error, reason} = error ->
        log_cache_error(reason, map_slug)
        error
    end
  end

  defp log_acl_event(message, payload, map_slug) do
    AppLogger.api_info(message,
      map_slug: map_slug,
      member_name: Map.get(payload, "member_name"),
      member_type: Map.get(payload, "member_type"),
      role: Map.get(payload, "role")
    )
  end

  defp maybe_notify_character_added(character) do
    if should_notify_character_added(character) do
      send_character_added_notification(character)
    end

    :ok
  end

  defp log_character_added(character, map_slug) do
    AppLogger.api_info("Character added to tracking via ACL",
      map_slug: map_slug,
      character_name: character["name"],
      eve_id: character["eve_id"]
    )
  end

  defp log_extraction_error(payload, map_slug, error) do
    AppLogger.api_error("Failed to extract character from ACL event",
      map_slug: map_slug,
      payload: inspect(payload),
      error: inspect(error)
    )
  end

  defp log_cache_error(reason, map_slug) do
    AppLogger.api_error("Failed to add character to cache",
      map_slug: map_slug,
      error: inspect(reason)
    )
  end

  @doc """
  Handles ACL member removed events.

  When a member is removed from the map's ACL, this function:
  1. Extracts character information from the event
  2. Removes the character from the tracked characters cache
  3. Sends notifications if applicable
  """
  @spec handle_acl_member_removed(map(), String.t()) :: :ok | {:error, term()}
  def handle_acl_member_removed(event, map_slug) do
    payload = Map.get(event, "payload", %{})
    log_acl_removal_event(payload, map_slug)

    with {:ok, character} <- extract_character_from_acl_event(payload),
         :ok <- remove_character_from_cache(character),
         :ok <- maybe_notify_character_removed(character) do
      log_character_removed(character, map_slug)
      :ok
    else
      {:error, :extract_failed} = error ->
        log_extraction_error(payload, map_slug, error)
        error

      {:error, reason} = error ->
        log_removal_error(reason, map_slug)
        error
    end
  end

  defp log_acl_removal_event(payload, map_slug) do
    AppLogger.api_info("Processing ACL member removed event",
      map_slug: map_slug,
      member_name: Map.get(payload, "member_name"),
      member_type: Map.get(payload, "member_type")
    )
  end

  defp maybe_notify_character_removed(character) do
    if should_notify_character_removed(character) do
      send_character_removed_notification(character)
    end

    :ok
  end

  defp log_character_removed(character, map_slug) do
    AppLogger.api_info("Character removed from tracking via ACL",
      map_slug: map_slug,
      character_name: character["name"],
      eve_id: character["eve_id"]
    )
  end

  defp log_removal_error(reason, map_slug) do
    AppLogger.api_error("Failed to remove character from cache",
      map_slug: map_slug,
      error: inspect(reason)
    )
  end

  @doc """
  Handles ACL member updated events.

  When a member's role or properties are updated in the map's ACL, this function:
  1. Extracts character information from the event
  2. Updates the character in the tracked characters cache
  3. Sends notifications if applicable
  """
  @spec handle_acl_member_updated(map(), String.t()) :: :ok | {:error, term()}
  def handle_acl_member_updated(event, map_slug) do
    payload = Map.get(event, "payload", %{})
    log_acl_event("Processing ACL member updated event", payload, map_slug)

    with {:ok, character} <- extract_character_from_acl_event(payload),
         :ok <- update_character_in_cache(character),
         :ok <- maybe_notify_character_updated(character) do
      log_character_updated(character, map_slug)
      :ok
    else
      {:error, :extract_failed} = error ->
        log_extraction_error(payload, map_slug, error)
        error

      {:error, reason} = error ->
        log_update_error(reason, map_slug)
        error
    end
  end

  defp maybe_notify_character_updated(character) do
    if should_notify_character_updated(character) do
      send_character_updated_notification(character)
    end

    :ok
  end

  defp log_character_updated(character, map_slug) do
    AppLogger.api_info("Character updated in tracking via ACL",
      map_slug: map_slug,
      character_name: character["name"],
      eve_id: character["eve_id"]
    )
  end

  defp log_update_error(reason, map_slug) do
    AppLogger.api_error("Failed to update character in cache",
      map_slug: map_slug,
      error: inspect(reason)
    )
  end

  # Private helper functions

  defp extract_character_from_acl_event(payload) do
    # Only process character-type ACL members
    case Map.get(payload, "member_type") do
      "character" ->
        # Extract character data from ACL event payload
        character = %{
          "eve_id" => Map.get(payload, "eve_id"),
          "name" => Map.get(payload, "member_name"),
          "acl_id" => Map.get(payload, "acl_id"),
          "member_id" => Map.get(payload, "member_id"),
          "role" => Map.get(payload, "role")
        }

        # Validate required fields
        if character["eve_id"] && character["name"] do
          {:ok, character}
        else
          {:error, :missing_required_fields}
        end

      other_type ->
        AppLogger.api_info("Ignoring non-character ACL member",
          member_type: other_type
        )

        {:error, :not_character_member}
    end
  end

  defp add_character_to_cache(character) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

    cache_name
    |> Cachex.get(CacheKeys.character_list())
    |> handle_add_to_cache(cache_name, character)
  end

  defp handle_add_to_cache({:ok, cached_characters}, cache_name, character)
       when is_list(cached_characters) do
    eve_id = character["eve_id"]

    if character_exists?(cached_characters, eve_id) do
      :ok
    else
      add_new_character(cache_name, cached_characters, character)
    end
  end

  defp handle_add_to_cache({:ok, nil}, cache_name, character) do
    Cachex.put(cache_name, CacheKeys.character_list(), [character])
    :ok
  end

  defp handle_add_to_cache({:error, reason}, _cache_name, _character) do
    {:error, reason}
  end

  defp character_exists?(characters, eve_id) do
    Enum.any?(characters, fn c -> c["eve_id"] == eve_id end)
  end

  defp add_new_character(cache_name, cached_characters, character) do
    updated_characters = [character | cached_characters]
    Cachex.put(cache_name, CacheKeys.character_list(), updated_characters)
    :ok
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

    cache_name
    |> Cachex.get(CacheKeys.character_list())
    |> handle_update_in_cache(cache_name, character)
  end

  defp handle_update_in_cache({:ok, cached_characters}, cache_name, character)
       when is_list(cached_characters) do
    eve_id = character["eve_id"]
    updated_characters = update_character_list(cached_characters, character, eve_id)
    Cachex.put(cache_name, CacheKeys.character_list(), updated_characters)
    :ok
  end

  defp handle_update_in_cache({:ok, nil}, cache_name, character) do
    Cachex.put(cache_name, CacheKeys.character_list(), [character])
    :ok
  end

  defp handle_update_in_cache({:error, reason}, _cache_name, _character) do
    {:error, reason}
  end

  defp update_character_list(characters, new_character, eve_id) do
    Enum.map(characters, fn c ->
      if c["eve_id"] == eve_id do
        Map.merge(c, new_character)
      else
        c
      end
    end)
  end

  defp should_notify_character_added(character) do
    # Use the existing character notification logic
    character_id = character["eve_id"]
    CharacterDeterminer.should_notify?(character_id, character)
  end

  defp should_notify_character_removed(character) do
    # For now, use the same logic as added
    # In the future, this could have different logic for removals
    character_id = character["eve_id"]
    CharacterDeterminer.should_notify?(character_id, character)
  end

  defp should_notify_character_updated(character) do
    # For now, use the same logic as added
    # In the future, this could have different logic for updates
    character_id = character["eve_id"]
    CharacterDeterminer.should_notify?(character_id, character)
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
    # This could be implemented in the future
    AppLogger.api_info("Character removed from tracking",
      character_name: character["name"],
      eve_id: character["eve_id"]
    )

    :ok
  end

  defp send_character_updated_notification(character) do
    # For now, we don't have a specific "character updated" notification
    # This could be implemented in the future
    AppLogger.api_info("Character updated in tracking",
      character_name: character["name"],
      eve_id: character["eve_id"],
      role: character["role"]
    )

    :ok
  end
end
