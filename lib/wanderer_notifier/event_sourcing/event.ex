defmodule WandererNotifier.EventSourcing.Event do
  @moduledoc """
  Unified event structure for all real-time sources.

  Provides a standardized way to represent events from WebSocket, SSE,
  and other real-time sources with proper validation and metadata.
  """

  @enforce_keys [:id, :type, :source, :timestamp, :data]
  defstruct [
    :id,
    :type,
    :source,
    :timestamp,
    :monotonic_timestamp,
    :data,
    :metadata,
    :version,
    :correlation_id,
    :causation_id
  ]

  @type event_source :: :websocket | :sse | :http | :internal
  @type event_type :: String.t()
  @type event_id :: String.t()

  @type t :: %__MODULE__{
          id: event_id(),
          type: event_type(),
          source: event_source(),
          timestamp: integer(),
          monotonic_timestamp: integer() | nil,
          data: map(),
          metadata: map() | nil,
          version: integer() | nil,
          correlation_id: String.t() | nil,
          causation_id: String.t() | nil
        }

  @doc """
  Creates a new event with the given parameters.

  ## Examples

      iex> WandererNotifier.EventSourcing.Event.new("killmail_received", :websocket, %{killmail_id: 123})
      %WandererNotifier.EventSourcing.Event{
        id: "...",
        type: "killmail_received",
        source: :websocket,
        data: %{killmail_id: 123},
        # ... other fields
      }
  """
  def new(type, source, data, opts \\ []) do
    now = System.system_time(:millisecond)
    monotonic_now = System.monotonic_time(:millisecond)
    id = generate_event_id(type, source, now)

    %__MODULE__{
      id: id,
      type: type,
      source: source,
      timestamp: now,
      monotonic_timestamp: monotonic_now,
      data: data,
      metadata: Keyword.get(opts, :metadata, %{}),
      version: Keyword.get(opts, :version, 1),
      correlation_id: Keyword.get(opts, :correlation_id),
      causation_id: Keyword.get(opts, :causation_id)
    }
  end

  @doc """
  Creates a killmail event from WebSocket data.
  """
  def from_websocket_killmail(killmail_data, opts \\ []) do
    new("killmail_received", :websocket, killmail_data, opts)
  end

  @doc """
  Creates a system event from SSE data.
  """
  def from_sse_system(system_data, opts \\ []) do
    new("system_updated", :sse, system_data, opts)
  end

  @doc """
  Creates a character event from SSE data.
  """
  def from_sse_character(character_data, opts \\ []) do
    new("character_updated", :sse, character_data, opts)
  end

  @doc """
  Validates an event structure.
  """
  def validate(%__MODULE__{} = event) do
    with :ok <- validate_required_fields(event),
         :ok <- validate_source(event.source),
         :ok <- validate_timestamp(event.timestamp),
         :ok <- validate_data(event.data) do
      {:ok, event}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Adds metadata to an event.
  """
  def add_metadata(%__MODULE__{} = event, key, value) do
    metadata = Map.put(event.metadata || %{}, key, value)
    %{event | metadata: metadata}
  end

  @doc """
  Sets the correlation ID for event tracing.
  """
  def with_correlation_id(%__MODULE__{} = event, correlation_id) do
    %{event | correlation_id: correlation_id}
  end

  @doc """
  Sets the causation ID for event causality tracking.
  """
  def with_causation_id(%__MODULE__{} = event, causation_id) do
    %{event | causation_id: causation_id}
  end

  @doc """
  Converts event to a serializable map.
  """
  def to_map(%__MODULE__{} = event) do
    event
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Creates an event from a map.
  """
  def from_map(map) when is_map(map) do
    event = struct(__MODULE__, map)
    validate(event)
  end

  @doc """
  Gets the age of an event in milliseconds.
  Uses monotonic time if available to handle system clock changes.
  """
  def age(%__MODULE__{monotonic_timestamp: monotonic_timestamp}) when not is_nil(monotonic_timestamp) do
    System.monotonic_time(:millisecond) - monotonic_timestamp
  end
  
  def age(%__MODULE__{timestamp: timestamp}) do
    # Fallback for events without monotonic timestamp
    System.system_time(:millisecond) - timestamp
  end

  @doc """
  Checks if an event is expired based on a TTL.
  """
  def expired?(%__MODULE__{} = event, ttl_ms) do
    age(event) > ttl_ms
  end

  # Private functions

  defp generate_event_id(type, source, timestamp) do
    # Create a unique ID combining type, source, timestamp and random component
    random_part = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "#{source}-#{type}-#{timestamp}-#{random_part}"
  end

  defp validate_required_fields(%__MODULE__{
         id: id,
         type: type,
         source: source,
         timestamp: timestamp,
         data: data
       }) do
    cond do
      is_nil(id) or id == "" -> {:error, "Event ID is required"}
      is_nil(type) or type == "" -> {:error, "Event type is required"}
      is_nil(source) -> {:error, "Event source is required"}
      is_nil(timestamp) -> {:error, "Event timestamp is required"}
      is_nil(data) -> {:error, "Event data is required"}
      true -> :ok
    end
  end

  defp validate_source(source) do
    valid_sources = [:websocket, :sse, :http, :internal]

    if source in valid_sources do
      :ok
    else
      {:error,
       "Invalid event source: #{inspect(source)}. Must be one of: #{inspect(valid_sources)}"}
    end
  end

  defp validate_timestamp(timestamp) when is_integer(timestamp) and timestamp > 0, do: :ok
  defp validate_timestamp(timestamp), do: {:error, "Invalid timestamp: #{inspect(timestamp)}"}

  defp validate_data(data) when is_map(data), do: :ok
  defp validate_data(data), do: {:error, "Event data must be a map, got: #{inspect(data)}"}
end
