defmodule WandererNotifier.MapEvents.Handlers do
  @moduledoc """
  Handles incoming map events from the WebSocket connection.

  This module processes system and character events, updating the cache
  and triggering notifications as needed.
  """

  alias WandererNotifier.MapEvents.CacheHandler
  alias WandererNotifier.MapEvents.NotificationHandler
  require Logger

  @doc """
  Route events to appropriate handlers based on type
  """
  def handle_event(%{"type" => "add_system", "payload" => payload}) do
    handle_system_added(payload)
  end

  def handle_event(%{"type" => "deleted_system", "payload" => payload}) do
    handle_system_deleted(payload)
  end

  def handle_event(%{"type" => "system_metadata_changed", "payload" => payload}) do
    handle_system_metadata_changed(payload)
  end

  def handle_event(%{"type" => "character_added", "payload" => payload}) do
    handle_character_added(payload)
  end

  def handle_event(%{"type" => "character_removed", "payload" => payload}) do
    handle_character_removed(payload)
  end

  def handle_event(%{"type" => "character_updated", "payload" => payload}) do
    handle_character_updated(payload)
  end

  def handle_event(%{"type" => "map_kill", "payload" => _payload}) do
    # Skip - already handled by killmail WebSocket
    :ok
  end

  # Catch-all for unknown event types
  def handle_event(%{"type" => unknown_type}) do
    Logger.warning("[MapEvents] Unknown event type: #{unknown_type}")
    :ok
  end

  # System event handlers

  defp handle_system_added(system) do
    Logger.debug("[MapEvents] Processing system added",
      system_id: system["solar_system_id"],
      name: system["name"]
    )

    # Send notification BEFORE updating cache
    # This ensures the deduplication service works correctly
    NotificationHandler.notify_system_added(system)

    # Update cache after notification
    CacheHandler.add_system(system)
  end

  defp handle_system_deleted(%{"solar_system_id" => system_id}) do
    Logger.debug("[MapEvents] Processing system deleted", system_id: system_id)

    # Update cache
    CacheHandler.remove_system(system_id)

    # Send notification
    NotificationHandler.notify_system_removed(system_id)
  end

  defp handle_system_metadata_changed(metadata) do
    Logger.debug("[MapEvents] Processing system metadata changed",
      system_id: metadata["solar_system_id"]
    )

    # Update cache with new metadata
    CacheHandler.update_system_metadata(metadata)
  end

  # Character event handlers

  defp handle_character_added(character) do
    Logger.debug("[MapEvents] Processing character added",
      character_id: character["character_id"],
      name: character["name"]
    )

    # Send notification BEFORE updating cache
    # This ensures the deduplication service works correctly
    NotificationHandler.notify_character_added(character)

    # Update cache after notification
    CacheHandler.add_character(character)
  end

  defp handle_character_removed(character) do
    Logger.debug("[MapEvents] Processing character removed",
      character_id: character["character_id"],
      name: character["name"]
    )

    # Update cache
    CacheHandler.remove_character(character["character_id"])

    # Send notification
    NotificationHandler.notify_character_removed(character)
  end

  defp handle_character_updated(character) do
    Logger.debug("[MapEvents] Processing character updated",
      character_id: character["character_id"],
      name: character["name"]
    )

    # Update cache
    CacheHandler.update_character(character)

    # Check if location changed and notify
    if character["location_changed"] do
      NotificationHandler.notify_character_location_changed(character)
    end
  end
end
