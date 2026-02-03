defmodule WandererNotifier.Domains.Tracking.Handlers.CharacterHandler do
  @moduledoc """
  Handles character events from the Wanderer map API.

  Processes real-time character events to maintain character tracking state.
  """

  require Logger
  alias WandererNotifier.Domains.Tracking.Entities.Character, as: Character
  alias WandererNotifier.Domains.Tracking.Handlers.GenericEventHandler
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
  # Character-Specific Data Extraction
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

    validate_character(character, payload)
  end

  defp validate_character(character, payload) do
    cond do
      character["eve_id"] && character["name"] ->
        {:ok, character}

      character["name"] && character["id"] ->
        Logger.debug("Character update without eve_id, will try to find in cache",
          name: character["name"],
          id: character["id"],
          category: :api
        )

        {:ok, character}

      true ->
        Logger.error("Missing required fields in character event",
          eve_id: character["eve_id"],
          name: character["name"],
          payload_keys: Map.keys(payload),
          category: :api
        )

        {:error, :missing_required_fields}
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Cache Operations (delegated to GenericEventHandler)
  # ══════════════════════════════════════════════════════════════════════════════

  defp add_character_to_cache(character) do
    GenericEventHandler.add_to_cache_list(:character, character)
  end

  defp remove_character_from_cache(character) do
    GenericEventHandler.remove_from_cache_list(:character, character)
  end

  defp update_character_in_cache(character) do
    match_fn = build_character_match_fn(character)
    GenericEventHandler.update_in_cache_list(:character, character, match_fn)
  end

  defp build_character_match_fn(character) do
    eve_id = character["eve_id"]
    name = character["name"]
    id = character["id"]

    cond do
      eve_id ->
        fn cached -> cached["eve_id"] == eve_id end

      name || id ->
        fn cached ->
          (name && cached["name"] == name) || (id && cached["id"] == id)
        end

      true ->
        # All identifiers are nil - no match possible
        fn _cached -> false end
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Notification Logic
  # ══════════════════════════════════════════════════════════════════════════════

  defp maybe_notify_character_added(character) do
    if should_notify_character?(character) do
      send_character_added_notification(character)
    end

    :ok
  end

  defp maybe_notify_character_removed(character) do
    Logger.debug("Character removed from tracking",
      character_name: character["name"],
      eve_id: character["eve_id"],
      category: :api
    )

    # No notification sent for character removal
    :ok
  end

  defp maybe_notify_character_updated(character) do
    Logger.debug("Character updated in tracking",
      character_name: character["name"],
      eve_id: character["eve_id"],
      online: character["online"],
      ship_type_id: character["ship_type_id"],
      category: :api
    )

    # No notification sent for character updates
    :ok
  end

  defp should_notify_character?(character) do
    character_id = character["eve_id"]
    GenericEventHandler.should_notify?(:character, character_id, character)
  end

  defp send_character_added_notification(character) do
    map_character = Character.from_api_data(character)
    WandererNotifier.DiscordNotifier.send_character_async(map_character)
    :ok
  end
end
