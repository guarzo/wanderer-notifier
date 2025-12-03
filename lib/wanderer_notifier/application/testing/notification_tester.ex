defmodule WandererNotifier.Application.Testing.NotificationTester do
  @moduledoc """
  Simple IEx helper module for testing notification formats.

  Usage in IEx:

      iex> alias WandererNotifier.Application.Testing.NotificationTester, as: NT
      iex> NT.debug_websocket_restart()
      iex> NT.check_websocket_supervision()
      # Test character notification (with real character ID)
      iex> NT.test_character("123456789")

      # Test system notification (with real system ID)
      iex> NT.test_system("30000142")

      # Process killmail by ID as new notification
      iex> NT.test_killmail_id(129076453)

      # Test WandererKills service connectivity
      iex> NT.test_wanderer_kills_connection()
      # 1. Check tracking configuration:
      iex> NT.check_tracking_data()
      # 2. List cached killmails:
      iex> NT.list_cached_killmails()
      # Override next kill classification
      iex> NT.set_kill_override(:character)
      iex> # Next real kill will be treated as character kill
      iex> NT.websocket_status()
      iex> NT.set_kill_override(:system)
      iex> # Next real kill will be treated as system kill
  """

  require Logger
  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Domains.Tracking.Entities.{Character, System}
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Domains.Killmail.WandererKillsAPI
  alias WandererNotifier.Domains.Killmail.Pipeline

  @kill_override_key "test:kill_override"

  # ═══════════════════════════════════════════════════════════════════════════════
  # Character Notification Testing
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Test character notification by character ID.

  Looks up character data from cache and sends a test notification.
  """
  def test_character(character_id) when is_integer(character_id) do
    Logger.debug("[TEST] Testing character notification for ID: #{character_id}")

    # Debug: check what cache keys exist
    debug_cache_keys()

    case Cache.get("map:character_list") do
      {:ok, character_list} when is_list(character_list) ->
        handle_character_list(character_list, character_id, character_id)

      {:ok, non_list_data} ->
        Logger.info(
          "[TEST] map:character_list exists but is not a list: #{inspect(non_list_data)}"
        )

        check_other_cache_locations(character_id)

      {:error, :not_found} ->
        Logger.info("[TEST] map:character_list not found in cache")
        check_other_cache_locations(character_id)
    end
  end

  def test_character(character_id) when is_binary(character_id) do
    Logger.debug("[TEST] Testing character notification for ID: #{character_id}")

    # Debug: check what cache keys exist
    debug_cache_keys()

    character_id_int = String.to_integer(character_id)

    case Cache.get("map:character_list") do
      {:ok, character_list} when is_list(character_list) ->
        handle_character_list(character_list, character_id_int, character_id)

      {:ok, non_list_data} ->
        Logger.info(
          "[TEST] map:character_list exists but is not a list: #{inspect(non_list_data)}"
        )

        check_other_cache_locations(character_id_int)

      {:error, :not_found} ->
        Logger.info("[TEST] map:character_list not found in cache")
        check_other_cache_locations(character_id_int)
    end
  end

  defp debug_cache_keys do
    # Try to get cache statistics or check common keys
    Logger.debug("[TEST] Checking cache contents...")

    # Check a few common cache keys
    keys_to_check = [
      "map:character_list",
      "map:characters",
      "map:systems",
      "map:character_ids"
    ]

    Enum.each(keys_to_check, fn key ->
      case Cache.get(key) do
        {:ok, data} when is_list(data) ->
          Logger.debug("[TEST] Cache key #{key}: list with #{length(data)} items")

        {:ok, data} ->
          Logger.debug("[TEST] Cache key #{key}: #{inspect(data)}")

        {:error, :not_found} ->
          Logger.debug("[TEST] Cache key #{key}: not found")
      end
    end)
  end

  defp handle_character_list(character_list, character_id, character_id_str) do
    Logger.debug("[TEST] Found #{length(character_list)} characters in map:character_list")
    log_sample_character(character_list)

    case find_character_in_list(character_list, character_id_str, character_id) do
      nil ->
        handle_character_not_found(character_list, character_id_str, character_id)

      character_data ->
        Logger.debug("[TEST] Found character in map list: #{inspect(character_data)}")
        character = create_character_struct(character_data, character_id)
        send_character_notification(character)
    end
  end

  defp log_sample_character(character_list) do
    if not Enum.empty?(character_list) do
      first_char = Enum.at(character_list, 0)
      Logger.debug("[TEST] Sample character structure: #{inspect(first_char)}")
    end
  end

  defp find_character_in_list(character_list, character_id_str, character_id_int) do
    Enum.find(character_list, fn char ->
      character_matches?(char, character_id_str, character_id_int)
    end)
  end

  defp character_matches?(char, character_id_str, character_id_int) do
    # The eve_id is nested inside the "character" sub-map
    character_data = Map.get(char, "character", %{})
    eve_id = Map.get(character_data, "eve_id")

    # Also check the top-level character_id (which is a UUID)
    char_id = Map.get(char, "character_id") || Map.get(char, :character_id)

    eve_id == character_id_str ||
      eve_id == character_id_int ||
      char_id == character_id_str ||
      char_id == character_id_int ||
      to_string(eve_id) == character_id_str ||
      to_string(char_id) == character_id_str
  end

  defp handle_character_not_found(character_list, character_id_str, character_id_int) do
    Logger.debug("[TEST] Character #{character_id_int} not found in map list")
    Logger.debug("[TEST] Checking if character ID is in the list...")

    all_eve_ids =
      Enum.map(character_list, fn char ->
        character_data = Map.get(char, "character", %{})
        Map.get(character_data, "eve_id")
      end)

    Logger.debug("[TEST] All eve_ids in cache: #{inspect(Enum.take(all_eve_ids, 10))}...")

    if character_id_int in all_eve_ids do
      Logger.info("[TEST] Character ID #{character_id_int} IS in the list!")
    end

    if character_id_str in all_eve_ids do
      Logger.info("[TEST] Character ID #{character_id_str} IS in the list as string!")
    end

    check_other_cache_locations(character_id_int)
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # System Notification Testing
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Test system notification by system ID.

  Looks up system data from cache and sends a test notification.
  """
  def test_system(system_id) when is_binary(system_id) do
    Logger.debug("[TEST] Testing system notification for ID: #{system_id}")

    case System.get_system(system_id) do
      {:ok, system} ->
        Logger.debug("[TEST] Found system: #{system.name}")
        send_system_notification(system)

      {:error, :not_found} ->
        Logger.error("[TEST] System #{system_id} not found")
        {:error, :not_found}
    end
  end

  def test_system(system_id) when is_integer(system_id) do
    test_system(Integer.to_string(system_id))
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Killmail ID Processing
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Process a killmail by ID through the full notification pipeline.

  Fetches the killmail data from WandererKills service and processes it
  as a new notification through the normal pipeline.
  """
  def test_killmail_id(killmail_id) when is_binary(killmail_id) do
    Logger.debug("[TEST] Processing killmail ID: #{killmail_id}")

    with {:ok, killmail_data} <- fetch_killmail_data(killmail_id),
         {:ok, result} <- process_killmail(killmail_data) do
      Logger.debug("[TEST] Killmail #{killmail_id} processed successfully: #{inspect(result)}")
      {:ok, result}
    else
      {:error, %{type: :not_found}} ->
        Logger.error("[TEST] Killmail #{killmail_id} not found in WandererKills service")
        {:error, :not_found}

      {:error, %{type: :http_error, message: message}} ->
        Logger.error("[TEST] HTTP error fetching killmail #{killmail_id}: #{message}")
        {:error, :http_error}

      {:error, %{type: :network_error, message: message}} ->
        Logger.error("[TEST] Network error fetching killmail #{killmail_id}: #{message}")
        {:error, :network_error}

      {:error, reason} ->
        Logger.error("[TEST] Failed to process killmail #{killmail_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def test_killmail_id(killmail_id) when is_integer(killmail_id) do
    test_killmail_id(Integer.to_string(killmail_id))
  end

  defp fetch_killmail_data(killmail_id) do
    Logger.debug("[TEST] Fetching killmail data from WandererKills service")

    # Log the base URL being used
    base_url =
      Application.get_env(
        :wanderer_notifier,
        :wanderer_kills_url,
        "http://host.docker.internal:4004"
      )

    full_url = "#{base_url}/api/v1/killmail/#{killmail_id}"
    Logger.debug("[TEST] Request URL: #{full_url}")

    case WandererKillsAPI.get_killmail(killmail_id) do
      {:ok, killmail_data} ->
        Logger.debug(
          "[TEST] Successfully fetched killmail data: #{inspect(Map.keys(killmail_data))}"
        )

        {:ok, killmail_data}

      {:error, %{type: :not_found} = error} ->
        Logger.info("[TEST] Killmail not found - this might be expected if the ID doesn't exist")
        Logger.info("[TEST] Try checking if the WandererKills service is running and accessible")
        {:error, error}

      {:error, %{type: :http_error, message: message} = error} ->
        Logger.error("[TEST] HTTP error: #{message}")
        Logger.info("[TEST] Check if WandererKills service is running at: #{base_url}")
        {:error, error}

      {:error, %{type: :network_error, message: message} = error} ->
        Logger.error("[TEST] Network error: #{message}")
        Logger.info("[TEST] Check network connectivity to: #{base_url}")
        {:error, error}
    end
  end

  defp process_killmail(killmail_data) do
    Logger.debug("[TEST] Processing killmail through pipeline")
    # Direct to pipeline - matches WebSocket flow which now skips Integration
    Pipeline.process_killmail(killmail_data)
  end

  @doc """
  Check if WebSocket process is being supervised and can restart.
  """
  def check_websocket_supervision do
    Logger.info("[TEST] Checking WebSocket supervision...")

    # Check current status
    pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)
    Logger.info("[TEST] Current WebSocket PID: #{inspect(pid)}")

    if pid do
      # Kill the process and see if it restarts
      Logger.info("[TEST] Killing WebSocket process to test supervision...")
      Process.exit(pid, :kill)

      # Wait and check multiple times
      result =
        Enum.reduce_while(1..10, nil, fn i, _acc ->
          Process.sleep(1000)
          new_pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)
          Logger.info("[TEST] After #{i}s - WebSocket PID: #{inspect(new_pid)}")

          check_websocket_restart(new_pid, pid, i)
        end)

      case result do
        {:ok, :restarted} ->
          result

        _ ->
          Logger.error(
            "[TEST] FAILED: WebSocket was not restarted by supervisor after 10 seconds"
          )

          {:error, :not_restarted}
      end
    else
      Logger.error("[TEST] WebSocket not running")
      {:error, :not_running}
    end
  end

  defp check_websocket_restart(new_pid, original_pid, seconds) do
    if new_pid && new_pid != original_pid do
      Logger.info("[TEST] SUCCESS: WebSocket restarted with new PID after #{seconds}s")
      websocket_status()
      {:halt, {:ok, :restarted}}
    else
      {:cont, nil}
    end
  end

  @doc """
  Check WebSocket connection status.

  Shows if the WebSocket client is alive and connected.
  """
  def websocket_status do
    pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)

    if pid do
      if Process.alive?(pid) do
        # Get process info
        info = Process.info(pid, [:message_queue_len, :current_function, :status, :memory])

        Logger.info("[TEST] WebSocket client is ALIVE")
        Logger.info("[TEST] PID: #{inspect(pid)}")
        Logger.info("[TEST] Status: #{inspect(info[:status])}")
        Logger.info("[TEST] Message queue length: #{info[:message_queue_len]}")
        Logger.info("[TEST] Memory: #{info[:memory]} bytes")

        # Try to get the actual WebSocket state
        try do
          state = :sys.get_state(pid)

          if state.connected_at do
            Logger.info("[TEST] WebSocket is CONNECTED!")
            Logger.info("[TEST] Connected at: #{state.connected_at}")
            Logger.info("[TEST] Connection ID: #{state.connection_id}")
            Logger.info("[TEST] Reconnect attempts: #{state.reconnect_attempts}")
            Logger.info("[TEST] Channel ref: #{inspect(state.channel_ref)}")
            Logger.info("[TEST] Subscribed systems: #{MapSet.size(state.subscribed_systems)}")

            Logger.info(
              "[TEST] Subscribed characters: #{MapSet.size(state.subscribed_characters)}"
            )
          else
            Logger.warning("[TEST] WebSocket process is alive but NOT CONNECTED")
            Logger.info("[TEST] Reconnect attempts: #{state.reconnect_attempts}")
          end
        rescue
          e ->
            Logger.debug("[TEST] Could not get WebSocket state: #{inspect(e)}")
            Logger.warning("[TEST] WebSocket is likely CONNECTED (receiving killmails)")
        end

        {:ok, :alive}
      else
        Logger.error("[TEST] WebSocket client process exists but is NOT ALIVE")
        {:error, :dead}
      end
    else
      Logger.error("[TEST] WebSocket client is NOT RUNNING")
      {:error, :not_running}
    end
  end

  @doc """
  Send a message to the WebSocket client to trigger reconnection.

  This is gentler than killing the process.
  """
  def trigger_websocket_reconnect do
    pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)

    if pid do
      Logger.info("[TEST] Sending :join_channel message to WebSocket client...")
      send(pid, :join_channel)

      # Wait a bit for it to process
      Process.sleep(2000)

      # Check status
      websocket_status()
    else
      Logger.error("[TEST] WebSocket client not found")
      {:error, :not_found}
    end
  end

  @doc """
  Force WebSocket reconnection.

  Kills the current WebSocket process to trigger a supervisor restart.
  """
  def reconnect_websocket do
    pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)

    if pid do
      Logger.info("[TEST] Killing WebSocket client process to force reconnection...")
      Process.exit(pid, :kill)

      # Wait a bit for supervisor to restart it
      Process.sleep(2000)

      # Check new status
      new_pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)

      if new_pid && new_pid != pid do
        Logger.info("[TEST] WebSocket client restarted with new PID: #{inspect(new_pid)}")
        websocket_status()
      else
        Logger.error("[TEST] WebSocket client failed to restart")
        {:error, :restart_failed}
      end
    else
      Logger.error("[TEST] WebSocket client not found")
      {:error, :not_found}
    end
  end

  @doc """
  Force the WebSocket to try joining the channel.
  """
  def force_websocket_join do
    pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)

    if pid do
      Logger.info("[TEST] Forcing WebSocket to attempt channel join...")
      send(pid, :join_channel)

      Process.sleep(2000)
      websocket_status()
    else
      Logger.error("[TEST] WebSocket client not found")
      {:error, :not_found}
    end
  end

  @doc """
  Manually start the WebSocket client.
  """
  def start_websocket_client do
    Logger.info("[TEST] Attempting to manually start WebSocket client...")

    case WandererNotifier.Domains.Killmail.WebSocketClient.start_link() do
      {:ok, pid} ->
        Logger.info("[TEST] WebSocket client started with PID: #{inspect(pid)}")
        Process.sleep(2000)
        websocket_status()
    end
  end

  @doc """
  Check what systems and characters are being tracked.
  """
  def check_tracking_data do
    Logger.info("[TEST] Checking current tracking data...")

    check_tracked_systems()
    check_tracked_characters()
    check_startup_suppression()

    :ok
  end

  defp check_tracked_systems do
    case Cache.get(Cache.Keys.map_systems()) do
      {:ok, systems} -> log_tracked_systems(systems)
      {:error, reason} -> Logger.error("[TEST] Failed to get tracked systems: #{inspect(reason)}")
    end
  end

  defp log_tracked_systems(systems) do
    Logger.info("[TEST] Tracked systems: #{length(systems)}")

    systems
    |> Enum.take(5)
    |> Enum.each(&log_system_info/1)
  end

  defp log_system_info(system) do
    Logger.info("[TEST] System: #{system["name"]} (#{system["solar_system_id"]})")
  end

  defp check_tracked_characters do
    case Cache.get("map:character_list") do
      {:ok, characters} ->
        log_tracked_characters(characters)

      {:error, reason} ->
        Logger.error("[TEST] Failed to get tracked characters: #{inspect(reason)}")
    end
  end

  defp log_tracked_characters(characters) do
    Logger.info("[TEST] Tracked characters: #{length(characters)}")

    characters
    |> Enum.take(5)
    |> Enum.each(&log_character_info/1)
  end

  defp log_character_info(char) do
    char_data = char["character"]
    Logger.info("[TEST] Character: #{char_data["name"]} (#{char_data["eve_id"]})")
  end

  defp check_startup_suppression do
    # SimpleApplicationService no longer exists in the refactored code
    Logger.info("[TEST] Startup suppression check not available in refactored architecture")
  end

  @doc """
  List all killmails currently in the cache.
  """
  def list_cached_killmails do
    Logger.info("[TEST] Checking cached killmails...")

    try do
      {:ok, keys} = Cachex.keys(:wanderer_cache)

      killmail_keys = filter_killmail_keys(keys)
      process_killmail_keys(killmail_keys)

      recent_keys = filter_recent_keys(keys)
      process_recent_keys(recent_keys)

      # Also check for deduplication keys
      dedup_keys = filter_dedup_keys(keys)
      process_dedup_keys(dedup_keys)

      {:ok, length(killmail_keys)}
    rescue
      e ->
        Logger.error("[TEST] Error checking cache: #{inspect(e)}")
        {:error, e}
    end
  end

  defp filter_killmail_keys(keys) do
    Enum.filter(keys, fn key ->
      is_binary(key) && String.contains?(key, "killmail")
    end)
  end

  defp filter_recent_keys(keys) do
    Enum.filter(keys, fn key ->
      is_binary(key) &&
        (String.contains?(key, "recent") || String.contains?(key, "processed"))
    end)
  end

  defp process_killmail_keys(killmail_keys) do
    count = length(killmail_keys)
    Logger.info("[TEST] Found #{count} killmail-related cache entries")

    if count > 0 do
      display_sample_keys(killmail_keys)
      log_remaining_entries(count)
    else
      Logger.warning("[TEST] No killmail entries found in cache")
    end
  end

  defp display_sample_keys(keys) do
    keys
    |> Enum.take(10)
    |> Enum.each(&log_cache_entry/1)
  end

  defp log_cache_entry(key) do
    case Cachex.get(:wanderer_cache, key) do
      {:ok, data} when data != nil ->
        Logger.info("[TEST] #{key}: #{inspect(data, limit: :infinity, printable_limit: 200)}")

      {:ok, nil} ->
        Logger.info("[TEST] #{key}: nil")

      {:error, reason} ->
        Logger.info("[TEST] #{key}: error - #{inspect(reason)}")
    end
  end

  defp log_remaining_entries(total) when total > 10 do
    Logger.info("[TEST] ... and #{total - 10} more killmail entries")
  end

  defp log_remaining_entries(_), do: :ok

  defp process_recent_keys([]), do: :ok

  defp process_recent_keys(recent_keys) do
    Logger.info("[TEST] Found #{length(recent_keys)} recent/processed entries")

    recent_keys
    |> Enum.take(5)
    |> Enum.each(&log_recent_entry/1)
  end

  defp log_recent_entry(key) do
    case Cachex.get(:wanderer_cache, key) do
      {:ok, data} -> Logger.info("[TEST] #{key}: #{inspect(data)}")
      _ -> Logger.info("[TEST] #{key}: no data")
    end
  end

  defp filter_dedup_keys(keys) do
    Enum.filter(keys, fn key ->
      is_binary(key) && (String.contains?(key, "dedup") || String.contains?(key, "notification:"))
    end)
  end

  defp process_dedup_keys([]), do: :ok

  defp process_dedup_keys(dedup_keys) do
    Logger.info("[TEST] Found #{length(dedup_keys)} deduplication entries")

    dedup_keys
    |> Enum.take(10)
    |> Enum.each(fn key ->
      Logger.info("[TEST] Dedup key: #{key}")
    end)

    if length(dedup_keys) > 10 do
      Logger.info("[TEST] ... and #{length(dedup_keys) - 10} more dedup entries")
    end
  end

  @doc """
  Monitor WebSocket for real-time killmail activity.
  """
  def monitor_websocket_activity(duration_seconds \\ 30) do
    Logger.info("[TEST] Monitoring WebSocket for #{duration_seconds} seconds...")

    pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)

    if pid do
      # Get initial state
      initial_state = :sys.get_state(pid)
      initial_memory_info = Process.info(pid, :memory)

      initial_memory =
        case initial_memory_info do
          {:memory, bytes} -> bytes
          nil -> 0
        end

      Logger.info("[TEST] Initial memory: #{initial_memory} bytes")
      Logger.info("[TEST] Monitoring started - make some kills now...")

      # Wait for the specified duration
      Process.sleep(duration_seconds * 1000)

      # Check final state
      final_state = :sys.get_state(pid)
      final_memory_info = Process.info(pid, :memory)

      final_memory =
        case final_memory_info do
          {:memory, bytes} -> bytes
          nil -> 0
        end

      Logger.info(
        "[TEST] Final memory: #{final_memory} bytes (change: #{final_memory - initial_memory})"
      )

      # Check for any changes that might indicate activity
      if final_state != initial_state do
        Logger.info("[TEST] WebSocket state changed during monitoring")
      else
        Logger.warning("[TEST] No WebSocket state changes detected")
      end

      # Check cache again
      list_cached_killmails()
    else
      Logger.error("[TEST] WebSocket client not running")
      {:error, :not_running}
    end
  end

  @doc """
  Test WebSocket subscription with minimal data to isolate connection issues.
  """
  def test_minimal_websocket_subscription do
    Logger.info("[TEST] Testing WebSocket with minimal subscription...")

    # Kill current WebSocket
    pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)
    if pid, do: Process.exit(pid, :kill)

    Process.sleep(1000)

    # Temporarily override the subscription limits
    Logger.info("[TEST] Setting minimal subscription limits...")

    # You can try different combinations:
    # 1. Just systems, no characters
    # 2. Just characters, no systems
    # 3. Very small numbers of each

    Application.put_env(:wanderer_notifier, :websocket_max_systems, 3)
    Application.put_env(:wanderer_notifier, :websocket_max_characters, 10)

    Logger.info(
      "[TEST] Starting WebSocket with limited subscription (3 systems, 10 characters)..."
    )

    # Start new WebSocket
    case WandererNotifier.Domains.Killmail.WebSocketClient.start_link() do
      {:ok, new_pid} ->
        Logger.info("[TEST] WebSocket started with PID: #{inspect(new_pid)}")

        # Monitor for connection issues
        # Wait 10 seconds
        Process.sleep(10_000)

        if Process.alive?(new_pid) do
          try do
            state = :sys.get_state(new_pid)

            if state.connected_at do
              Logger.info("[TEST] SUCCESS: WebSocket stayed connected with minimal subscription!")
              Logger.info("[TEST] Connected at: #{state.connected_at}")
            else
              Logger.warning("[TEST] WebSocket alive but not connected")
            end
          rescue
            _ -> Logger.info("[TEST] WebSocket process is running (may be reconnection process)")
          end
        else
          Logger.error("[TEST] WebSocket process died")
        end

        # Reset limits
        Application.put_env(:wanderer_notifier, :websocket_max_systems, 1000)
        Application.put_env(:wanderer_notifier, :websocket_max_characters, 500)
    end
  end

  @doc """
  Debug WebSocket restart failure.
  """
  def debug_websocket_restart do
    Logger.info("[TEST] Debugging WebSocket restart...")

    # Check if the name is still registered
    current_pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)
    Logger.info("[TEST] Current registered PID: #{inspect(current_pid)}")

    if current_pid do
      Logger.info("[TEST] Process alive? #{Process.alive?(current_pid)}")

      if Process.alive?(current_pid) do
        info = Process.info(current_pid)
        Logger.info("[TEST] Process info: #{inspect(info)}")
      end
    end

    # Try to start manually
    Logger.info("[TEST] Attempting manual start...")

    case WandererNotifier.Domains.Killmail.WebSocketClient.start_link() do
      {:ok, pid} ->
        Logger.info("[TEST] SUCCESS: Started with PID #{inspect(pid)}")
        websocket_status()
    end
  end

  @doc """
  Test connectivity to the WandererKills service.

  Useful for debugging connection issues before testing killmail IDs.
  """
  def test_wanderer_kills_connection do
    Logger.info("[TEST] Testing WandererKills service connectivity")

    base_url =
      Application.get_env(
        :wanderer_notifier,
        :wanderer_kills_url,
        "http://host.docker.internal:4004"
      )

    Logger.info("[TEST] WandererKills base URL: #{base_url}")

    # Try to fetch a known killmail to test connectivity
    # Using a high ID that's likely to exist
    test_killmail_id = "128000000"

    case WandererKillsAPI.get_killmail(test_killmail_id) do
      {:ok, _killmail_data} ->
        Logger.info(
          "[TEST] WandererKills service is healthy - successfully fetched test killmail"
        )

        {:ok, :healthy}

      {:error, %{type: :not_found}} ->
        Logger.info(
          "[TEST] WandererKills service is healthy - responded with 404 for test killmail"
        )

        {:ok, :healthy}

      {:error, reason} ->
        Logger.error("[TEST] WandererKills service connection failed: #{inspect(reason)}")
        Logger.info("[TEST] Make sure the WandererKills service is running at: #{base_url}")
        {:error, reason}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Kill Classification Override
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Set kill classification override for the next kill.

  Options:
  - :character - Next kill will be treated as character kill
  - :system - Next kill will be treated as system kill
  - :clear - Remove override
  """
  def set_kill_override(:character) do
    Cache.put(@kill_override_key, :character, :timer.minutes(10))
    Logger.info("[TEST] Kill override set to :character (expires in 10 minutes)")
    :ok
  end

  def set_kill_override(:system) do
    Cache.put(@kill_override_key, :system, :timer.minutes(10))
    Logger.info("[TEST] Kill override set to :system (expires in 10 minutes)")
    :ok
  end

  def set_kill_override(:clear) do
    Cache.delete(@kill_override_key)
    Logger.info("[TEST] Kill override cleared")
    :ok
  end

  @doc """
  Check current kill override setting.
  """
  def get_kill_override do
    case Cache.get(@kill_override_key) do
      {:ok, override} ->
        Logger.info("[TEST] Current kill override: #{override}")
        {:ok, override}

      {:error, :not_found} ->
        Logger.info("[TEST] No kill override set")
        {:ok, nil}
    end
  end

  @doc """
  Get the override for kill classification (called by the system).
  """
  def check_kill_override do
    case Cache.get(@kill_override_key) do
      {:ok, override} ->
        # Clear after use
        Cache.delete(@kill_override_key)
        Logger.info("[TEST] Using kill override: #{override}")
        {:ok, override}

      {:error, :not_found} ->
        {:ok, nil}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Private Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════════

  defp check_other_cache_locations(character_id) do
    # Try as integer with get_character
    case Cache.get_character(character_id) do
      {:ok, character_data} ->
        Logger.info("[TEST] Found character in ESI cache: #{inspect(character_data)}")
        character = create_character_struct(character_data, character_id)
        send_character_notification(character)

      {:error, :not_found} ->
        # Try direct string key
        character_id_str = Integer.to_string(character_id)

        case Cache.get("esi:character:#{character_id_str}") do
          {:ok, character_data} ->
            Logger.info("[TEST] Found character with string key: #{inspect(character_data)}")
            character = create_character_struct(character_data, character_id)
            send_character_notification(character)

          {:error, :not_found} ->
            Logger.error("[TEST] Character #{character_id} not found in any cache location")

            Logger.info(
              "[TEST] Tried: map:character_list, esi:character:#{character_id}, esi:character:#{character_id_str}"
            )

            {:error, :not_found}
        end
    end
  end

  defp create_character_struct(character_data, character_id) do
    # Handle nested structure from map:character_list
    char_info = Map.get(character_data, "character", character_data)
    character_id_str = Integer.to_string(character_id)

    %Character{
      character_id: character_id_str,
      name: get_name(char_info),
      corporation_id: get_corp_id(char_info),
      alliance_id: get_alliance_id(char_info),
      eve_id: character_id_str,
      corporation_ticker: Map.get(char_info, "corporation_ticker"),
      alliance_ticker: Map.get(char_info, "alliance_ticker"),
      tracked: true
    }
  end

  defp get_name(data) do
    Map.get(data, "name") || Map.get(data, :name) || "Unknown"
  end

  defp get_corp_id(data) do
    Map.get(data, "corporation_id") || Map.get(data, :corporation_id)
  end

  defp get_alliance_id(data) do
    Map.get(data, "alliance_id") || Map.get(data, :alliance_id)
  end

  defp send_character_notification(character) do
    try do
      DiscordNotifier.send_new_tracked_character_notification(character)
    rescue
      e ->
        Logger.error("[TEST] Exception sending character notification: #{inspect(e)}")
        {:error, e}
    end
  end

  defp send_system_notification(system) do
    try do
      DiscordNotifier.send_new_system_notification(system)
    rescue
      e ->
        Logger.error("[TEST] Exception sending system notification: #{inspect(e)}")
        {:error, e}
    end
  end
end
