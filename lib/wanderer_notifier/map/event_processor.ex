defmodule WandererNotifier.Map.EventProcessor do
  @moduledoc """
  Processes incoming SSE events from the Wanderer map API.

  This module acts as the central dispatcher for all map events,
  routing them to appropriate handlers based on event type.

  ## Event Categories

  Events are organized into logical categories for better maintainability:

  - **System Events**: Changes to wormhole systems (add/remove/update)
  - **Connection Events**: Wormhole connection changes (future)
  - **Signature Events**: Cosmic signature updates (future)
  - **ACL Events**: Access control list changes for character tracking
  - **Special Events**: Meta events like connection status

  The event processor uses a two-stage routing approach:
  1. Categorize the event based on its type
  2. Delegate to the appropriate category handler
  """

  require Logger

  @doc """
  Processes a single event from the SSE stream.

  ## Parameters
  - `event` - The parsed event data as a map
  - `map_slug` - The map identifier for logging context

  ## Returns
  - `:ok` on successful processing
  - `{:error, reason}` on failure
  """
  @spec process_event(map(), String.t()) :: :ok | {:error, term()}
  def process_event(event, map_slug) when is_map(event) do
    event_type = Map.get(event, "type")

    Logger.debug("Processing SSE event",
      map_slug: map_slug,
      event_type: event_type,
      event_id: Map.get(event, "id")
    )

    case route_event(event_type, event, map_slug) do
      :ok ->
        Logger.debug("Event processed successfully",
          map_slug: map_slug,
          event_type: event_type
        )

        :ok

      {:error, reason} = error ->
        Logger.error("Event processing failed",
          map_slug: map_slug,
          event_type: event_type,
          error: inspect(reason)
        )

        error

      :ignored ->
        Logger.debug("Event ignored",
          map_slug: map_slug,
          event_type: event_type
        )

        :ok
    end
  end

  def process_event(event, map_slug) do
    Logger.error("Invalid event format",
      map_slug: map_slug,
      event: inspect(event)
    )

    {:error, :invalid_event_format}
  end

  # Routes an event to the appropriate handler based on event type.
  #
  # ## Event Categories
  # - System Events: add_system, deleted_system, system_metadata_changed
  # - Connection Events: connection_added, connection_removed, connection_updated
  # - Signature Events: signature_added, signature_removed, signatures_updated
  # - ACL Events: acl_member_added, acl_member_removed, acl_member_updated
  # - Special Events: connected, map_kill
  @spec route_event(String.t(), map(), String.t()) :: :ok | {:error, term()} | :ignored
  defp route_event(event_type, event, map_slug) do
    case categorize_event(event_type) do
      :system -> handle_system_event(event_type, event, map_slug)
      :connection -> handle_connection_event(event_type, event, map_slug)
      :signature -> handle_signature_event(event_type, event, map_slug)
      :character -> handle_character_event(event_type, event, map_slug)
      :acl -> handle_acl_event(event_type, event, map_slug)
      :rally -> handle_rally_event(event_type, event, map_slug)
      :special -> handle_special_event(event_type, event, map_slug)
      :unknown -> handle_unknown_event(event_type, event, map_slug)
    end
  end

  # Categorizes events based on their type prefix or pattern
  @spec categorize_event(String.t()) :: atom()
  defp categorize_event(event_type) do
    cond do
      event_type in ["add_system", "deleted_system", "system_metadata_changed"] ->
        :system

      event_type in ["connection_added", "connection_removed", "connection_updated"] ->
        :connection

      event_type in ["signature_added", "signature_removed", "signatures_updated"] ->
        :signature

      event_type in ["character_added", "character_removed", "character_updated"] ->
        :character

      event_type in ["acl_member_added", "acl_member_removed", "acl_member_updated"] ->
        :acl

      event_type in ["rally_point_added", "rally_point_removed"] ->
        :rally

      event_type in ["connected", "map_kill"] ->
        :special

      true ->
        :unknown
    end
  end

  # System event handlers
  @spec handle_system_event(String.t(), map(), String.t()) :: :ok | {:error, term()}
  defp handle_system_event("add_system", event, map_slug) do
    WandererNotifier.Domains.Tracking.Handlers.SystemHandler.handle_entity_added(event, map_slug)
  end

  defp handle_system_event("deleted_system", event, map_slug) do
    WandererNotifier.Domains.Tracking.Handlers.SystemHandler.handle_entity_removed(
      event,
      map_slug
    )
  end

  defp handle_system_event("system_metadata_changed", event, map_slug) do
    WandererNotifier.Domains.Tracking.Handlers.SystemHandler.handle_entity_updated(
      event,
      map_slug
    )
  end

  # Connection event handlers (not implemented yet)
  @spec handle_connection_event(String.t(), map(), String.t()) :: :ignored
  defp handle_connection_event(_event_type, _event, _map_slug) do
    # Future implementation for wormhole connection events
    :ignored
  end

  # Signature event handlers (not implemented yet)
  @spec handle_signature_event(String.t(), map(), String.t()) :: :ignored
  defp handle_signature_event(_event_type, _event, _map_slug) do
    # Future implementation for signature scanning events
    :ignored
  end

  # Character event handlers
  @spec handle_character_event(String.t(), map(), String.t()) :: :ok | {:error, term()}
  defp handle_character_event("character_added", event, map_slug) do
    WandererNotifier.Domains.Tracking.Handlers.CharacterHandler.handle_entity_added(
      event,
      map_slug
    )
  end

  defp handle_character_event("character_removed", event, map_slug) do
    WandererNotifier.Domains.Tracking.Handlers.CharacterHandler.handle_entity_removed(
      event,
      map_slug
    )
  end

  defp handle_character_event("character_updated", event, map_slug) do
    # Add defensive logging to see what's in the event
    payload = Map.get(event, "payload", %{})

    if map_size(payload) == 0 do
      Logger.warning("Character updated event has empty payload",
        map_slug: map_slug,
        event_id: Map.get(event, "id"),
        event_keys: Map.keys(event)
      )
    end

    WandererNotifier.Domains.Tracking.Handlers.CharacterHandler.handle_entity_updated(
      event,
      map_slug
    )
  end

  # ACL event handlers (legacy - keeping for compatibility)
  @spec handle_acl_event(String.t(), map(), String.t()) :: :ignored
  defp handle_acl_event(_event_type, _event, _map_slug) do
    # ACL events are now handled by character events
    :ignored
  end

  # Rally point event handlers
  @spec handle_rally_event(String.t(), map(), String.t()) :: :ok | {:error, term()} | :ignored
  defp handle_rally_event("rally_point_added", event, _map_slug) do
    payload = Map.get(event, "payload", %{})

    Logger.debug("Rally point created",
      system: Map.get(payload, "system_name"),
      character: Map.get(payload, "character_name"),
      category: :rally
    )

    rally_point = %{
      id: Map.get(payload, "rally_point_id"),
      system_id: Map.get(payload, "solar_system_id"),
      system_name: Map.get(payload, "system_name"),
      character_name: Map.get(payload, "character_name"),
      character_eve_id: Map.get(payload, "character_eve_id"),
      message: Map.get(payload, "message"),
      created_at: Map.get(payload, "created_at")
    }

    # Trigger notification through the notification context
    case WandererNotifier.Contexts.NotificationContext.send_rally_point_notification(rally_point) do
      {:ok, _} -> {:ok, :sent}
      {:error, :notifications_disabled} -> :skip
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_rally_event("rally_point_removed", _event, _map_slug) do
    # Not handling removed events for now
    :ignored
  end

  # Special event handlers
  @spec handle_special_event(String.t(), map(), String.t()) :: :ok | :ignored
  defp handle_special_event("connected", event, map_slug) do
    Logger.debug("SSE connection established",
      map_slug: map_slug,
      event_id: Map.get(event, "id"),
      server_time: Map.get(event, "server_time")
    )

    :ok
  end

  defp handle_special_event("map_kill", _event, _map_slug) do
    # Kill events are handled by the existing killmail pipeline
    :ignored
  end

  # Unknown event handler
  @spec handle_unknown_event(String.t(), map(), String.t()) :: :ignored
  defp handle_unknown_event(unknown_type, _event, map_slug) do
    Logger.warning("Unknown event type received",
      map_slug: map_slug,
      event_type: unknown_type
    )

    :ignored
  end

  @doc """
  Validates that an event has all required fields.

  ## Required Fields
  - `id` - Unique event identifier (ULID)
  - `type` - Event type string
  - `map_id` - Map UUID
  - `timestamp` - ISO 8601 timestamp
  - `payload` - Event-specific data
  """
  @spec validate_event(map()) :: :ok | {:error, term()}
  def validate_event(event) when is_map(event) do
    required_fields = ["id", "type", "map_id", "timestamp", "payload"]

    case find_missing_fields(event, required_fields) do
      [] ->
        validate_event_payload(event)

      missing_fields ->
        {:error, {:missing_fields, missing_fields}}
    end
  end

  def validate_event(_), do: {:error, :invalid_event_structure}

  defp find_missing_fields(event, required_fields) do
    Enum.filter(required_fields, fn field ->
      not Map.has_key?(event, field) or is_nil(Map.get(event, field))
    end)
  end

  defp validate_event_payload(event) do
    payload = Map.get(event, "payload")

    if is_map(payload) and map_size(payload) > 0 do
      :ok
    else
      {:error, :invalid_payload}
    end
  end

  @doc """
  Extracts event metadata for logging and debugging.
  """
  @spec extract_event_metadata(map()) :: map()
  def extract_event_metadata(event) when is_map(event) do
    %{
      id: Map.get(event, "id"),
      type: Map.get(event, "type"),
      map_id: Map.get(event, "map_id"),
      timestamp: Map.get(event, "timestamp"),
      payload_keys: event |> Map.get("payload", %{}) |> Map.keys()
    }
  end

  def extract_event_metadata(_), do: %{error: "invalid_event_format"}
end
