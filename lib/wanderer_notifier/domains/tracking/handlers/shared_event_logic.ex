defmodule WandererNotifier.Domains.Tracking.Handlers.SharedEventLogic do
  @moduledoc """
  Shared event processing logic for tracking handlers.

  This module contains common patterns used by both character and system event handlers,
  reducing code duplication while allowing for entity-specific customization.
  """

  require Logger
  alias WandererNotifier.Shared.Utils.EntityUtils

  @doc """
  Generic event handler that processes entity events with customizable steps.

  This function provides a common pattern for handling entity events:
  1. Extract payload from event
  2. Log the event for monitoring
  3. Extract/process entity data from payload
  4. Update cache with the entity
  5. Optionally send notifications

  ## Parameters
  - `event` - The full event map
  - `map_slug` - Map identifier for logging
  - `event_type` - Type of event for logging (e.g., :character_added, :system_removed)
  - `extract_fn` - Function to extract/process entity data from payload
  - `cache_fn` - Function to update cache with the entity
  - `notify_fn` - Function to handle notifications (optional)

  ## Returns
  - `:ok` if successful
  - `{:error, reason}` if any step fails
  """
  @spec handle_entity_event(
          event :: map(),
          map_slug :: String.t(),
          event_type :: atom(),
          extract_fn :: (map() -> {:ok, term()} | {:error, term()}),
          cache_fn :: (term() -> :ok | {:error, term()}),
          notify_fn :: (term() -> :ok | {:error, term()})
        ) :: :ok | {:error, term()}
  def handle_entity_event(event, map_slug, event_type, extract_fn, cache_fn, notify_fn) do
    payload = Map.get(event, "payload", %{})

    # Log payload information with size limiting to prevent log flooding
    Logger.debug("#{event_type} payload received",
      map_slug: map_slug,
      event_type: event_type,
      payload: truncate_payload(payload),
      payload_keys: Map.keys(payload),
      payload_size: map_size(payload),
      category: :api
    )

    Logger.debug("Processing #{event_type} event",
      map_slug: map_slug,
      event_type: event_type,
      entity_name: extract_entity_name(payload),
      entity_id: extract_entity_id(payload),
      category: :api
    )

    with {:ok, entity} <- extract_fn.(payload),
         :ok <- cache_fn.(entity),
         :ok <- notify_fn.(entity) do
      Logger.debug("#{event_type} processed successfully",
        map_slug: map_slug,
        event_type: event_type,
        entity_name: extract_entity_name_from_result(entity),
        entity_id: extract_entity_id_from_result(entity),
        category: :api
      )

      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to process #{event_type} event",
          map_slug: map_slug,
          event_type: event_type,
          error: inspect(reason),
          category: :api
        )

        error
    end
  end

  @doc """
  Handles extraction of the entity name from the payload for logging.

  This function attempts to extract a human-readable name from different
  payload structures to improve log readability.
  """
  @spec extract_entity_name(map()) :: String.t() | nil
  def extract_entity_name(payload) do
    Map.get(payload, "name") ||
      Map.get(payload, "character_name") ||
      Map.get(payload, "system_name")
  end

  @doc """
  Handles extraction of the entity ID from the payload for logging.

  This function attempts to extract an identifier from different
  payload structures to improve log traceability.
  """
  @spec extract_entity_id(map()) :: String.t() | integer() | nil
  def extract_entity_id(payload) do
    # Maintain original extraction logic for backward compatibility
    Map.get(payload, "id") ||
      Map.get(payload, "character_eve_id") ||
      Map.get(payload, "eve_id") ||
      Map.get(payload, "character_id") ||
      Map.get(payload, "solar_system_id") ||
      Map.get(payload, "system_id")
  end

  @doc """
  Extracts entity name from processed entity data for logging.
  """
  @spec extract_entity_name_from_result(term()) :: String.t() | nil
  def extract_entity_name_from_result(entity) do
    case entity do
      %{name: name} -> name
      %{"name" => name} -> name
      _ -> nil
    end
  end

  @doc """
  Extracts entity ID from processed entity data for logging.
  """
  @spec extract_entity_id_from_result(term()) :: String.t() | integer() | nil
  def extract_entity_id_from_result(entity) do
    # Use EntityUtils for consistent extraction logic, but preserve original data types
    case entity do
      %{eve_id: id} ->
        id

      %{"eve_id" => id} ->
        id

      _ ->
        EntityUtils.extract_character_id(entity) ||
          EntityUtils.extract_system_id(entity) ||
          EntityUtils.get_value(entity, "id")
    end
  end

  @doc """
  Creates a no-op notification function for cases where notifications aren't needed.

  This is useful for events like entity removal or updates that don't require notifications.
  """
  @spec no_op_notification() :: (term() -> :ok)
  def no_op_notification do
    fn _entity -> :ok end
  end

  @doc """
  Creates a logging-only notification function for cases where we want to log but not notify.

  This is useful for events that should be logged but don't trigger Discord notifications.
  """
  @spec log_only_notification(String.t()) :: (term() -> :ok)
  def log_only_notification(action_description) do
    fn entity ->
      entity_name = extract_entity_name_from_result(entity)
      entity_id = extract_entity_id_from_result(entity)

      Logger.debug(action_description,
        entity_name: entity_name,
        entity_id: entity_id,
        category: :api
      )

      :ok
    end
  end

  @doc """
  Wraps a function to handle errors gracefully and convert them to the expected format.

  This is useful for cache operations that might fail but shouldn't crash the event processing.
  """
  @spec safe_operation((term() -> term())) :: (term() -> :ok | {:error, term()})
  def safe_operation(operation_fn) do
    fn entity ->
      try do
        case operation_fn.(entity) do
          :ok -> :ok
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
          other -> {:error, {:unexpected_result, other}}
        end
      rescue
        error -> {:error, {:operation_failed, error}}
      end
    end
  end

  @doc """
  Creates a conditional notification function that only notifies if a condition is met.
  """
  @spec conditional_notification(
          condition_fn :: (term() -> boolean()),
          notification_fn :: (term() -> :ok | {:error, term()})
        ) :: (term() -> :ok | {:error, term()})
  def conditional_notification(condition_fn, notification_fn) do
    fn entity ->
      if condition_fn.(entity) do
        notification_fn.(entity)
      else
        :ok
      end
    end
  end

  # Helper function to truncate large payloads for logging
  @max_payload_log_length 500
  defp truncate_payload(payload) when is_map(payload) do
    inspected = inspect(payload)

    if String.length(inspected) > @max_payload_log_length do
      String.slice(inspected, 0, @max_payload_log_length) <> "... [truncated]"
    else
      inspected
    end
  end

  defp truncate_payload(payload), do: inspect(payload)
end
