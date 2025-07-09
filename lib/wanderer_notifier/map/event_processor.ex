defmodule WandererNotifier.Map.EventProcessor do
  @moduledoc """
  Processes incoming SSE events from the Wanderer map API.

  This module acts as the central dispatcher for all map events,
  routing them to appropriate handlers based on event type.
  """

  require Logger
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Map.EventHandlers.SystemHandler
  alias WandererNotifier.Map.EventHandlers.AclHandler

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

    AppLogger.api_info("Processing SSE event",
      map_slug: map_slug,
      event_type: event_type,
      event_id: Map.get(event, "id")
    )

    case route_event(event_type, event, map_slug) do
      :ok ->
        AppLogger.api_info("Event processed successfully",
          map_slug: map_slug,
          event_type: event_type
        )

        :ok

      {:error, reason} = error ->
        AppLogger.api_error("Event processing failed",
          map_slug: map_slug,
          event_type: event_type,
          error: inspect(reason)
        )

        error

      :ignored ->
        AppLogger.api_info("Event ignored",
          map_slug: map_slug,
          event_type: event_type
        )

        :ok
    end
  end

  def process_event(event, map_slug) do
    AppLogger.api_error("Invalid event format",
      map_slug: map_slug,
      event: inspect(event)
    )

    {:error, :invalid_event_format}
  end

  # Routes an event to the appropriate handler based on event type.
  # 
  # ## System Events
  # - `add_system` - New system added to map
  # - `deleted_system` - System removed from map
  # - `system_metadata_changed` - System properties updated
  # 
  # ## Connection Events (future)
  # - `connection_added` - New wormhole connection
  # - `connection_removed` - Connection closed
  # - `connection_updated` - Connection properties changed
  # 
  # ## Signature Events (future)
  # - `signature_added` - New signature detected
  # - `signature_removed` - Signature cleared
  # - `signatures_updated` - Signature properties changed
  # 
  # ## Kill Events (future)
  # - `map_kill` - Kill occurred in mapped system
  # 
  # ## ACL Events
  # - `acl_member_added` - Character added to map ACL
  # - `acl_member_removed` - Character removed from map ACL
  # - `acl_member_updated` - Character role updated in map ACL
  @spec route_event(String.t(), map(), String.t()) :: :ok | {:error, term()} | :ignored
  defp route_event("add_system", event, map_slug) do
    SystemHandler.handle_system_added(event, map_slug)
  end

  defp route_event("deleted_system", event, map_slug) do
    SystemHandler.handle_system_deleted(event, map_slug)
  end

  defp route_event("system_metadata_changed", event, map_slug) do
    SystemHandler.handle_system_metadata_changed(event, map_slug)
  end

  # Connection events (not implemented yet)
  defp route_event("connection_added", _event, _map_slug) do
    :ignored
  end

  defp route_event("connection_removed", _event, _map_slug) do
    :ignored
  end

  defp route_event("connection_updated", _event, _map_slug) do
    :ignored
  end

  # Signature events (not implemented yet)
  defp route_event("signature_added", _event, _map_slug) do
    :ignored
  end

  defp route_event("signature_removed", _event, _map_slug) do
    :ignored
  end

  defp route_event("signatures_updated", _event, _map_slug) do
    :ignored
  end

  # Kill events (not implemented yet - handled by existing killmail pipeline)
  defp route_event("map_kill", _event, _map_slug) do
    :ignored
  end

  # ACL events for character tracking
  defp route_event("acl_member_added", event, map_slug) do
    AclHandler.handle_acl_member_added(event, map_slug)
  end

  defp route_event("acl_member_removed", event, map_slug) do
    AclHandler.handle_acl_member_removed(event, map_slug)
  end

  defp route_event("acl_member_updated", event, map_slug) do
    AclHandler.handle_acl_member_updated(event, map_slug)
  end

  # Connection events (special system events)
  defp route_event("connected", event, map_slug) do
    AppLogger.api_info("SSE connection established",
      map_slug: map_slug,
      event_id: Map.get(event, "id"),
      server_time: Map.get(event, "server_time")
    )

    :ok
  end

  # Unknown event types
  defp route_event(unknown_type, _event, map_slug) do
    AppLogger.api_warn("Unknown event type received",
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
  - `ts` - ISO 8601 timestamp
  - `payload` - Event-specific data
  """
  @spec validate_event(map()) :: :ok | {:error, term()}
  def validate_event(event) when is_map(event) do
    required_fields = ["id", "type", "map_id", "ts", "payload"]

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
      timestamp: Map.get(event, "ts"),
      payload_keys: event |> Map.get("payload", %{}) |> Map.keys()
    }
  end

  def extract_event_metadata(_), do: %{error: "invalid_event_format"}
end
