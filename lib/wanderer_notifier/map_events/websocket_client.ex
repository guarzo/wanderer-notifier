defmodule WandererNotifier.MapEvents.WebSocketClient do
  @moduledoc """
  Proof of concept WebSocket client for connecting to map events service.

  This client connects to the external events service to receive real-time
  system and character updates for tracked maps.
  """

  use WebSockex
  require Logger

  @reconnect_delay 5_000
  @heartbeat_interval 30_000

  @type option ::
          {:map_identifier, String.t()}
          | {:api_key, String.t()}
          | {:url, String.t()}
          | {:name, atom()}
  @type options :: [option()]

  @spec start_link(Keyword.t()) :: {:ok, pid()} | {:error, any()}
  def start_link(opts) do
    start_link_impl(
      Keyword.get(opts, :map_identifier),
      Keyword.get(opts, :api_key),
      opts
    )
  end

  defp start_link_impl(nil, _, _opts), do: {:error, :missing_map_identifier}
  defp start_link_impl(_, nil, _opts), do: {:error, :missing_api_key}

  defp start_link_impl(map_identifier, api_key, opts) do
    # Optional configuration
    websocket_url =
      Keyword.get(
        opts,
        :url,
        Application.get_env(
          :wanderer_notifier,
          :websocket_map_url,
          "ws://host.docker.internal:4444"
        )
      )

    name = Keyword.get(opts, :name, __MODULE__)

    Logger.debug("[MapEvents] Starting WebSocket client",
      url: websocket_url,
      map_identifier: map_identifier
    )

    # Build the Phoenix socket URL with API key
    socket_url = build_socket_url(websocket_url, api_key)

    state = %{
      url: socket_url,
      map_identifier: map_identifier,
      api_key: api_key,
      channel_ref: nil,
      heartbeat_ref: nil,
      joined: false,
      join_ref: "1"
    }

    Logger.info("[MapEvents] Attempting WebSocket connection",
      url: socket_url,
      timeout: 10_000
    )

    WebSockex.start_link(socket_url, __MODULE__, state,
      name: name,
      extra_headers: [
        {"Origin", "http://localhost"},
        {"User-Agent", "WandererNotifier/1.0 (Elixir WebSockex)"}
      ],
      timeout: 10_000
    )
  end

  def handle_connect(_conn, state) do
    Logger.debug("[MapEvents] WebSocket connected, joining channel")

    # Start heartbeat
    heartbeat_ref = Process.send_after(self(), :heartbeat, @heartbeat_interval)

    # Join the external events channel
    send(self(), :join_channel)

    {:ok, %{state | heartbeat_ref: heartbeat_ref}}
  end

  def handle_disconnect(%{reason: reason}, state) do
    Logger.error("[MapEvents] WebSocket disconnected", reason: inspect(reason))

    # Cancel timer
    cancel_timer(state.heartbeat_ref)

    # Reconnect after delay
    Process.send_after(self(), :connect_delayed, @reconnect_delay)

    {:ok,
     %{state | channel_ref: nil, heartbeat_ref: nil, joined: false, join_ref: state.join_ref}}
  end

  def handle_frame({:text, message}, state) do
    Logger.debug(
      "[MapEvents] Received frame: #{String.slice(message, 0, 200)}#{if String.length(message) > 200, do: "...", else: ""}"
    )

    case Jason.decode(message) do
      {:ok, data} when is_list(data) ->
        # Phoenix V2 protocol uses array format
        handle_phoenix_v2_message(data, state)

      {:ok, data} ->
        # Fallback for object format (shouldn't happen with V2)
        Logger.warning("[MapEvents] Received non-array message", data: inspect(data))
        {:ok, state}

      {:error, reason} ->
        Logger.error("[MapEvents] Failed to decode WebSocket message",
          error: inspect(reason),
          message: message
        )

        {:ok, state}
    end
  end

  def handle_frame({:binary, _data}, state) do
    # We don't expect binary frames
    {:ok, state}
  end

  def handle_info(:heartbeat, state) do
    # Send Phoenix V2 heartbeat
    if state.joined do
      ref = to_string(System.system_time(:millisecond))

      # Phoenix V2 heartbeat format: [join_ref, ref, topic, event, payload]
      heartbeat_message = [
        # join_ref (nil for heartbeat)
        nil,
        # ref
        ref,
        # topic
        "phoenix",
        # event
        "heartbeat",
        # payload
        %{}
      ]

      case Jason.encode(heartbeat_message) do
        {:ok, json} ->
          {:reply, {:text, json},
           %{state | heartbeat_ref: Process.send_after(self(), :heartbeat, @heartbeat_interval)}}

        {:error, _} ->
          {:ok,
           %{state | heartbeat_ref: Process.send_after(self(), :heartbeat, @heartbeat_interval)}}
      end
    else
      {:ok, %{state | heartbeat_ref: Process.send_after(self(), :heartbeat, @heartbeat_interval)}}
    end
  end

  def handle_info(:connect_delayed, state) do
    # Attempt to reconnect
    send(self(), :join_channel)
    {:ok, state}
  end

  def handle_info(:join_channel, state) do
    ref = to_string(System.system_time(:millisecond))
    topic = "external_events:map:#{state.map_identifier}"

    # Phoenix V2 protocol uses array format: [join_ref, ref, topic, event, payload]
    join_message = [
      # join_ref
      state.join_ref,
      # ref
      ref,
      # topic
      topic,
      # event
      "phx_join",
      # payload
      %{}
    ]

    Logger.debug("[MapEvents] Joining channel", topic: topic)

    case Jason.encode(join_message) do
      {:ok, json} ->
        {:reply, {:text, json}, %{state | channel_ref: ref}}

      {:error, reason} ->
        Logger.error("[MapEvents] Failed to encode join message", error: inspect(reason))
        Process.send_after(self(), :join_channel, 5_000)
        {:ok, state}
    end
  end

  # Handle Phoenix V2 messages in array format: [join_ref, ref, topic, event, payload]
  defp handle_phoenix_v2_message(
         [_join_ref, ref, _topic, "phx_reply", %{"status" => "ok"}],
         state
       )
       when ref == state.channel_ref do
    Logger.info("[MapEvents] ✅ Connected to map events channel for #{state.map_identifier}")
    {:ok, %{state | joined: true}}
  end

  defp handle_phoenix_v2_message(
         [_join_ref, _ref, _topic, "phx_reply", %{"status" => "error", "response" => response}],
         state
       ) do
    Logger.error("[MapEvents] Failed to join channel",
      error: inspect(response),
      channel: "external_events:map:#{state.map_identifier}",
      api_key_present: state.api_key != nil
    )

    Process.send_after(self(), :join_channel, 5_000)
    {:ok, state}
  end

  # Handle Phoenix error events
  defp handle_phoenix_v2_message([_join_ref, _ref, topic, "phx_error", payload], state) do
    Logger.error("[MapEvents] Channel error received",
      topic: topic,
      payload: inspect(payload),
      details: "This usually means authentication failed or the channel closed unexpectedly"
    )

    # Don't try to handle as external event, just reconnect
    {:ok, state}
  end

  defp handle_phoenix_v2_message(
         [_join_ref, _ref, _topic, "phx_reply", %{"status" => "error"} = payload],
         state
       ) do
    Logger.error("[MapEvents] Failed to join channel",
      payload: inspect(payload),
      channel: "external_events:map:#{state.map_identifier}"
    )

    Process.send_after(self(), :join_channel, 5_000)
    {:ok, state}
  end

  # Handle external events
  defp handle_phoenix_v2_message([_join_ref, _ref, _topic, "external_event", payload], state) do
    handle_external_event(payload, state)
    {:ok, state}
  end

  # Handle heartbeat reply
  defp handle_phoenix_v2_message([_join_ref, _ref, "phoenix", "phx_reply", _payload], state) do
    # Heartbeat acknowledged
    {:ok, state}
  end

  defp handle_phoenix_v2_message([_join_ref, _ref, topic, event, payload] = _msg, state) do
    Logger.debug("[MapEvents] Received event - Topic: #{topic}, Event: #{event}")

    # Check if this might be a map event with a different event name
    # Exclude Phoenix internal events (phx_reply, phx_error, phx_close, phx_leave)
    if String.contains?(topic, "external_events:map") && !String.starts_with?(event, "phx_") do
      Logger.debug("[MapEvents.Raw] Processing map event", event: event)

      # Try to handle it as an external event
      handle_external_event(payload, state)
    end

    {:ok, state}
  end

  defp handle_phoenix_v2_message(msg, state) do
    Logger.debug("[MapEvents] Unexpected Phoenix V2 message format", message: inspect(msg))
    {:ok, state}
  end

  # Handle different event types
  defp handle_external_event(event, _state) do
    # Log the raw event data for analysis
    Logger.debug("[MapEvents.Raw] Received event", type: event["type"])

    # Delegate to the handlers module
    WandererNotifier.MapEvents.Handlers.handle_event(event)
  end

  # Utilities
  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp build_socket_url(base_url, api_key) do
    url =
      base_url
      |> String.replace("http://", "ws://")
      |> String.replace("https://", "wss://")
      |> ensure_socket_path()

    # Add API key and version as query parameters
    separator = if String.contains?(url, "?"), do: "&", else: "?"
    final_url = "#{url}#{separator}api_key=#{api_key}&vsn=2.0.0"

    Logger.info("[MapEvents] Built socket URL - Base: #{base_url}, Final: #{final_url}")

    final_url
  end

  defp ensure_socket_path(url) do
    path =
      cond do
        String.ends_with?(url, "/socket/websocket") ->
          url

        String.ends_with?(url, "/socket") ->
          "#{url}/websocket"

        true ->
          url = String.trim_trailing(url, "/")
          "#{url}/socket/websocket"
      end

    Logger.info("[MapEvents] Socket path: #{path}")
    path
  end
end
