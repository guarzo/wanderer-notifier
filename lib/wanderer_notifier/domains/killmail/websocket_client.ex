defmodule WandererNotifier.Domains.Killmail.WebSocketClient do
  @moduledoc """
  WebSocket client for connecting to the external WandererKills service.

  Provides real-time WebSocket connection for receiving pre-enriched killmail data.
  """

  use WebSockex
  require Logger

  alias WandererNotifier.Domains.Tracking.MapTrackingClient
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Infrastructure.Messaging.ConnectionMonitor
  alias WandererNotifier.Shared.Utils.{EntityUtils, ErrorHandler, Retry, TimeUtils}

  @initial_reconnect_delay 1_000
  @max_reconnect_delay 60_000
  @heartbeat_interval 30_000
  # 5 minutes
  @subscription_update_interval 300_000

  def start_link(opts \\ []) do
    websocket_url = WandererNotifier.Shared.Config.websocket_url()

    name = Keyword.get(opts, :name, __MODULE__)

    Logger.debug("Starting WebSocket client", url: websocket_url)

    # Build the WebSocket URL with Phoenix socket path
    socket_url = build_socket_url(websocket_url)

    Logger.debug("Attempting WebSocket connection", socket_url: socket_url)

    state = %{
      url: socket_url,
      channel_ref: nil,
      heartbeat_ref: nil,
      subscription_update_ref: nil,
      subscribed_systems: MapSet.new(),
      subscribed_characters: MapSet.new(),
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
      "WebSocket connected successfully. Starting heartbeat and subscription updates",
      url: state.url,
      heartbeat_interval: @heartbeat_interval,
      subscription_update_interval: @subscription_update_interval
    )

    # Generate connection ID for tracking
    connection_id =
      "websocket_killmail_#{System.system_time(:millisecond)}_#{:rand.uniform(1_000_000)}"

    # Notify fallback handler that WebSocket is connected
    if Process.whereis(WandererNotifier.Domains.Killmail.FallbackHandler) do
      WandererNotifier.Domains.Killmail.FallbackHandler.websocket_connected()
    end

    # Register with ConnectionMonitor
    ConnectionMonitor.register_connection(connection_id, :websocket, %{
      url: state.url,
      pid: self()
    })

    ConnectionMonitor.update_connection_status(connection_id, :connected)

    # Update metrics with connection start time
    WandererNotifier.Shared.Metrics.update_websocket_info(%{
      connection_start: System.system_time(:second)
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

    # Update ConnectionMonitor status
    if state.connection_id do
      ConnectionMonitor.update_connection_status(state.connection_id, :disconnected)
    end

    # Notify fallback handler that WebSocket is down
    if Process.whereis(WandererNotifier.Domains.Killmail.FallbackHandler) do
      WandererNotifier.Domains.Killmail.FallbackHandler.websocket_down()
    end

    # Clear websocket stats on disconnect
    WandererNotifier.Shared.Metrics.update_websocket_info(%{
      connection_start: nil
    })

    # Calculate exponential backoff with jitter using unified retry logic
    delay = calculate_backoff(state.reconnect_attempts)

    Logger.debug(
      "WebSocket scheduling reconnect",
      delay_ms: delay,
      attempt: state.reconnect_attempts + 1
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
      "WebSocket endpoint not found (404). Please check if the WandererKills service is running and has the correct endpoint",
      url: state.url,
      subscribed_systems: MapSet.size(state.subscribed_systems),
      subscribed_characters: MapSet.size(state.subscribed_characters)
    )
  end

  defp log_disconnect_reason({:error, {:closed, :econnrefused}}, state) do
    Logger.error(
      "WebSocket connection refused. Please check if the WandererKills service is running",
      url: state.url,
      subscribed_systems: MapSet.size(state.subscribed_systems),
      subscribed_characters: MapSet.size(state.subscribed_characters)
    )
  end

  defp log_disconnect_reason({:remote, :closed}, state) do
    Logger.error(
      "WebSocket closed by remote server. This may indicate an issue with the channel join message or server-side validation",
      url: state.url,
      subscribed_systems: MapSet.size(state.subscribed_systems),
      subscribed_characters: MapSet.size(state.subscribed_characters)
    )
  end

  defp log_disconnect_reason({:remote, 1012, message}, state) do
    Logger.info(
      "WebSocket server restarting (code 1012)",
      message: inspect(message),
      connected_systems: MapSet.size(state.subscribed_systems),
      connected_characters: MapSet.size(state.subscribed_characters),
      url: state.url
    )
  end

  defp log_disconnect_reason({:remote, code, message}, state) when is_integer(code) do
    Logger.error(
      "WebSocket closed by remote server",
      code: code,
      message: inspect(message),
      connected_systems: MapSet.size(state.subscribed_systems),
      connected_characters: MapSet.size(state.subscribed_characters),
      url: state.url
    )
  end

  defp log_disconnect_reason(reason, state) do
    Logger.error(
      "WebSocket disconnected",
      url: state.url,
      reason: inspect(reason),
      subscribed_systems: MapSet.size(state.subscribed_systems),
      subscribed_characters: MapSet.size(state.subscribed_characters)
    )
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp calculate_backoff(attempts) do
    # Use the unified Retry module's backoff calculation
    state = %{
      mode: :exponential,
      base_backoff: @initial_reconnect_delay,
      max_backoff: @max_reconnect_delay,
      # Fixed 30% jitter
      jitter: 0.3,
      # Retry module uses 1-based attempts
      attempt: attempts + 1
    }

    Retry.calculate_backoff(state)
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
    Logger.debug("WebSocket text frame received", message_size: message_size)
  end

  defp handle_decoded_message(data, state) do
    log_decoded_message(data)
    handle_phoenix_message(data, state)
  end

  defp log_decoded_message(data) do
    Logger.debug(
      "Decoded WebSocket message",
      event: data["event"],
      topic: data["topic"],
      payload_keys: inspect(extract_payload_keys(data["payload"]))
    )
  end

  defp extract_payload_keys(payload) when is_map(payload), do: Map.keys(payload)
  defp extract_payload_keys(_), do: nil

  defp handle_decode_error(message, message_size, reason, state) do
    message_preview = truncate_message(message, message_size)

    Logger.error(
      "Failed to decode WebSocket message",
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
    # Increment heartbeat count for periodic status logging
    heartbeat_count = Map.get(state, :heartbeat_count, 0) + 1
    state = Map.put(state, :heartbeat_count, heartbeat_count)

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
    Logger.debug("Starting subscription update check")

    try do
      check_and_update_subscriptions(state)
    rescue
      error ->
        Logger.error("Subscription update check failed", error: ErrorHandler.format_error(error))
        # Schedule next subscription update anyway to prevent hanging
        subscription_update_ref =
          Process.send_after(self(), :subscription_update, @subscription_update_interval)

        {:ok, %{state | subscription_update_ref: subscription_update_ref}}
    end
  end

  def handle_info(:join_channel, state) do
    Logger.debug("WebSocket handling join_channel message")

    try do
      {limited_systems, limited_characters} = prepare_subscription_data()
      join_params = build_join_params(limited_systems, limited_characters)
      result = send_join_message(join_params, limited_systems, limited_characters, state)
      Logger.debug("Join channel result", result: inspect(result))
      result
    rescue
      error ->
        Logger.error("Error during channel join", error: ErrorHandler.format_error(error))

        # Retry with exponential backoff
        retry_count = Map.get(state, :join_retry_count, 0)
        delay = calculate_backoff(retry_count)

        Logger.debug("Scheduling channel join retry", delay_ms: delay, attempt: retry_count + 1)

        Process.send_after(self(), :join_channel, delay)
        {:ok, %{state | join_retry_count: retry_count + 1}}
    end
  end

  defp log_heartbeat_uptime(state) do
    uptime = calculate_connection_uptime(state)

    Logger.debug(
      "WebSocket heartbeat - Connection uptime",
      uptime_seconds: uptime,
      uptime_minutes: div(uptime, 60),
      uptime_seconds_remainder: rem(uptime, 60)
    )

    # Log killmail activity status every 5 minutes (10 heartbeats at 30s interval)
    heartbeat_count = Map.get(state, :heartbeat_count, 0)

    if rem(heartbeat_count, 10) == 0 do
      log_killmail_activity_status(state)
    end
  end

  defp log_killmail_activity_status(state) do
    activity = WandererNotifier.Shared.Metrics.get_killmail_activity()
    uptime = calculate_connection_uptime(state)

    last_received_ago = TimeUtils.format_time_ago(activity[:last_received_at])
    last_notified_ago = TimeUtils.format_time_ago(activity[:last_notified_at])

    Logger.info(
      "[Killmail Status] uptime=#{div(uptime, 60)}m, " <>
        "subscribed_systems=#{MapSet.size(state.subscribed_systems)}, " <>
        "subscribed_chars=#{MapSet.size(state.subscribed_characters)}, " <>
        "received=#{activity[:received_count] || 0} (last: #{last_received_ago}), " <>
        "notified=#{activity[:notified_count] || 0} (last: #{last_notified_ago})"
    )
  end

  defp calculate_connection_uptime(%{connected_at: %DateTime{} = connected_at}) do
    DateTime.diff(DateTime.utc_now(), connected_at, :second)
  end

  defp calculate_connection_uptime(_), do: 0

  defp record_heartbeat_in_monitoring(state) do
    if state.connection_id do
      ConnectionMonitor.record_heartbeat(state.connection_id)
    end

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

    # Schedule next update and return proper WebSockex format
    subscription_update_ref =
      Process.send_after(self(), :subscription_update, @subscription_update_interval)

    {:ok, %{state | subscription_update_ref: subscription_update_ref}}
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
    Logger.debug(
      "Subscription update check completed",
      systems_changed: systems_changed,
      characters_changed: characters_changed,
      current_systems: MapSet.size(current_systems),
      current_characters: MapSet.size(current_characters),
      subscribed_systems: MapSet.size(state.subscribed_systems),
      subscribed_characters: MapSet.size(state.subscribed_characters)
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
    Logger.debug(
      "WebSocket channel join data preparation",
      total_systems: length(all_systems),
      total_characters: length(all_characters),
      limited_systems: length(limited_systems),
      limited_characters: length(limited_characters)
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
    channel_ref = generate_channel_ref()

    log_subscription_details(systems, characters, join_params)

    join_params
    |> build_join_message(channel_ref)
    |> Jason.encode()
    |> handle_join_encoding_result(channel_ref, systems, characters, state)
  end

  defp generate_channel_ref do
    "join_#{System.system_time(:millisecond)}_#{:rand.uniform(10000)}"
  end

  defp build_join_message(join_params, channel_ref) do
    %{
      topic: "killmails:lobby",
      event: "phx_join",
      payload: join_params,
      ref: channel_ref
    }
  end

  defp log_subscription_details(systems, characters, join_params) do
    Logger.debug(
      "WebSocket subscription data",
      systems_count: length(systems),
      characters_count: length(characters)
    )

    Logger.debug("Systems sample", systems_sample: inspect(Enum.take(systems, 10)))
    Logger.debug("Characters sample", characters_sample: inspect(Enum.take(characters, 10)))
    Logger.debug("Full join params", join_params: inspect(join_params, limit: :infinity))
  end

  defp handle_join_encoding_result({:ok, json}, channel_ref, systems, characters, state) do
    log_join_success(systems, characters)

    new_state = %{
      state
      | channel_ref: channel_ref,
        subscribed_systems: MapSet.new(systems),
        subscribed_characters: MapSet.new(characters)
    }

    {:reply, {:text, json}, new_state}
  end

  defp handle_join_encoding_result({:error, reason}, _channel_ref, _systems, _characters, state) do
    Logger.error("Failed to encode join message", error: inspect(reason))

    retry_count = Map.get(state, :join_retry_count, 0)
    delay = calculate_backoff(retry_count)
    Process.send_after(self(), :join_channel, delay)
    {:ok, %{state | join_retry_count: retry_count + 1}}
  end

  defp log_join_success(systems, characters) do
    Logger.debug(
      "Joining killmails channel",
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
    Logger.error("Failed to join channel", error: inspect(response))

    retry_count = Map.get(state, :join_retry_count, 0)
    delay = calculate_backoff(retry_count)
    Process.send_after(self(), :join_channel, delay)
    {:ok, %{state | join_retry_count: retry_count + 1}}
  end

  defp handle_phoenix_message(%{"event" => "killmail_update", "payload" => payload}, state) do
    killmails = payload["killmails"] || []
    system_id = payload["system_id"]
    is_preload = payload["preload"] || false

    # Log at INFO level to track killmail reception
    Logger.info(
      "Received killmail update",
      system_id: system_id,
      killmails_count: length(killmails),
      preload: is_preload
    )

    # Transform and send each killmail to the pipeline with deduplication
    Enum.each(killmails, fn killmail ->
      killmail_id = killmail["killmail_id"]

      # Record that we received this killmail (for diagnostics)
      WandererNotifier.Shared.Metrics.record_killmail_received(killmail_id)

      if should_process_killmail?(killmail_id) do
        transformed_killmail = transform_killmail(killmail)
        send_to_pipeline(transformed_killmail, state)
      else
        Logger.debug("WebSocket: Skipping duplicate killmail", killmail_id: killmail_id)
      end
    end)

    {:ok, state}
  end

  defp handle_phoenix_message(%{"event" => "kill_count_update", "payload" => payload}, state) do
    system_id = payload["system_id"]
    count = payload["count"]

    Logger.debug("Kill count update", system_id: system_id, count: count)

    {:ok, state}
  end

  defp handle_phoenix_message(%{"event" => "preload_complete", "payload" => payload}, state) do
    total_kills = payload["total_kills"]
    systems_processed = payload["systems_processed"]

    Logger.info(
      "Preload complete",
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
    Logger.debug("Unhandled Phoenix message", message: inspect(msg))

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

  defp send_to_pipeline(killmail, _state) do
    # Send to the registered PipelineWorker process with retry mechanism
    send_to_pipeline_with_retry(killmail, _max_attempts = 3, _attempt = 1)
  end

  defp send_to_pipeline_with_retry(killmail, max_attempts, attempt) when attempt > max_attempts do
    killmail_id = Map.get(killmail, "killmail_id", "unknown")

    Logger.error("PipelineWorker not available after #{max_attempts} attempts, killmail dropped",
      killmail_id: killmail_id,
      attempts: max_attempts,
      category: :processor
    )

    {:error, :pipeline_worker_unavailable}
  end

  defp send_to_pipeline_with_retry(killmail, max_attempts, attempt) do
    case Process.whereis(WandererNotifier.Domains.Killmail.PipelineWorker) do
      nil ->
        killmail_id = Map.get(killmail, "killmail_id", "unknown")
        # Exponential backoff: 100ms, 200ms, 400ms
        delay = (100 * :math.pow(2, attempt - 1)) |> round()

        Logger.warning("PipelineWorker not found, retrying in #{delay}ms",
          killmail_id: killmail_id,
          attempt: attempt,
          max_attempts: max_attempts,
          category: :processor
        )

        Process.sleep(delay)
        send_to_pipeline_with_retry(killmail, max_attempts, attempt + 1)

      pid ->
        send(pid, {:websocket_killmail, killmail})
        :ok
    end
  end

  # Get tracked systems from MapTrackingClient directly
  defp get_tracked_systems do
    case ErrorHandler.safe_execute(
           fn ->
             systems = get_systems_from_cache_or_api()
             process_systems_list(systems)
           end,
           context: %{operation: :get_tracked_systems}
         ) do
      {:ok, result} when is_list(result) -> result
      {:error, _reason} -> []
    end
  end

  defp get_systems_from_cache_or_api do
    case Cache.get(Cache.Keys.map_systems()) do
      {:ok, systems} when is_list(systems) ->
        systems

      _ ->
        fetch_systems_from_api()
    end
  end

  defp fetch_systems_from_api do
    case MapTrackingClient.fetch_and_cache_systems() do
      {:ok, systems} ->
        systems

      {:error, reason} ->
        Logger.error("Failed to get tracked systems", reason: inspect(reason))
        []
    end
  end

  defp process_systems_list(systems) do
    systems
    |> Enum.map(&extract_system_id/1)
    |> Enum.filter(&valid_system_id?/1)
    |> Enum.uniq()
  end

  defp extract_system_id(system), do: EntityUtils.extract_system_id(system)

  defp valid_system_id?(system_id), do: EntityUtils.valid_system_id?(system_id)

  # Get tracked characters from MapTrackingClient directly
  defp get_tracked_characters do
    case ErrorHandler.safe_execute(
           fn ->
             Logger.debug("Fetching tracked characters from MapTrackingClient")

             # Try cache first
             fetch_characters_with_cache()
           end,
           context: %{operation: :get_tracked_characters}
         ) do
      {:ok, result} when is_list(result) -> result
      {:error, _reason} -> []
    end
  end

  defp fetch_characters_with_cache do
    case Cache.get(Cache.Keys.map_characters()) do
      {:ok, characters} when is_list(characters) ->
        get_characters_from_cache(characters)

      _ ->
        get_characters_from_api()
    end
  end

  defp get_characters_from_cache(characters) do
    Logger.debug("Retrieved tracked characters from cache", characters_count: length(characters))
    log_raw_characters(characters)
    process_character_list(characters)
  end

  defp get_characters_from_api do
    case MapTrackingClient.fetch_and_cache_characters() do
      {:ok, characters} ->
        Logger.debug("MapTrackingClient returned characters",
          characters_count: length(characters)
        )

        log_raw_characters(characters)
        process_character_list(characters)

      {:error, reason} ->
        Logger.error("Failed to get tracked characters", reason: inspect(reason))
        []
    end
  end

  defp log_raw_characters(characters) do
    Logger.debug(
      "Raw character data from ExternalAdapters",
      count: length(characters),
      sample: inspect(Enum.take(characters, 3))
    )
  end

  defp process_character_list(characters) do
    extracted_ids = Enum.map(characters, &extract_character_id/1)
    valid_ids = Enum.filter(extracted_ids, &valid_character_id?/1)
    processed = Enum.uniq(valid_ids)

    Logger.debug(
      "Processed character list",
      inputs: length(characters),
      extracted: length(extracted_ids),
      valid: length(valid_ids),
      unique: length(processed)
    )

    processed
  end

  defp extract_character_id(char), do: EntityUtils.extract_character_id(char)

  defp valid_character_id?(char_id) do
    is_integer(char_id) && char_id > 90_000_000 && char_id < 100_000_000_000
  end

  # WebSocket-level deduplication to prevent immediate duplicates
  defp should_process_killmail?(killmail_id) do
    alias WandererNotifier.Infrastructure.Cache.Deduplication

    case Deduplication.check_and_mark(:websocket, to_string(killmail_id)) do
      :new -> true
      :duplicate -> false
    end
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
