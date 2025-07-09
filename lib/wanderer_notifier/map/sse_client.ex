defmodule WandererNotifier.Map.SSEClient do
  @moduledoc """
  Server-Sent Events client for Wanderer map real-time events.

  Connects to the Wanderer SSE endpoint and processes map events in real-time,
  replacing the polling-based system update mechanism.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Map.EventProcessor

  @type state :: %{
          map_slug: String.t(),
          api_token: String.t(),
          connection: pid() | nil,
          last_event_id: String.t() | nil,
          reconnect_attempts: integer(),
          reconnect_timer: reference() | nil,
          events_filter: list(String.t()),
          status: :disconnected | :connecting | :connected | :reconnecting
        }

  @default_events [
    "add_system",
    "deleted_system",
    "system_metadata_changed",
    "acl_member_added",
    "acl_member_removed",
    "acl_member_updated"
  ]
  @initial_reconnect_delay 1000
  @max_reconnect_delay 30_000
  @reconnect_backoff_factor 2

  # Client API

  @doc """
  Starts the SSE client for a specific map.

  ## Options
  - `:map_id` - The map ID for the SSE endpoint
  - `:map_slug` - The map slug for logging and identification
  - `:api_token` - Authentication token for the map API
  - `:events` - List of event types to subscribe to (optional)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    map_slug = Keyword.fetch!(opts, :map_slug)
    name = via_tuple(map_slug)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the current connection status.
  """
  @spec get_status(String.t()) :: :disconnected | :connecting | :connected | :reconnecting
  def get_status(map_slug) do
    map_slug
    |> via_tuple()
    |> GenServer.call(:get_status)
  end

  @doc """
  Manually triggers a reconnection attempt.
  """
  @spec reconnect(String.t()) :: :ok
  def reconnect(map_slug) do
    map_slug
    |> via_tuple()
    |> GenServer.cast(:reconnect)
  end

  @doc """
  Stops the SSE client.
  """
  @spec stop(String.t()) :: :ok
  def stop(map_slug) do
    map_slug
    |> via_tuple()
    |> GenServer.stop()
  end

  # GenServer Implementation

  @impl GenServer
  def init(opts) do
    map_slug = Keyword.fetch!(opts, :map_slug)
    api_token = Keyword.fetch!(opts, :api_token)
    # If events is not provided, use nil (no filtering) instead of default events
    events = Keyword.get(opts, :events, nil)

    AppLogger.api_info("SSE client init",
      map_slug: map_slug,
      opts: inspect(opts),
      events: inspect(events),
      default_events: inspect(@default_events)
    )

    state = %{
      map_slug: map_slug,
      api_token: api_token,
      connection: nil,
      last_event_id: nil,
      reconnect_attempts: 0,
      reconnect_timer: nil,
      events_filter: events,
      status: :disconnected
    }

    AppLogger.api_info("SSE client initialized",
      map_slug: map_slug,
      events_filter: inspect(state.events_filter)
    )

    # Start connection immediately
    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    case do_connect(state) do
      {:ok, connection} ->
        new_state = %{state | connection: connection, status: :connected, reconnect_attempts: 0}
        AppLogger.api_info("SSE connected", map_slug: state.map_slug)
        {:noreply, new_state}

      {:error, reason} ->
        AppLogger.api_error("SSE connection failed",
          map_slug: state.map_slug,
          error: inspect(reason)
        )

        new_state = schedule_reconnect(state)
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl GenServer
  def handle_cast(:reconnect, state) do
    # Cancel existing reconnect timer
    if state.reconnect_timer, do: Process.cancel_timer(state.reconnect_timer)

    # Close existing connection
    if state.connection, do: close_connection(state.connection)

    new_state = %{state | connection: nil, reconnect_timer: nil, status: :connecting}

    {:noreply, new_state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_info({:sse_event, event_data}, state) do
    case process_event(event_data, state) do
      {:ok, last_event_id} ->
        new_state = %{state | last_event_id: last_event_id}
        {:noreply, new_state}

      {:error, reason} ->
        AppLogger.api_error("Event processing failed",
          map_slug: state.map_slug,
          error: inspect(reason)
        )

        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:sse_error, reason}, state) do
    AppLogger.api_error("SSE connection error",
      map_slug: state.map_slug,
      error: inspect(reason)
    )

    # Close connection and schedule reconnect
    if state.connection, do: close_connection(state.connection)

    new_state = %{state | connection: nil}
    new_state = schedule_reconnect(new_state)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:sse_closed}, state) do
    AppLogger.api_info("SSE connection closed", map_slug: state.map_slug)

    new_state = %{state | connection: nil}
    new_state = schedule_reconnect(new_state)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:reconnect_timer, state) do
    new_state = %{state | reconnect_timer: nil, status: :reconnecting}
    {:noreply, new_state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_info(%HTTPoison.AsyncStatus{code: status_code, id: async_id}, state) do
    AppLogger.api_info("SSE connection status",
      map_slug: state.map_slug,
      status_code: status_code
    )

    if status_code == 200 do
      # Connection successful, continue streaming
      # Create the AsyncResponse struct that stream_next expects
      async_response = %HTTPoison.AsyncResponse{id: async_id}
      HTTPoison.stream_next(async_response)
      {:noreply, state}
    else
      # Connection failed
      AppLogger.api_error("SSE connection failed",
        map_slug: state.map_slug,
        status_code: status_code
      )

      new_state = schedule_reconnect(state)
      {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_info(%HTTPoison.AsyncHeaders{headers: headers, id: async_id}, state) do
    AppLogger.api_info("SSE connection headers received",
      map_slug: state.map_slug,
      headers: inspect(headers)
    )

    # Continue streaming
    async_response = %HTTPoison.AsyncResponse{id: async_id}
    HTTPoison.stream_next(async_response)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(%HTTPoison.AsyncChunk{chunk: chunk, id: async_id}, state) do
    # Log raw chunk for debugging
    AppLogger.api_info("Received SSE chunk",
      map_slug: state.map_slug,
      chunk_size: byte_size(chunk),
      chunk_preview: String.slice(chunk, 0, 200)
    )

    # Process SSE chunk
    case parse_sse_chunk(chunk) do
      {:ok, events} ->
        AppLogger.api_info("Parsed SSE chunk into events",
          map_slug: state.map_slug,
          event_count: length(events)
        )

        # Process events and return the updated state
        process_sse_events(events, state, async_id)

      {:error, reason} ->
        AppLogger.api_error("Failed to parse SSE chunk",
          map_slug: state.map_slug,
          error: inspect(reason),
          chunk: inspect(chunk)
        )

        # Continue streaming despite parse error
        async_response = %HTTPoison.AsyncResponse{id: async_id}
        HTTPoison.stream_next(async_response)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(%HTTPoison.AsyncEnd{}, state) do
    AppLogger.api_info("SSE connection ended", map_slug: state.map_slug)

    # Connection ended, schedule reconnect
    new_state = %{state | connection: nil}
    new_state = schedule_reconnect(new_state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(%HTTPoison.Error{reason: reason}, state) do
    AppLogger.api_error("SSE connection error",
      map_slug: state.map_slug,
      error: inspect(reason)
    )

    # Connection error, schedule reconnect
    new_state = %{state | connection: nil}
    new_state = schedule_reconnect(new_state)
    {:noreply, new_state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.connection, do: close_connection(state.connection)
    if state.reconnect_timer, do: Process.cancel_timer(state.reconnect_timer)
    :ok
  end

  # Private Functions

  defp via_tuple(map_slug) do
    {:via, Registry, {WandererNotifier.Registry, {:sse_client, map_slug}}}
  end

  defp do_connect(state) do
    url = build_sse_url(state)
    headers = build_headers(state)

    # Log the full URL without truncation
    AppLogger.api_info("Connecting to SSE",
      map_slug: state.map_slug,
      # Show more of the URL
      url: String.slice(url, 0..500)
    )

    case start_sse_connection(url, headers) do
      {:ok, connection} ->
        {:ok, connection}

      error ->
        {:error, error}
    end
  end

  defp build_sse_url(state) do
    # Use the map URL from configuration, fallback to wanderer_api_base_url
    base_url = Config.get(:map_url) || Config.get(:wanderer_api_base_url, "https://wanderer.ltd")

    # Remove any trailing path from map_url (like /maps/name)
    base_url =
      base_url
      |> URI.parse()
      |> Map.put(:path, nil)
      |> Map.put(:query, nil)
      |> URI.to_string()

    # Build query params with events filter
    query_params = []

    # Add events filter if available
    events_filter = state.events_filter || @default_events

    AppLogger.api_info("Building SSE URL with events filter",
      map_slug: state.map_slug,
      state_events_filter: inspect(state.events_filter),
      resolved_events_filter: inspect(events_filter),
      default_events: inspect(@default_events)
    )

    query_params =
      if events_filter && length(events_filter) > 0 do
        events_string = Enum.join(events_filter, ",")
        [{"events", events_string} | query_params]
      else
        query_params
      end

    # Add last_event_id for backfill if available
    query_params =
      if state.last_event_id do
        [{"last_event_id", state.last_event_id} | query_params]
      else
        query_params
      end

    # Build the URL - try using map_slug instead of map_id
    final_url =
      if length(query_params) > 0 do
        query_string = URI.encode_query(query_params)
        "#{base_url}/api/maps/#{state.map_slug}/events/stream?#{query_string}"
      else
        # No query parameters at all - use map slug
        "#{base_url}/api/maps/#{state.map_slug}/events/stream"
      end

    AppLogger.api_info("Final SSE URL",
      map_slug: state.map_slug,
      url: final_url,
      query_params: inspect(query_params)
    )

    final_url
  end

  defp build_headers(state) do
    [
      {"Authorization", "Bearer #{state.api_token}"},
      {"Accept", "text/event-stream"},
      {"Cache-Control", "no-cache"},
      {"Connection", "keep-alive"}
    ]
  end

  defp start_sse_connection(url, headers) do
    # Start real SSE connection using HTTPoison streaming
    options = [
      stream_to: self(),
      async: :once,
      recv_timeout: 60_000,
      timeout: 30_000,
      follow_redirect: true
    ]

    AppLogger.api_info("Starting SSE connection", url: url)

    case HTTPoison.get(url, headers, options) do
      {:ok, %HTTPoison.AsyncResponse{id: async_id}} ->
        AppLogger.api_info("SSE connection established", async_id: async_id)
        {:ok, async_id}

      {:error, %HTTPoison.Error{reason: reason}} ->
        AppLogger.api_error("SSE connection failed", reason: reason)
        {:error, {:connection_failed, reason}}
    end
  end

  defp close_connection(connection) when is_reference(connection) do
    # Handle HTTPoison async response
    try do
      async_response = %HTTPoison.AsyncResponse{id: connection}
      HTTPoison.stream_next(async_response)
    rescue
      _ -> :ok
    end
  end

  defp close_connection(_), do: :ok

  defp process_event(event_data, state) do
    with {:ok, parsed_event} <- parse_event(event_data),
         {:ok, validated_event} <- validate_event(parsed_event),
         :ok <- EventProcessor.process_event(validated_event, state.map_slug) do
      # Extract event ID for tracking
      event_id = Map.get(validated_event, "id")
      {:ok, event_id}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_event(event_data) when is_binary(event_data) do
    case Jason.decode(event_data) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, :json_decode_error}
    end
  end

  defp parse_event(event_data) when is_map(event_data) do
    {:ok, event_data}
  end

  defp parse_event(_), do: {:error, :invalid_event_data}

  defp validate_event(event) when is_map(event) do
    event_type = Map.get(event, "type")

    case event_type do
      "connected" ->
        # Connection events have different structure
        required_fields = ["id", "type", "map_id", "server_time"]
        validate_event_fields(event, required_fields)

      _ ->
        # Regular events require payload and timestamp
        required_fields = ["id", "type", "map_id", "timestamp", "payload"]
        validate_event_fields(event, required_fields)
    end
  end

  defp validate_event(_), do: {:error, :invalid_event_structure}

  defp validate_event_fields(event, required_fields) do
    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(event, field)
      end)

    if Enum.empty?(missing_fields) do
      {:ok, event}
    else
      AppLogger.api_error("Event validation failed - missing required fields",
        event: inspect(event),
        missing_fields: inspect(missing_fields),
        present_fields: inspect(Map.keys(event))
      )

      {:error, :missing_required_fields}
    end
  end

  defp schedule_reconnect(state) do
    # Calculate delay with exponential backoff
    delay =
      min(
        @initial_reconnect_delay * :math.pow(@reconnect_backoff_factor, state.reconnect_attempts),
        @max_reconnect_delay
      )

    # Add jitter to prevent thundering herd
    jitter = (delay * 0.1) |> trunc() |> :rand.uniform()
    final_delay = (delay + jitter) |> trunc()

    AppLogger.api_info("Scheduling reconnect",
      map_slug: state.map_slug,
      attempt: state.reconnect_attempts + 1,
      delay_ms: final_delay
    )

    timer = Process.send_after(self(), :reconnect_timer, final_delay)

    %{
      state
      | reconnect_timer: timer,
        reconnect_attempts: state.reconnect_attempts + 1,
        status: :disconnected
    }
  end

  defp parse_sse_chunk(chunk) do
    # Parse SSE chunk according to SSE specification
    # SSE format: "event: event_type\ndata: json_data\nid: event_id\n\n"

    try do
      events =
        chunk
        |> String.split("\n\n")
        |> Enum.filter(fn event_str -> String.trim(event_str) != "" end)
        |> Enum.map(&parse_single_sse_event/1)
        |> Enum.filter(fn
          {:ok, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {:ok, event} -> event end)

      {:ok, events}
    rescue
      error ->
        {:error, {:parse_error, error}}
    end
  end

  defp parse_single_sse_event(event_str) do
    event_str
    |> String.split("\n")
    |> parse_sse_lines()
    |> decode_event_data()
  end

  defp parse_sse_lines(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      parse_sse_line(line, acc)
    end)
  end

  defp parse_sse_line(line, acc) do
    case String.split(line, ": ", parts: 2) do
      ["data", data] -> Map.update(acc, "data", data, fn existing -> existing <> "\n" <> data end)
      ["event", event_type] -> Map.put(acc, "event", event_type)
      ["id", event_id] -> Map.put(acc, "id", event_id)
      _ -> acc
    end
  end

  defp decode_event_data(%{"data" => data_str} = event_data) do
    case Jason.decode(data_str) do
      {:ok, parsed_data} ->
        event = build_event(parsed_data, event_data)
        log_parsed_event(event)
        {:ok, event}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp decode_event_data(_), do: {:error, :no_data}

  defp build_event(parsed_data, event_data) do
    Map.merge(parsed_data, %{
      "type" => Map.get(event_data, "event", "unknown"),
      "id" => Map.get(event_data, "id")
    })
  end

  defp log_parsed_event(event) do
    AppLogger.api_info("Parsed SSE event",
      event_type: Map.get(event, "type"),
      event_id: Map.get(event, "id"),
      event_map_id: Map.get(event, "map_id")
    )
  end

  defp process_sse_events(events, state, async_id) do
    # Process multiple events from a single chunk
    last_event_id = state.last_event_id

    {new_last_event_id, processed_count} =
      events
      |> Enum.reduce({last_event_id, 0}, fn event, {last_id, count} ->
        case process_event(event, state) do
          {:ok, event_id} ->
            {event_id || last_id, count + 1}

          {:error, reason} ->
            AppLogger.api_error("Failed to process SSE event",
              map_slug: state.map_slug,
              error: inspect(reason),
              event: inspect(event)
            )

            {last_id, count}
        end
      end)

    if processed_count > 0 do
      AppLogger.api_info("Processed SSE events",
        map_slug: state.map_slug,
        count: processed_count,
        last_event_id: new_last_event_id
      )
    end

    # Continue streaming
    async_response = %HTTPoison.AsyncResponse{id: async_id}
    HTTPoison.stream_next(async_response)

    # Update state with new last_event_id
    new_state = %{state | last_event_id: new_last_event_id}
    {:noreply, new_state}
  end
end
