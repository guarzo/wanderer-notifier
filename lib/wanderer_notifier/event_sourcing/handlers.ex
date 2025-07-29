defmodule WandererNotifier.EventSourcing.Handlers do
  @moduledoc """
  Event handlers for processing different types of events in the event sourcing system.

  Provides handlers for killmail, system, character, and other event types
  with proper error handling and logging.
  """

  require Logger
  alias WandererNotifier.EventSourcing.Event

  @doc """
  Processes an event by routing it to the appropriate handler.
  """
  def handle_event(%Event{type: type} = event) do
    Logger.debug("Processing event", type: type, id: event.id, source: event.source)

    case route_event(event) do
      {:ok, result} ->
        Logger.debug("Event processed successfully",
          type: type,
          id: event.id,
          result: inspect(result)
        )

        {:ok, result}

      {:error, reason} ->
        Logger.warning("Event processing failed",
          type: type,
          id: event.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Handles killmail events from WebSocket sources.
  """
  def handle_killmail_event(%Event{type: "killmail_received", source: :websocket} = event) do
    try do
      killmail_data = event.data

      # Validate killmail data structure
      with {:ok, validated_data} <- validate_killmail_data(killmail_data),
           {:ok, enriched_data} <- enrich_killmail_data(validated_data),
           {:ok, result} <- process_killmail(enriched_data, event) do
        {:ok,
         %{type: :killmail_processed, killmail_id: validated_data[:killmail_id], result: result}}
      else
        {:error, reason} -> {:error, {:killmail_processing_failed, reason}}
      end
    rescue
      e -> {:error, {:killmail_processing_exception, Exception.message(e)}}
    end
  end

  @doc """
  Handles system events from SSE sources.
  """
  def handle_system_event(%Event{type: "system_updated", source: :sse} = event) do
    try do
      system_data = event.data

      with {:ok, validated_data} <- validate_system_data(system_data),
           {:ok, result} <- process_system_update(validated_data, event) do
        {:ok, %{type: :system_processed, system_id: validated_data[:system_id], result: result}}
      else
        {:error, reason} -> {:error, {:system_processing_failed, reason}}
      end
    rescue
      e -> {:error, {:system_processing_exception, Exception.message(e)}}
    end
  end

  @doc """
  Handles character events from SSE sources.
  """
  def handle_character_event(%Event{type: "character_updated", source: :sse} = event) do
    try do
      character_data = event.data

      with {:ok, validated_data} <- validate_character_data(character_data),
           {:ok, result} <- process_character_update(validated_data, event) do
        {:ok,
         %{
           type: :character_processed,
           character_id: validated_data[:character_id],
           result: result
         }}
      else
        {:error, reason} -> {:error, {:character_processing_failed, reason}}
      end
    rescue
      e -> {:error, {:character_processing_exception, Exception.message(e)}}
    end
  end

  @doc """
  Handles generic events.
  """
  def handle_generic_event(%Event{} = event) do
    Logger.info("Processing generic event", type: event.type, source: event.source, id: event.id)

    # For generic events, we just validate and pass through
    case validate_generic_data(event.data) do
      {:ok, data} ->
        {:ok, %{type: :generic_processed, event_type: event.type, data: data}}

      {:error, reason} ->
        {:error, {:generic_processing_failed, reason}}
    end
  end

  @doc """
  Handles batch events processing.
  """
  def handle_batch_events(events) when is_list(events) do
    results =
      events
      |> Enum.with_index()
      |> Enum.map(fn {event, index} ->
        case handle_event(event) do
          {:ok, result} -> {:ok, {index, result}}
          {:error, reason} -> {:error, {index, reason}}
        end
      end)

    # Separate successful and failed events
    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    success_count = length(successes)
    failure_count = length(failures)

    Logger.debug("Batch processing completed",
      total: length(events),
      successes: success_count,
      failures: failure_count
    )

    {:ok,
     %{
       total: length(events),
       successes: success_count,
       failures: failure_count,
       results: results
     }}
  end

  # Private functions

  defp route_event(%Event{type: "killmail_received", source: :websocket} = event) do
    handle_killmail_event(event)
  end

  defp route_event(%Event{type: "system_updated", source: :sse} = event) do
    handle_system_event(event)
  end

  defp route_event(%Event{type: "character_updated", source: :sse} = event) do
    handle_character_event(event)
  end

  defp route_event(%Event{} = event) do
    handle_generic_event(event)
  end

  defp validate_killmail_data(data) when is_map(data) do
    required_fields = [:killmail_id, :hash, :zkb]

    case check_required_fields(data, required_fields) do
      :ok -> {:ok, data}
      {:error, missing} -> {:error, "Missing required killmail fields: #{inspect(missing)}"}
    end
  end

  defp validate_system_data(data) when is_map(data) do
    required_fields = [:system_id, :event_type]

    case check_required_fields(data, required_fields) do
      :ok -> {:ok, data}
      {:error, missing} -> {:error, "Missing required system fields: #{inspect(missing)}"}
    end
  end

  defp validate_character_data(data) when is_map(data) do
    required_fields = [:character_id, :event]

    case check_required_fields(data, required_fields) do
      :ok -> {:ok, data}
      {:error, missing} -> {:error, "Missing required character fields: #{inspect(missing)}"}
    end
  end

  defp validate_generic_data(data) when is_map(data), do: {:ok, data}

  defp validate_generic_data(data),
    do: {:error, "Event data must be a map, got: #{inspect(data)}"}

  defp check_required_fields(data, required_fields) do
    missing_fields =
      required_fields
      |> Enum.reject(fn field -> Map.has_key?(data, field) end)

    case missing_fields do
      [] -> :ok
      missing -> {:error, missing}
    end
  end

  defp enrich_killmail_data(data) do
    # Add enrichment metadata
    enriched = Map.put(data, :processed_at, System.monotonic_time(:millisecond))
    enriched = Map.put(enriched, :source_enriched, true)
    {:ok, enriched}
  end

  defp process_killmail(data, event) do
    # Simulate killmail processing
    Logger.debug("Processing killmail", killmail_id: data[:killmail_id], event_id: event.id)

    # Here would be the actual killmail processing logic
    # For now, we'll just return success
    {:ok,
     %{
       killmail_id: data[:killmail_id],
       processed_at: System.monotonic_time(:millisecond),
       event_id: event.id
     }}
  end

  defp process_system_update(data, event) do
    # Simulate system update processing
    Logger.debug("Processing system update", system_id: data[:system_id], event_id: event.id)

    {:ok,
     %{
       system_id: data[:system_id],
       event_type: data[:event_type],
       processed_at: System.monotonic_time(:millisecond),
       event_id: event.id
     }}
  end

  defp process_character_update(data, event) do
    # Simulate character update processing
    Logger.debug("Processing character update",
      character_id: data[:character_id],
      event_id: event.id
    )

    {:ok,
     %{
       character_id: data[:character_id],
       event: data[:event],
       processed_at: System.monotonic_time(:millisecond),
       event_id: event.id
     }}
  end
end
