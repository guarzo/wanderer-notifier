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

  defp map_registry do
    Application.get_env(
      :wanderer_notifier,
      :map_registry_module,
      WandererNotifier.Map.MapRegistry
    )
  end

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
      &add_character_to_cache(&1, map_slug),
      &handle_character_added(&1, map_slug)
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
      &remove_character_from_cache(&1, map_slug),
      &handle_character_removed(&1, map_slug)
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
      &update_character_in_cache(&1, map_slug),
      &maybe_notify_character_updated/1
    )
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Character-Specific Data Extraction
  # ══════════════════════════════════════════════════════════════════════════════

  defp extract_character_from_event(payload) do
    # Try different field names for EVE ID, normalize to string (or nil)
    raw_eve_id =
      Map.get(payload, "character_eve_id") ||
        Map.get(payload, "eve_id") ||
        Map.get(payload, "character_id")

    eve_id = normalize_eve_id(raw_eve_id)

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

  defp normalize_eve_id(nil), do: nil
  defp normalize_eve_id(""), do: nil
  defp normalize_eve_id(id) when is_integer(id), do: Integer.to_string(id)
  defp normalize_eve_id(id) when is_binary(id), do: id
  defp normalize_eve_id(_other), do: nil

  defp validate_character(%{"eve_id" => eve_id, "name" => name} = character, _payload)
       when eve_id != nil and name != nil do
    {:ok, character}
  end

  defp validate_character(%{"name" => name, "id" => id} = character, _payload)
       when name != nil and id != nil do
    Logger.debug("Character update without eve_id, will try to find in cache",
      name: name,
      id: id,
      category: :api
    )

    {:ok, character}
  end

  defp validate_character(character, payload) do
    Logger.error("Missing required fields in character event",
      eve_id: character["eve_id"],
      name: character["name"],
      payload_keys: Map.keys(payload),
      category: :api
    )

    {:error, :missing_required_fields}
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Cache Operations (delegated to GenericEventHandler)
  # ══════════════════════════════════════════════════════════════════════════════

  defp add_character_to_cache(character, map_slug) do
    GenericEventHandler.add_to_cache_list(:character, character, map_slug: map_slug)
  end

  defp remove_character_from_cache(character, map_slug) do
    GenericEventHandler.remove_from_cache_list(:character, character, map_slug: map_slug)
  end

  defp update_character_in_cache(character, map_slug) do
    match_fn = build_character_match_fn(character)
    GenericEventHandler.update_in_cache_list(:character, character, match_fn, map_slug: map_slug)
  end

  defp build_character_match_fn(%{"eve_id" => eve_id}) when is_integer(eve_id) do
    fn cached -> cached["eve_id"] == eve_id end
  end

  defp build_character_match_fn(%{"eve_id" => eve_id}) when is_binary(eve_id) and eve_id != "" do
    fn cached -> cached["eve_id"] == eve_id end
  end

  defp build_character_match_fn(%{"name" => name, "id" => id})
       when is_binary(name) and name != "" and id != nil do
    fn cached ->
      cached["name"] == name or cached["id"] == id
    end
  end

  defp build_character_match_fn(%{"name" => name}) when is_binary(name) and name != "" do
    fn cached -> cached["name"] == name end
  end

  defp build_character_match_fn(%{"id" => id}) when id != nil do
    fn cached -> cached["id"] == id end
  end

  defp build_character_match_fn(_character) do
    # All identifiers are nil - no match possible
    fn _cached -> false end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Notification Logic
  # ══════════════════════════════════════════════════════════════════════════════

  defp handle_character_added(character, map_slug) do
    # Update reverse index for killmail fan-out
    eve_id = character["eve_id"]
    if is_binary(eve_id) and eve_id != "", do: map_registry().index_character(map_slug, eve_id)

    case should_notify_character?(character) do
      {:ok, true} ->
        send_character_added_notification(character)
        {:ok, :sent}

      {:ok, false} ->
        {:ok, :skipped}
    end
  end

  defp handle_character_removed(character, map_slug) do
    # Update reverse index for killmail fan-out
    eve_id = character["eve_id"]
    if is_binary(eve_id) and eve_id != "", do: map_registry().deindex_character(map_slug, eve_id)

    Logger.debug("Character removed from tracking",
      character_name: character["name"],
      eve_id: character["eve_id"],
      category: :api
    )

    {:ok, :skipped}
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
    {:ok, :skipped}
  end

  defp should_notify_character?(character) do
    character_id = character["eve_id"]
    GenericEventHandler.should_notify?(:character, character_id, character)
  end

  defp send_character_added_notification(character) do
    map_character = Character.from_api_data(character)
    WandererNotifier.DiscordNotifier.send_character_async(map_character)
    {:ok, :sent}
  end
end
