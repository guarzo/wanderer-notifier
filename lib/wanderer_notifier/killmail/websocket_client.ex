defmodule WandererNotifier.Killmail.WebSocketClient do
  @moduledoc """
  WebSocket client for connecting to the external WandererKills service.

  This module replaces the RedisQ HTTP polling approach with a real-time
  WebSocket connection that receives pre-enriched killmail data.
  """

  use WebSockex

  alias WandererNotifier.Contexts.ExternalAdapters

  @reconnect_delay 5_000
  @heartbeat_interval 30_000
  # 5 minutes
  @subscription_update_interval 300_000

  def start_link(opts \\ []) do
    websocket_url = WandererNotifier.Config.websocket_url()

    name = Keyword.get(opts, :name, __MODULE__)

    WandererNotifier.Logger.Logger.startup_info("Starting WebSocket client", url: websocket_url)

    # Build the WebSocket URL with Phoenix socket path
    socket_url = build_socket_url(websocket_url)

    WandererNotifier.Logger.Logger.startup_info("Attempting WebSocket connection",
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
      connected_at: nil
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

    WandererNotifier.Logger.Logger.startup_info(
      "WebSocket connected successfully to #{state.url}. Starting heartbeat (#{@heartbeat_interval}ms) and subscription updates (#{@subscription_update_interval}ms)."
    )

    # Start heartbeat
    heartbeat_ref = Process.send_after(self(), :heartbeat, @heartbeat_interval)

    # Start subscription update timer
    subscription_update_ref =
      Process.send_after(self(), :subscription_update, @subscription_update_interval)

    # Join the killmails channel
    send(self(), :join_channel)

    {:ok,
     %{
       state
       | heartbeat_ref: heartbeat_ref,
         subscription_update_ref: subscription_update_ref,
         connected_at: connected_at
     }}
  end

  def handle_disconnect(%{reason: reason}, state) do
    log_disconnect_reason(reason, state)

    # Cancel timers
    cancel_timer(state.heartbeat_ref)
    cancel_timer(state.subscription_update_ref)

    # Reconnect after delay
    Process.send_after(self(), :connect_delayed, @reconnect_delay)

    {:ok,
     %{
       state
       | channel_ref: nil,
         heartbeat_ref: nil,
         subscription_update_ref: nil,
         connected_at: nil
     }}
  end

  defp log_disconnect_reason({:error, {404, _headers, _body}}, state) do
    WandererNotifier.Logger.Logger.error(
      "WebSocket endpoint not found (404) at #{state.url}. Please check if the WandererKills service is running and has the correct endpoint. Subscribed to #{MapSet.size(state.subscribed_systems)} systems and #{MapSet.size(state.subscribed_characters)} characters."
    )
  end

  defp log_disconnect_reason({:error, {:closed, :econnrefused}}, state) do
    WandererNotifier.Logger.Logger.error(
      "WebSocket connection refused at #{state.url}. Please check if the WandererKills service is running. Subscribed to #{MapSet.size(state.subscribed_systems)} systems and #{MapSet.size(state.subscribed_characters)} characters."
    )
  end

  defp log_disconnect_reason({:remote, :closed}, state) do
    WandererNotifier.Logger.Logger.error(
      "WebSocket closed by remote server at #{state.url}. This may indicate an issue with the channel join message or server-side validation. Subscribed to #{MapSet.size(state.subscribed_systems)} systems and #{MapSet.size(state.subscribed_characters)} characters."
    )
  end

  defp log_disconnect_reason({:remote, code, message}, state) when is_integer(code) do
    WandererNotifier.Logger.Logger.error(
      "WebSocket closed by remote server with code #{code}. Message: #{inspect(message)}. Connected systems: #{MapSet.size(state.subscribed_systems)}, characters: #{MapSet.size(state.subscribed_characters)}. URL: #{state.url}"
    )
  end

  defp log_disconnect_reason(reason, state) do
    WandererNotifier.Logger.Logger.error(
      "WebSocket disconnected from #{state.url} with reason: #{inspect(reason)}. Subscribed to #{MapSet.size(state.subscribed_systems)} systems and #{MapSet.size(state.subscribed_characters)} characters."
    )
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  def handle_frame({:text, message}, state) do
    WandererNotifier.Logger.Logger.info("WebSocket text frame received",
      message_size: byte_size(message),
      message_preview: String.slice(message, 0, 500)
    )

    case Jason.decode(message) do
      {:ok, data} ->
        WandererNotifier.Logger.Logger.info("Decoded WebSocket message",
          event: data["event"],
          topic: data["topic"],
          payload_keys: if(is_map(data["payload"]), do: Map.keys(data["payload"]), else: nil)
        )

        handle_phoenix_message(data, state)

      {:error, reason} ->
        WandererNotifier.Logger.Logger.error("Failed to decode WebSocket message",
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
    # Log heartbeat with connection uptime
    uptime =
      if state[:connected_at] do
        DateTime.diff(DateTime.utc_now(), state.connected_at, :second)
      else
        0
      end

    WandererNotifier.Logger.Logger.info(
      "WebSocket heartbeat - Connection uptime: #{uptime}s (#{div(uptime, 60)}m #{rem(uptime, 60)}s)"
    )

    # Send Phoenix heartbeat
    if state.channel_ref do
      heartbeat_message = %{
        topic: "phoenix",
        event: "heartbeat",
        payload: %{},
        ref: "heartbeat_#{System.system_time(:millisecond)}"
      }

      case Jason.encode(heartbeat_message) do
        {:ok, json} ->
          {:reply, {:text, json},
           %{state | heartbeat_ref: Process.send_after(self(), :heartbeat, @heartbeat_interval)}}

        {:error, _} ->
          {:ok,
           %{state | heartbeat_ref: Process.send_after(self(), :heartbeat, @heartbeat_interval)}}
      end
    else
      WandererNotifier.Logger.Logger.warn("Heartbeat attempted but no channel_ref set")
      {:ok, %{state | heartbeat_ref: Process.send_after(self(), :heartbeat, @heartbeat_interval)}}
    end
  end

  def handle_info(:connect_delayed, state) do
    # Attempt to reconnect
    send(self(), :join_channel)
    {:ok, state}
  end

  def handle_info(:subscription_update, state) do
    WandererNotifier.Logger.Logger.info("Starting subscription update check")

    try do
      check_and_update_subscriptions(state)
    rescue
      error ->
        handle_subscription_error(error, state)
    end
  end

  def handle_info(:join_channel, state) do
    {limited_systems, limited_characters} = prepare_subscription_data()
    join_params = build_join_params(limited_systems, limited_characters)
    send_join_message(join_params, limited_systems, limited_characters, state)
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
    WandererNotifier.Logger.Logger.info("Subscription update check completed",
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
    WandererNotifier.Logger.Logger.warn(
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
    WandererNotifier.Logger.Logger.error("Subscription update check failed",
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
    WandererNotifier.Logger.Logger.info("WebSocket channel join data preparation",
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
      WandererNotifier.Logger.Logger.startup_info(
        "No valid systems or characters found, joining with empty subscription"
      )

      %{
        systems: [],
        character_ids: [],
        preload: %{enabled: false}
      }
    else
      WandererNotifier.Logger.Logger.startup_info(
        "Subscribing to all tracked systems and characters"
      )

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
    WandererNotifier.Logger.Logger.info(
      "WebSocket subscription data: #{length(systems)} systems, #{length(characters)} characters"
    )

    WandererNotifier.Logger.Logger.info("Systems sample: #{inspect(Enum.take(systems, 10))}")

    WandererNotifier.Logger.Logger.info(
      "Characters sample: #{inspect(Enum.take(characters, 10))}"
    )

    WandererNotifier.Logger.Logger.info(
      "Full join params: #{inspect(join_params, limit: :infinity)}"
    )

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
        WandererNotifier.Logger.Logger.error("Failed to encode join message",
          error: inspect(reason)
        )

        Process.send_after(self(), :join_channel, 5_000)
        {:ok, state}
    end
  end

  defp log_join_success(systems, characters) do
    WandererNotifier.Logger.Logger.startup_info("Joining killmails channel",
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
    WandererNotifier.Logger.Logger.startup_info("Successfully joined killmails channel")
    {:ok, state}
  end

  defp handle_phoenix_message(
         %{"event" => "phx_reply", "payload" => %{"status" => "error", "response" => response}},
         state
       ) do
    WandererNotifier.Logger.Logger.error("Failed to join channel", error: inspect(response))
    Process.send_after(self(), :join_channel, 5_000)
    {:ok, state}
  end

  defp handle_phoenix_message(%{"event" => "killmail_update", "payload" => payload}, state) do
    killmails = payload["killmails"] || []
    system_id = payload["system_id"]
    is_preload = payload["preload"] || false

    WandererNotifier.Logger.Logger.processor_debug("Received killmail update",
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

    WandererNotifier.Logger.Logger.processor_debug("Kill count update",
      system_id: system_id,
      count: count
    )

    {:ok, state}
  end

  defp handle_phoenix_message(%{"event" => "preload_complete", "payload" => payload}, state) do
    total_kills = payload["total_kills"]
    systems_processed = payload["systems_processed"]

    WandererNotifier.Logger.Logger.startup_info("Preload complete",
      total_kills: total_kills,
      systems_processed: systems_processed
    )

    {:ok, state}
  end

  defp handle_phoenix_message(%{"event" => event}, state) do
    WandererNotifier.Logger.Logger.debug("Unhandled Phoenix event", event: event)
    {:ok, state}
  end

  defp handle_phoenix_message(msg, state) do
    WandererNotifier.Logger.Logger.debug("Unhandled Phoenix message", message: inspect(msg))
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
    if state.pipeline_worker do
      send(state.pipeline_worker, {:websocket_killmail, killmail})
    else
      # If no specific pipeline worker, send to the default one
      case Process.whereis(WandererNotifier.Killmail.PipelineWorker) do
        nil ->
          WandererNotifier.Logger.Logger.error("PipelineWorker not found")

        pid ->
          send(pid, {:websocket_killmail, killmail})
      end
    end
  end

  # Get tracked systems from ExternalAdapters
  defp get_tracked_systems do
    # get_all() always returns {:ok, list()}, never an error
    {:ok, systems} = ExternalAdapters.get_tracked_systems()

    systems
    |> Enum.map(&extract_system_id/1)
    |> Enum.filter(&valid_system_id?/1)
    |> Enum.uniq()
  rescue
    error ->
      WandererNotifier.Logger.Logger.error(
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
    # get_all() always returns {:ok, list()}, never an error
    {:ok, characters} = ExternalAdapters.get_tracked_characters()

    log_raw_characters(characters)
    process_character_list(characters)
  rescue
    error ->
      WandererNotifier.Logger.Logger.error(
        "Exception in get_tracked_characters: #{Exception.message(error)} (#{inspect(error.__struct__)})"
      )

      []
  end

  defp log_raw_characters(characters) do
    WandererNotifier.Logger.Logger.debug("Raw character data from ExternalAdapters",
      count: length(characters),
      sample: Enum.take(characters, 3) |> Enum.map(&inspect/1)
    )
  end

  defp process_character_list(characters) do
    processed =
      characters
      |> Enum.map(&extract_character_id/1)
      |> Enum.filter(&valid_character_id?/1)
      |> Enum.uniq()

    WandererNotifier.Logger.Logger.debug("Processed character IDs",
      final_count: length(processed),
      final_ids: processed
    )

    processed
  end

  defp extract_character_id(char) do
    char_id = char["eve_id"] || char[:eve_id]

    WandererNotifier.Logger.Logger.debug("Processing character",
      char_sample: inspect(char),
      extracted_id: inspect(char_id)
    )

    normalize_character_id(char_id)
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
