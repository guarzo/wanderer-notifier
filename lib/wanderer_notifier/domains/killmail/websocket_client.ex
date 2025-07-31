defmodule WandererNotifier.Domains.Killmail.WebSocketClient do
  @moduledoc """
  WebSocket client for connecting to the external WandererKills service.

  This module replaces the RedisQ HTTP polling approach with a real-time
  WebSocket connection that receives pre-enriched killmail data.
  """

  use WebSockex
  require Logger

  alias WandererNotifier.Contexts.ApiContext

  @initial_reconnect_delay 1_000
  @max_reconnect_delay 60_000
  @heartbeat_interval 30_000
  # 5 minutes
  @subscription_update_interval 300_000

  def start_link(opts \\ []) do
    websocket_url = WandererNotifier.Shared.Config.websocket_url()

    name = Keyword.get(opts, :name, __MODULE__)

    Logger.debug("Starting WebSocket client",
      url: websocket_url
    )

    # Build the WebSocket URL with Phoenix socket path
    socket_url = build_socket_url(websocket_url)

    Logger.debug("Attempting WebSocket connection",
      socket_url: socket_url
    )

    state = %{
      url: socket_url,
      channel_ref: nil,
      heartbeat_ref: nil,
      subscription_update_ref: nil,
      subscribed_systems: MapSet.new(),
      subscribed_characters: MapSet.new(),
      pipeline_worker: Keyword.get(opts, :pipeline_worker),
      connected_at: nil,
      reconnect_attempts: 0,
      connection_id: nil,
      join_retry_count: 0
    }

    WebSockex.start_link(socket_url, __MODULE__, state,
      name: name,
      extra_headers: [
        {"Origin", "http://localhost"},
        {"User-Agent", "WandererNotifier/1.0 (Elixir WebSockex)"}
      ]
    )
  end

  def handle_connect(_conn, state) do
    connected_at = DateTime.utc_now()

    Logger.debug(
      "WebSocket connected successfully to #{state.url}. Starting heartbeat (#{@heartbeat_interval}ms) and subscription updates (#{@subscription_update_interval}ms)."
    )

    # Register connection with monitoring system (skip if Integration not running)
    connection_id =
      "websocket_killmail_#{System.system_time(:millisecond)}_#{:rand.uniform(1_000_000)}"

    if Process.whereis(WandererNotifier.Infrastructure.ConnectionHealthService) do
      WandererNotifier.Infrastructure.ConnectionHealthService.register_websocket_connection(
        connection_id,
        %{
          url: state.url,
          pid: self()
        }
      )

      # Update connection status
      WandererNotifier.Infrastructure.ConnectionHealthService.update_connection_health(
        connection_id,
        :connected
      )
    end

    # Notify fallback handler that WebSocket is connected
    if Process.whereis(WandererNotifier.Domains.Killmail.FallbackHandler) do
      WandererNotifier.Domains.Killmail.FallbackHandler.websocket_connected()
    end

    # Update stats with connection time
    WandererNotifier.Application.Services.ApplicationService.update_health(:websocket, %{
      connection_start: System.system_time(:second),
      connected_at: connected_at,
      url: state.url
    })

    # Start heartbeat
    heartbeat_ref = Process.send_after(self(), :heartbeat, @heartbeat_interval)

    # Start subscription update timer
    subscription_update_ref =
      Process.send_after(self(), :subscription_update, @subscription_update_interval)

    # Join the killmails channel
    send(self(), :join_channel)

    new_state = %{
      state
      | heartbeat_ref: heartbeat_ref,
        subscription_update_ref: subscription_update_ref,
        connected_at: connected_at,
        connection_id: connection_id,
        reconnect_attempts: 0
    }

    {:ok, new_state}
  end

  def handle_disconnect(%{reason: reason}, state) do
    log_disconnect_reason(reason, state)

    # Cancel timers
    cancel_timer(state.heartbeat_ref)
    cancel_timer(state.subscription_update_ref)

    # Update connection status in monitoring system (skip if ConnectionHealthService not running)
    if Map.has_key?(state, :connection_id) &&
         Process.whereis(WandererNotifier.Infrastructure.ConnectionHealthService) do
      WandererNotifier.Infrastructure.ConnectionHealthService.update_connection_health(
        state.connection_id,
        :disconnected,
        %{reason: reason}
      )
    end

    # Notify fallback handler that WebSocket is down
    if Process.whereis(WandererNotifier.Domains.Killmail.FallbackHandler) do
      WandererNotifier.Domains.Killmail.FallbackHandler.websocket_down()
    end

    # Clear websocket stats on disconnect
    WandererNotifier.Application.Services.ApplicationService.update_health(:websocket, %{})

    # Calculate exponential backoff with jitter
    delay = calculate_backoff(state.reconnect_attempts)

    Logger.debug(
      "WebSocket scheduling reconnect in #{delay}ms (attempt #{state.reconnect_attempts + 1})"
    )

    # Reconnect after delay
    Process.send_after(self(), :connect_delayed, delay)

    {:ok,
     %{
       state
       | channel_ref: nil,
         heartbeat_ref: nil,
         subscription_update_ref: nil,
         connected_at: nil,
         reconnect_attempts: state.reconnect_attempts + 1
     }}
  end

  defp log_disconnect_reason({:error, {404, _headers, _body}}, state) do
    Logger.error(
      "WebSocket endpoint not found (404) at #{state.url}. Please check if the WandererKills service is running and has the correct endpoint. Subscribed to #{MapSet.size(state.subscribed_systems)} systems and #{MapSet.size(state.subscribed_characters)} characters."
    )
  end

  defp log_disconnect_reason({:error, {:closed, :econnrefused}}, state) do
    Logger.error(
      "WebSocket connection refused at #{state.url}. Please check if the WandererKills service is running. Subscribed to #{MapSet.size(state.subscribed_systems)} systems and #{MapSet.size(state.subscribed_characters)} characters."
    )
  end

  defp log_disconnect_reason({:remote, :closed}, state) do
    Logger.error(
      "WebSocket closed by remote server at #{state.url}. This may indicate an issue with the channel join message or server-side validation. Subscribed to #{MapSet.size(state.subscribed_systems)} systems and #{MapSet.size(state.subscribed_characters)} characters."
    )
  end

  defp log_disconnect_reason({:remote, code, message}, state) when is_integer(code) do
    Logger.error(
      "WebSocket closed by remote server with code #{code}. Message: #{inspect(message)}. Connected systems: #{MapSet.size(state.subscribed_systems)}, characters: #{MapSet.size(state.subscribed_characters)}. URL: #{state.url}"
    )
  end

  defp log_disconnect_reason(reason, state) do
    Logger.error(
      "WebSocket disconnected from #{state.url} with reason: #{inspect(reason)}. Subscribed to #{MapSet.size(state.subscribed_systems)} systems and #{MapSet.size(state.subscribed_characters)} characters."
    )
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp calculate_backoff(attempts) do
    base = @initial_reconnect_delay
    # Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, 60s max
    calculated = base * :math.pow(2, attempts)
    # Add 20-40% jitter to prevent thundering herd
    jittered = calculated * (0.8 + :rand.uniform() * 0.4)
    min(trunc(jittered), @max_reconnect_delay)
  end

  def handle_frame({:text, message}, state) do
    message_size = byte_size(message)
    log_frame_received(message_size)

    case Jason.decode(message) do
      {:ok, data} ->
        handle_decoded_message(data, state)

      {:error, reason} ->
        handle_decode_error(message, message_size, reason, state)
    end
  end

  def handle_frame({:binary, _data}, state) do
    # We don't expect binary frames
    {:ok, state}
  end

  defp log_frame_received(message_size) do
    # Only log detailed info for debug level, reduce memory impact
    Logger.debug("WebSocket text frame received",
      message_size: message_size
    )
  end

  defp handle_decoded_message(data, state) do
    log_decoded_message(data)
    handle_phoenix_message(data, state)
  end

  defp log_decoded_message(data) do
    Logger.debug("Decoded WebSocket message",
      event: data["event"],
      topic: data["topic"],
      payload_keys: extract_payload_keys(data["payload"])
    )
  end

  defp extract_payload_keys(payload) when is_map(payload), do: Map.keys(payload)
  defp extract_payload_keys(_), do: nil

  defp handle_decode_error(message, message_size, reason, state) do
    message_preview = truncate_message(message, message_size)

    Logger.error("Failed to decode WebSocket message",
      error: inspect(reason),
      message_size: message_size,
      message_preview: message_preview
    )

    {:ok, state}
  end

  defp truncate_message(message, message_size) when message_size > 200 do
    String.slice(message, 0, 200) <> "... (truncated)"
  end

  defp truncate_message(message, _message_size), do: message

  def handle_info(:heartbeat, state) do
    log_heartbeat_uptime(state)
    record_heartbeat_in_monitoring(state)
    send_phoenix_heartbeat(state)
  end

  def handle_info(:connect_delayed, state) do
    # Attempt to reconnect
    send(self(), :join_channel)
    {:ok, state}
  end

  def handle_info(:subscription_update, state) do
    Logger.info("Starting subscription update check")

    try do
      check_and_update_subscriptions(state)
    rescue
      error ->
        handle_subscription_error(error, state)
    end
  end

  def handle_info(:join_channel, state) do
    Logger.debug("WebSocket handling join_channel message")

    try do
      {limited_systems, limited_characters} = prepare_subscription_data()
      join_params = build_join_params(limited_systems, limited_characters)
      result = send_join_message(join_params, limited_systems, limited_characters, state)
      Logger.debug("Join channel result: #{inspect(result)}")
      result
    rescue
      error ->
        Logger.error("Error during channel join",
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )

        # Retry with exponential backoff
        retry_count = Map.get(state, :join_retry_count, 0)
        delay = calculate_backoff(retry_count)

        Logger.debug("Scheduling channel join retry in #{delay}ms (attempt #{retry_count + 1})")

        Process.send_after(self(), :join_channel, delay)
        {:ok, %{state | join_retry_count: retry_count + 1}}
    end
  end

  defp log_heartbeat_uptime(state) do
    uptime = calculate_connection_uptime(state)

    Logger.debug(
      "WebSocket heartbeat - Connection uptime: #{uptime}s (#{div(uptime, 60)}m #{rem(uptime, 60)}s)"
    )
  end

  defp calculate_connection_uptime(%{connected_at: %DateTime{} = connected_at}) do
    DateTime.diff(DateTime.utc_now(), connected_at, :second)
  end

  defp calculate_connection_uptime(_), do: 0

  defp record_heartbeat_in_monitoring(_state) do
    # Heartbeat recording removed - ConnectionHealthService doesn't need explicit heartbeats
    # Connection status is updated on connect/disconnect events only
    :ok
  end

  defp send_phoenix_heartbeat(state) do
    if state.channel_ref do
      send_heartbeat_message(state)
    else
      handle_missing_channel_ref(state)
    end
  end

  defp send_heartbeat_message(state) do
    heartbeat_message = build_heartbeat_message()

    case Jason.encode(heartbeat_message) do
      {:ok, json} ->
        {:reply, {:text, json}, schedule_next_heartbeat(state)}

      {:error, _} ->
        {:ok, schedule_next_heartbeat(state)}
    end
  end

  defp build_heartbeat_message do
    %{
      topic: "phoenix",
      event: "heartbeat",
      payload: %{},
      ref: "heartbeat_#{System.system_time(:millisecond)}"
    }
  end

  defp handle_missing_channel_ref(state) do
    Logger.warning("Heartbeat attempted but no channel_ref set")
    {:ok, schedule_next_heartbeat(state)}
  end

  defp schedule_next_heartbeat(state) do
    %{state | heartbeat_ref: Process.send_after(self(), :heartbeat, @heartbeat_interval)}
  end

  defp check_and_update_subscriptions(state) do
    {current_systems, current_characters} = get_current_tracking_data()

    {systems_changed, characters_changed} =
      check_for_changes(
        current_systems,
        current_characters,
        state
      )

    log_subscription_status(
      systems_changed,
      characters_changed,
      current_systems,
      current_characters,
      state
    )

    if systems_changed or characters_changed do
      trigger_rejoin(systems_changed, characters_changed)
    end

    schedule_next_update(state)
  end

  defp get_current_tracking_data do
    current_systems = MapSet.new(get_tracked_systems())
    current_characters = MapSet.new(get_tracked_characters())
    {current_systems, current_characters}
  end

  defp check_for_changes(current_systems, current_characters, state) do
    systems_changed = not MapSet.equal?(current_systems, state.subscribed_systems)
    characters_changed = not MapSet.equal?(current_characters, state.subscribed_characters)
    {systems_changed, characters_changed}
  end

  defp log_subscription_status(
         systems_changed,
         characters_changed,
         current_systems,
         current_characters,
         state
       ) do
    Logger.debug("Subscription update check completed",
      systems_changed: systems_changed,
      characters_changed: characters_changed,
      current_systems_count: MapSet.size(current_systems),
      current_characters_count: MapSet.size(current_characters),
      subscribed_systems_count: MapSet.size(state.subscribed_systems),
      subscribed_characters_count: MapSet.size(state.subscribed_characters),
      current_systems_sample: Enum.take(MapSet.to_list(current_systems), 5),
      current_characters_sample: Enum.take(MapSet.to_list(current_characters), 5)
    )
  end

  defp trigger_rejoin(systems_changed, characters_changed) do
    Logger.warning(
      "Subscription update needed - triggering channel rejoin",
      systems_changed: systems_changed,
      characters_changed: characters_changed
    )

    send(self(), :join_channel)
  end

  defp schedule_next_update(state) do
    subscription_update_ref =
      Process.send_after(self(), :subscription_update, @subscription_update_interval)

    {:ok, %{state | subscription_update_ref: subscription_update_ref}}
  end

  defp handle_subscription_error(error, state) do
    Logger.error("Subscription update check failed",
      error: Exception.message(error)
    )

    # Schedule next subscription update anyway to prevent hanging
    schedule_next_update(state)
  end

  defp prepare_subscription_data do
    tracked_systems = get_tracked_systems()
    tracked_characters = get_tracked_characters()

    # Apply configurable limits to prevent overwhelming WebSocket server
    max_systems = Application.get_env(:wanderer_notifier, :websocket_max_systems, 1000)
    max_characters = Application.get_env(:wanderer_notifier, :websocket_max_characters, 500)

    limited_systems = Enum.take(tracked_systems, max_systems)
    limited_characters = Enum.take(tracked_characters, max_characters)

    log_subscription_data(
      tracked_systems,
      tracked_characters,
      limited_systems,
      limited_characters
    )

    {limited_systems, limited_characters}
  end

  defp log_subscription_data(all_systems, all_characters, limited_systems, limited_characters) do
    Logger.debug("WebSocket channel join data preparation",
      total_systems_count: length(all_systems),
      total_characters_count: length(all_characters),
      limited_systems_count: length(limited_systems),
      limited_characters_count: length(limited_characters),
      sample_systems: Enum.take(limited_systems, 5),
      sample_characters: Enum.take(limited_characters, 5)
    )
  end

  defp build_join_params(systems, characters) do
    if systems == [] and characters == [] do
      Logger.debug("No valid systems or characters found, joining with empty subscription")

      %{
        systems: [],
        character_ids: [],
        preload: %{enabled: false}
      }
    else
      Logger.debug("Subscribing to all tracked systems and characters")

      %{
        systems: systems,
        character_ids: characters,
        preload: %{
          enabled: true,
          limit_per_system: 20,
          since_hours: 12
        }
      }
    end
  end

  defp send_join_message(join_params, systems, characters, state) do
    channel_ref = "join_#{System.system_time(:millisecond)}_#{:rand.uniform(10000)}"

    join_message = %{
      topic: "killmails:lobby",
      event: "phx_join",
      payload: join_params,
      ref: channel_ref
    }

    # Log the full subscription data being sent
    Logger.debug(
      "WebSocket subscription data: #{length(systems)} systems, #{length(characters)} characters"
    )

    Logger.debug("Systems sample: #{inspect(Enum.take(systems, 10))}")

    Logger.debug("Characters sample: #{inspect(Enum.take(characters, 10))}")

    Logger.debug("Full join params: #{inspect(join_params, limit: :infinity)}")

    case Jason.encode(join_message) do
      {:ok, json} ->
        log_join_success(systems, characters)

        new_state = %{
          state
          | channel_ref: channel_ref,
            subscribed_systems: MapSet.new(systems),
            subscribed_characters: MapSet.new(characters)
        }

        {:reply, {:text, json}, new_state}

      {:error, reason} ->
        Logger.error("Failed to encode join message",
          error: inspect(reason)
        )

        retry_count = Map.get(state, :join_retry_count, 0)
        delay = calculate_backoff(retry_count)
        Process.send_after(self(), :join_channel, delay)
        {:ok, %{state | join_retry_count: retry_count + 1}}
    end
  end

  defp log_join_success(systems, characters) do
    Logger.debug("Joining killmails channel",
      systems_count: length(systems),
      characters_count: length(characters)
    )
  end

  # Handle Phoenix channel messages
  defp handle_phoenix_message(
         %{"event" => "phx_reply", "payload" => %{"status" => "ok"}, "ref" => ref},
         state
       )
       when ref == state.channel_ref do
    Logger.debug("Successfully joined killmails channel")
    # Reset join retry count on successful join
    {:ok, %{state | join_retry_count: 0}}
  end

  defp handle_phoenix_message(
         %{"event" => "phx_reply", "payload" => %{"status" => "error", "response" => response}},
         state
       ) do
    Logger.error("Failed to join channel",
      error: inspect(response)
    )

    retry_count = Map.get(state, :join_retry_count, 0)
    delay = calculate_backoff(retry_count)
    Process.send_after(self(), :join_channel, delay)
    {:ok, %{state | join_retry_count: retry_count + 1}}
  end

  defp handle_phoenix_message(%{"event" => "killmail_update", "payload" => payload}, state) do
    killmails = payload["killmails"] || []
    system_id = payload["system_id"]
    is_preload = payload["preload"] || false

    Logger.debug("Received killmail update",
      system_id: system_id,
      killmails_count: length(killmails),
      preload: is_preload
    )

    # Transform and send each killmail to the pipeline
    Enum.each(killmails, fn killmail ->
      transformed_killmail = transform_killmail(killmail)
      send_to_pipeline(transformed_killmail, state)
    end)

    {:ok, state}
  end

  defp handle_phoenix_message(%{"event" => "kill_count_update", "payload" => payload}, state) do
    system_id = payload["system_id"]
    count = payload["count"]

    Logger.debug("Kill count update",
      system_id: system_id,
      count: count
    )

    {:ok, state}
  end

  defp handle_phoenix_message(%{"event" => "preload_complete", "payload" => payload}, state) do
    total_kills = payload["total_kills"]
    systems_processed = payload["systems_processed"]

    Logger.info("Preload complete",
      total_kills: total_kills,
      systems_processed: systems_processed
    )

    {:ok, state}
  end

  defp handle_phoenix_message(%{"event" => event}, state) do
    Logger.debug("Unhandled Phoenix event", event: event)
    {:ok, state}
  end

  defp handle_phoenix_message(msg, state) do
    Logger.debug("Unhandled Phoenix message",
      message: inspect(msg)
    )

    {:ok, state}
  end

  # Transform external service killmail format to internal format
  defp transform_killmail(external_killmail) do
    # Validate required fields
    killmail_id = external_killmail["killmail_id"]

    if !killmail_id do
      raise ArgumentError, "Missing required killmail_id in external killmail"
    end

    %{
      "killmail_id" => killmail_id,
      "kill_time" => external_killmail["kill_time"],
      "system_id" => external_killmail["system_id"],
      "victim" => transform_victim(external_killmail["victim"]),
      "attackers" => transform_attackers(external_killmail["attackers"] || []),
      "zkb" => external_killmail["zkb"] || %{},
      # Mark as pre-enriched so pipeline knows to skip ESI calls
      "enriched" => true
    }
  end

  defp transform_victim(victim) when is_map(victim) do
    %{
      "character_id" => victim["character_id"],
      "character_name" => victim["character_name"],
      "corporation_id" => victim["corporation_id"],
      "corporation_name" => victim["corporation_name"],
      "alliance_id" => victim["alliance_id"],
      "alliance_name" => victim["alliance_name"],
      "ship_type_id" => victim["ship_type_id"],
      "ship_name" => victim["ship_name"],
      "damage_taken" => victim["damage_taken"]
    }
  end

  defp transform_victim(_), do: %{}

  defp transform_attackers(attackers) when is_list(attackers) do
    Enum.map(attackers, fn attacker ->
      %{
        "character_id" => attacker["character_id"],
        "character_name" => attacker["character_name"],
        "corporation_id" => attacker["corporation_id"],
        "corporation_name" => attacker["corporation_name"],
        "alliance_id" => attacker["alliance_id"],
        "alliance_name" => attacker["alliance_name"],
        "ship_type_id" => attacker["ship_type_id"],
        "ship_name" => attacker["ship_name"],
        "damage_done" => attacker["damage_done"],
        "final_blow" => attacker["final_blow"] || false,
        "security_status" => attacker["security_status"],
        "weapon_type_id" => attacker["weapon_type_id"]
      }
    end)
  end

  defp transform_attackers(_), do: []

  # Send transformed killmail to pipeline worker
  defp send_to_pipeline(killmail, state) do
    # Skip Integration module entirely - it has redundant deduplication
    # The Pipeline module has the proper domain-specific deduplication
    send_to_legacy_pipeline(killmail, state)
  end

  defp send_to_legacy_pipeline(killmail, state) do
    if state.pipeline_worker do
      send(state.pipeline_worker, {:websocket_killmail, killmail})
    else
      # If no specific pipeline worker, send to the default one
      case Process.whereis(WandererNotifier.Domains.Killmail.PipelineWorker) do
        nil ->
          Logger.error("PipelineWorker not found")

        pid ->
          send(pid, {:websocket_killmail, killmail})
      end
    end
  end

  # Get tracked systems from ExternalAdapters
  defp get_tracked_systems do
    case ApiContext.get_tracked_systems() do
      {:ok, systems} ->
        systems
        |> Enum.map(&extract_system_id/1)
        |> Enum.filter(&valid_system_id?/1)
        |> Enum.uniq()

      {:error, reason} ->
        Logger.error("Failed to get tracked systems: #{inspect(reason)}")

        []
    end
  rescue
    error ->
      Logger.error(
        "Exception in get_tracked_systems: #{Exception.message(error)} (#{inspect(error.__struct__)})"
      )

      []
  end

  defp extract_system_id(system) when is_struct(system) do
    # Struct format (MapSystem) - access using dot notation
    system.solar_system_id || system.id
  end

  defp extract_system_id(system) when is_map(system) do
    # Plain map format
    system["solar_system_id"] || system[:solar_system_id] ||
      system["system_id"] || system[:system_id]
  end

  defp extract_system_id(_), do: nil

  defp valid_system_id?(system_id) do
    is_integer(system_id) && system_id > 30_000_000 && system_id < 40_000_000
  end

  # Get tracked characters from ExternalAdapters
  defp get_tracked_characters do
    Logger.info("Fetching tracked characters from ExternalAdapters")

    case ApiContext.get_tracked_characters() do
      {:ok, characters} ->
        Logger.info("ExternalAdapters returned characters",
          count: length(characters),
          first_char: inspect(Enum.at(characters, 0)) |> String.slice(0, 200)
        )

        log_raw_characters(characters)
        process_character_list(characters)

      {:error, reason} ->
        Logger.error("Failed to get tracked characters: #{inspect(reason)}")
        []
    end
  rescue
    error ->
      Logger.error(
        "Exception in get_tracked_characters: #{Exception.message(error)} (#{inspect(error.__struct__)})"
      )

      []
  end

  defp log_raw_characters(characters) do
    Logger.debug("Raw character data from ExternalAdapters",
      count: length(characters),
      sample: Enum.take(characters, 3) |> Enum.map(&inspect/1)
    )
  end

  defp process_character_list(characters) do
    Logger.info("Starting to process character list", count: length(characters))

    extracted_ids = Enum.map(characters, &extract_character_id/1)

    Logger.info("Extracted character IDs",
      extracted_count: length(extracted_ids),
      sample_ids: Enum.take(extracted_ids, 5)
    )

    valid_ids = Enum.filter(extracted_ids, &valid_character_id?/1)

    Logger.info("After validity filter",
      valid_count: length(valid_ids),
      sample_valid_ids: Enum.take(valid_ids, 5)
    )

    processed = Enum.uniq(valid_ids)

    Logger.debug(
      "Processed #{length(processed)} tracked characters from #{length(characters)} inputs"
    )

    processed
  end

  defp extract_character_id(char) do
    # Extract from nested character structure
    char_id = char["character"]["eve_id"]

    normalized = normalize_character_id(char_id)

    normalized
  end

  defp normalize_character_id(id) when is_integer(id), do: id

  defp normalize_character_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> int_id
      _ -> nil
    end
  end

  defp normalize_character_id(_), do: nil

  defp valid_character_id?(char_id) do
    is_integer(char_id) && char_id > 90_000_000 && char_id < 100_000_000_000
  end

  # Build the WebSocket URL with proper Phoenix socket path
  defp build_socket_url(base_url) do
    base_url
    |> String.replace("http://", "ws://")
    |> String.replace("https://", "wss://")
    |> ensure_socket_path()
  end

  defp ensure_socket_path(url) do
    cond do
      String.ends_with?(url, "/socket/websocket") ->
        # Already has the correct Phoenix Channels WebSocket path
        add_version_param(url)

      String.ends_with?(url, "/socket") ->
        # Add the WebSocket path
        add_version_param("#{url}/websocket")

      true ->
        # Build the full path
        url = String.trim_trailing(url, "/")
        add_version_param("#{url}/socket/websocket")
    end
  end

  defp add_version_param(url) do
    # Always use Phoenix WebSocket version 1.0.0
    separator = if String.contains?(url, "?"), do: "&", else: "?"
    "#{url}#{separator}vsn=1.0.0"
  end
end
