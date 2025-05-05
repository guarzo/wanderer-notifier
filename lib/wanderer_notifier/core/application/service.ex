defmodule WandererNotifier.Core.Application.Service do
  @moduledoc """
  The main WandererNotifier service (GenServer).
  Coordinates periodic maintenance and kill processing.
  """

  use GenServer
  alias WandererNotifier.ESI.Service, as: ESIService
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Config
  alias WandererNotifier.Notifications.Helpers.Deduplication
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Killmail.Processor, as: KillmailProcessor
  alias WandererNotifier.Schedulers.CharacterUpdateScheduler
  alias WandererNotifier.Schedulers.SystemUpdateScheduler
  alias WandererNotifier.Killmail.Websocket, as: KillmailWebsocket

  @default_interval :timer.minutes(5)

  defmodule State do
    @moduledoc """
    Maintains the state of the application.
    """
    defstruct [
      :ws_pid,
      processed_kill_ids: %{},
      last_status_time: nil,
      service_start_time: nil,
      last_systems_update: nil,
      last_characters_update: nil,
      systems_count: 0,
      characters_count: 0
    ]
  end

  @doc """
  Starts the service.
  """
  def start_link(opts \\ []) do
    AppLogger.startup_debug("Starting WandererNotifier Service")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  @impl true
  def init(_opts) do
    AppLogger.startup_debug("Initializing WandererNotifier Service")
    # Trap exits so the GenServer doesn't crash when a linked process dies
    Process.flag(:trap_exit, true)
    now = :os.system_time(:second)

    # Initialize kill stats for tracking
    KillmailProcessor.init()

    # Debug system tracking status
    state = %State{
      service_start_time: now,
      last_status_time: now,
      last_systems_update: now,
      last_characters_update: now
    }

    state = start_zkill_ws(state)

    # Schedule Discord notification with a delay to ensure hackney is initialized
    Process.send_after(self(), :send_startup_notification, 2000)

    # Schedule first maintenance run
    schedule_next_run(@default_interval)

    # Schedule stats logging now that we're initialized
    KillmailProcessor.schedule_tasks()

    # Schedule a direct call to the maintenance scheduler after 10 seconds to handle both systems and characters
    Process.send_after(self(), :update_tracked_data, 10_000)

    {:ok, state}
  rescue
    e ->
      AppLogger.startup_error("❌ Error in Service initialization",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      # Return a basic valid state to avoid crashing
      {:ok, %State{service_start_time: :os.system_time(:second)}}
  end

  def mark_as_processed(kill_id) do
    GenServer.cast(__MODULE__, {:mark_as_processed, kill_id})
  end

  @impl true
  def handle_cast({:mark_as_processed, kill_id}, state) do
    if Map.has_key?(state.processed_kill_ids, kill_id) do
      {:noreply, state}
    else
      new_state =
        %{
          state
          | processed_kill_ids:
              Map.put(state.processed_kill_ids, kill_id, :os.system_time(:second))
        }

      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:run_maintenance, state) do
    try do
      run_maintenance()
      schedule_next_run(@default_interval)
    catch
      kind, error ->
        handle_maintenance_error({kind, error})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:maintenance, state) do
    # Maintenance is now handled by the dedicated maintenance service
    {:noreply, state}
  end

  @impl true
  def handle_info(:initial_maintenance, state) do
    # Maintenance is now handled by the dedicated maintenance service
    {:noreply, state}
  end

  @impl true
  def handle_info({:zkill_message, message}, state) do
    # Process the message with the KillmailProcessor
    new_state = KillmailProcessor.process_zkill_message(message, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:ws_disconnected, state) do
    AppLogger.websocket_warn("Websocket disconnected, scheduling reconnect",
      reconnect_delay_ms: Config.websocket_reconnect_delay()
    )

    Process.send_after(self(), :reconnect_ws, Config.websocket_reconnect_delay())
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect_ws, state) do
    # Check if the websocket is enabled in config
    if Config.websocket_enabled?() do
      AppLogger.websocket_info("Attempting to reconnect WandererNotifier.Killmail.Websocket")
      new_state = reconnect_zkill_ws(state)
      {:noreply, new_state}
    else
      AppLogger.websocket_info(
        "Skipping WandererNotifier.Killmail.Websocket reconnection - disabled by configuration"
      )

      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:force_refresh_cache, state) do
    AppLogger.cache_warn(
      "Received force_refresh_cache message. Refreshing critical data after cache recovery"
    )

    # Execute the system and character update schedulers directly
    SystemUpdateScheduler.run()
    CharacterUpdateScheduler.run()

    AppLogger.cache_info("Cache refresh completed after recovery")
    {:noreply, state}
  end

  @impl true
  def handle_info(:log_kill_stats, state) do
    KillmailProcessor.log_stats()
    {:noreply, state}
  rescue
    e ->
      AppLogger.kill_error("Error logging kill stats", error: Exception.message(e))
      {:noreply, state}
  end

  @impl true
  def handle_info(:update_tracked_data, state) do
    AppLogger.startup_debug("Running scheduled initial data update")

    try do
      # Execute the system and character update schedulers directly
      SystemUpdateScheduler.run()
      CharacterUpdateScheduler.run()

      AppLogger.startup_debug("Initial tracked data update complete")

      {:noreply, state}
    rescue
      e ->
        AppLogger.startup_error("Error in tracked data update",
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Try again in 5 seconds if there was an error
        Process.send_after(self(), :update_tracked_data, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:debug_special_system, system_id}, state) do
    # Get system name for better logging
    system_name = get_system_name(system_id)

    AppLogger.maintenance_info("Processing debug request for system",
      system_id: system_id,
      system_name: system_name
    )

    # Get all tracked systems from cache
    tracked_systems =
      case CacheRepo.get("map:systems") do
        {:ok, value} -> value
        _ -> []
      end

    AppLogger.maintenance_info("Found tracked systems", count: length(tracked_systems))

    # Check if system is already tracked
    found =
      Enum.any?(tracked_systems, fn system ->
        case system do
          %{solar_system_id: id} when not is_nil(id) ->
            id_str = to_string(id)
            id_str == to_string(system_id)

          %{"solar_system_id" => id} when not is_nil(id) ->
            id_str = to_string(id)
            id_str == to_string(system_id)

          %{system_id: id} when not is_nil(id) ->
            id_str = to_string(id)
            id_str == to_string(system_id)

          %{"system_id" => id} when not is_nil(id) ->
            id_str = to_string(id)
            id_str == to_string(system_id)

          id when is_integer(id) or is_binary(id) ->
            id_str = to_string(id)
            id_str == to_string(system_id)

          _ ->
            false
        end
      end)

    AppLogger.maintenance_info("System tracked status",
      system_id: system_id,
      system_name: system_name,
      is_tracked: found
    )

    # Try direct cache lookup
    direct_system =
      case CacheRepo.get("map:system:#{system_id}") do
        {:ok, value} -> value
        _ -> nil
      end

    AppLogger.cache_debug("Direct cache lookup result",
      key: "map:system:#{system_id}",
      result: inspect(direct_system)
    )

    # Use the new CacheHelpers function instead of directly manipulating the cache
    ttl = Config.systems_cache_ttl()
    :ok = CacheRepo.set(WandererNotifier.Cache.Keys.tracked_system(system_id), true, ttl)

    AppLogger.maintenance_info("Added system to tracked systems",
      system_id: system_id,
      system_name: system_name
    )

    AppLogger.maintenance_info("Debug tracking operation complete",
      system_id: system_id,
      system_name: system_name
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:debug_special_character, character_id}, state) do
    # Get character name for better logging
    character_name = get_character_name(character_id)

    AppLogger.maintenance_info("Processing debug request for character",
      character_id: character_id,
      character_name: character_name
    )

    # Get all tracked characters from cache
    tracked_characters =
      case CacheRepo.get("tracked:character:#{character_id}") do
        {:ok, value} -> value
        _ -> []
      end

    AppLogger.maintenance_info("Found tracked characters", count: length(tracked_characters))

    # Check if character is already tracked
    character_id_str = to_string(character_id)

    # Try direct cache lookup
    direct_character =
      case CacheRepo.get("tracked:character:#{character_id_str}") do
        {:ok, value} -> value
        _ -> nil
      end

    AppLogger.cache_debug("Direct cache lookup result",
      key: "tracked:character:#{character_id_str}",
      result: inspect(direct_character)
    )

    # Use the CacheHelpers function to add the character
    ttl = Config.characters_cache_ttl()
    :ok = CacheRepo.set(WandererNotifier.Cache.Keys.tracked_character(character_id), true, ttl)

    AppLogger.maintenance_info("Added character to tracked characters",
      character_id: character_id,
      character_name: character_name
    )

    AppLogger.maintenance_info("Debug tracking operation complete",
      character_id: character_id,
      character_name: character_name
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) when reason == :normal do
    AppLogger.processor_debug("Linked process exited normally", pid: inspect(pid))
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    AppLogger.processor_warn("Linked process exited abnormally",
      pid: inspect(pid),
      reason: inspect(reason)
    )

    # Check if the crashed process is the Killmail websocket (now WandererNotifier.Killmail.Websocket)
    if pid == state.ws_pid do
      AppLogger.websocket_warn(
        "Killmail websocket crashed. Scheduling reconnect (WandererNotifier.Killmail.Websocket)",
        reconnect_delay_ms: Config.websocket_reconnect_delay()
      )

      Process.send_after(self(), :reconnect_ws, Config.websocket_reconnect_delay())
      {:noreply, %{state | ws_pid: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:clear_dedup_key, key}, state) do
    # Handle deduplication key expiration
    # Parse type and id from key (e.g., "system:123")
    case String.split(key, ":", parts: 2) do
      [type_str, id] ->
        type =
          case type_str do
            "system" -> :system
            "character" -> :character
            "kill" -> :kill
            _ -> :system # default/fallback
          end
        Deduplication.clear_key(type, id)
      _ ->
        :noop
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(:send_startup_notification, state) when state.config_loaded == false do
    # If config not loaded yet, schedule a retry
    AppLogger.startup_debug("Config not loaded yet, scheduling startup notification retry")
    Process.send_after(self(), :send_startup_notification, 1000)
    {:noreply, state}
  end

  @impl true
  def handle_info(:send_startup_notification, state) do
    AppLogger.startup_info("Sending startup notification", %{
      uptime: :os.system_time(:second) - state.service_start_time
    })

    WandererNotifier.Notifiers.StatusNotifier.send_status_message(
      "WandererNotifier Service Status",
      "The service has started and is now operational."
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(:flush_batch_logs, state) do
    # Flush any remaining batch logs
    WandererNotifier.Logger.Logger.flush_batch_logs()
    {:noreply, state}
  rescue
    e ->
      AppLogger.processor_error("Error flushing batch logs", error: Exception.message(e))
      {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if is_map(state) and Map.get(state, :ws_pid), do: Process.exit(state.ws_pid, :normal)
    :ok
  end

  # Schedule the next maintenance run
  defp schedule_next_run(interval) do
    Process.send_after(self(), :run_maintenance, interval)
  end

  # Handle maintenance errors
  defp handle_maintenance_error(error) do
    AppLogger.scheduler_error("[Service] Maintenance error: #{inspect(error)}")
    # Continue with scheduling next run despite error
    schedule_next_run(@default_interval)
  end

  # Run maintenance tasks
  defp run_maintenance do
    # Override in child modules
    :ok
  end

  defp start_zkill_ws(state) do
    # Check if websocket is enabled in config
    if Config.websocket_enabled?() do
      AppLogger.websocket_debug("Starting WandererNotifier.Killmail.Websocket")

      case KillmailWebsocket.start_link(self()) do
        {:ok, pid} ->
          AppLogger.websocket_info("🔌 WandererNotifier.Killmail.Websocket ready")
          %{state | ws_pid: pid}

        {:error, reason} ->
          AppLogger.websocket_error("❌ Failed to start websocket", error: inspect(reason))

          # Notify about the failure
          WandererNotifier.Notifications.Dispatcher.send_message("Failed to start websocket: #{inspect(reason)}")

          # Return state without websocket
          state
      end
    else
      AppLogger.websocket_debug("WandererNotifier.Killmail.Websocket disabled by configuration")
      state
    end
  end

  defp reconnect_zkill_ws(state) do
    # Check if the websocket is enabled in config
    if Config.websocket_enabled?() do
      case KillmailWebsocket.start_link(self()) do
        {:ok, pid} ->
          AppLogger.websocket_info("Reconnected to WandererNotifier.Killmail.Websocket",
            pid: inspect(pid)
          )

          %{state | ws_pid: pid}

        {:error, reason} ->
          AppLogger.websocket_error("Reconnection failed", error: inspect(reason))
          Process.send_after(self(), :reconnect_ws, Config.websocket_reconnect_delay())
          state
      end
    else
      AppLogger.websocket_info(
        "WandererNotifier.Killmail.Websocket reconnection skipped - disabled by configuration"
      )

      state
    end
  end

  @doc """
  Dumps the current tracked systems data for debugging purposes.
  """
  def debug_tracked_systems do
    # Get and analyze tracked systems
    tracked_data = collect_tracked_systems_data()

    # Verify test system tracking
    test_system_id = "30000253"
    test_system_data = analyze_test_system(tracked_data.tracked_systems, test_system_id)

    # Return summary of findings
    %{
      tracked_systems_count: tracked_data.system_count,
      raw_systems_count: tracked_data.raw_system_count,
      test_system_found: test_system_data.matches != [],
      test_system_details: test_system_data.matches
    }
  end

  # Collect all tracked systems data
  defp collect_tracked_systems_data do
    # Fetch tracked systems and log count
    tracked_systems =
      case CacheRepo.get("map:systems") do
        {:ok, value} -> value
        _ -> []
      end

    system_count = length(tracked_systems)
    AppLogger.maintenance_info("Found tracked systems", count: system_count)

    # Fetch raw systems from cache and log count
    raw_systems =
      case CacheRepo.get("map:systems") do
        {:ok, value} -> value
        _ -> []
      end

    raw_system_count = if is_list(raw_systems), do: length(raw_systems), else: 0
    AppLogger.cache_info("Raw map:systems cache data", count: raw_system_count)

    # Log and analyze system samples if available
    if system_count > 0 do
      sample_systems(tracked_systems, system_count)
    end

    %{
      tracked_systems: tracked_systems,
      system_count: system_count,
      raw_systems: raw_systems,
      raw_system_count: raw_system_count
    }
  end

  # Sample systems for debugging
  defp sample_systems(tracked_systems, system_count) do
    sample = Enum.take(tracked_systems, min(3, system_count))
    AppLogger.maintenance_debug("Sample system structure", sample: inspect(sample))

    # Extract and log ID formats for sample systems
    id_formats = extract_id_formats(sample)
    AppLogger.maintenance_debug("ID formats", formats: inspect(id_formats))
  end

  # Analyze test system
  defp analyze_test_system(tracked_systems, test_system_id) do
    AppLogger.maintenance_debug("Checking if system is tracked", system_id: test_system_id)

    matches = find_test_system(tracked_systems, test_system_id)

    if matches == [] do
      AppLogger.maintenance_debug("System NOT in tracked systems list", system_id: test_system_id)
    else
      AppLogger.maintenance_debug("System IS in tracked systems list",
        system_id: test_system_id,
        matches: inspect(matches)
      )
    end

    # Check additional cache data
    check_additional_cache_data(test_system_id)

    %{matches: matches}
  end

  # Find test system in tracked systems
  defp find_test_system(tracked_systems, test_system_id) do
    AppLogger.maintenance_debug("Checking if system is tracked", system_id: test_system_id)

    Enum.filter(tracked_systems, fn system ->
      system_matches_id?(system, test_system_id)
    end)
  end

  # Check if system matches the test ID
  defp system_matches_id?(%{solar_system_id: id}, test_id) when not is_nil(id),
    do: to_string(id) == test_id

  defp system_matches_id?(%{"solar_system_id" => id}, test_id) when not is_nil(id),
    do: to_string(id) == test_id

  defp system_matches_id?(%{system_id: id}, test_id) when not is_nil(id),
    do: to_string(id) == test_id

  defp system_matches_id?(%{"system_id" => id}, test_id) when not is_nil(id),
    do: to_string(id) == test_id

  defp system_matches_id?(id, test_id) when is_integer(id) or is_binary(id),
    do: to_string(id) == test_id

  defp system_matches_id?(_, _), do: false

  # Check additional cache data for test system
  defp check_additional_cache_data(test_system_id) do
    system_ids_key =
      case CacheRepo.get("map:system_ids") do
        {:ok, value} -> value
        _ -> nil
      end

    specific_system_key =
      case CacheRepo.get("map:system:#{test_system_id}") do
        {:ok, value} -> value
        _ -> nil
      end

    AppLogger.cache_debug("map:system_ids contents", contents: inspect(system_ids_key))

    AppLogger.cache_debug("map:system key contents",
      key: "map:system:#{test_system_id}",
      contents: inspect(specific_system_key)
    )
  end

  # Extract ID formats from sample systems
  defp extract_id_formats(sample) do
    Enum.map(sample, fn system ->
      %{
        system: system,
        formats: %{
          raw: system,
          solar_system_id_atom: is_map(system) && Map.get(system, :solar_system_id),
          solar_system_id_string: is_map(system) && Map.get(system, "solar_system_id"),
          system_id_atom: is_map(system) && Map.get(system, :system_id),
          system_id_string: is_map(system) && Map.get(system, "system_id")
        }
      }
    end)
  end

  # Helper function to get system name
  defp get_system_name(system_id) do
    case ESIService.get_system_info(system_id) do
      {:ok, system_info} -> Map.get(system_info, "name")
      {:error, :not_found} -> "Unknown System (ID: #{system_id})"
      _ -> "Unknown System"
    end
  end

  # Helper function to get character names
  defp get_character_name(character_id) do
    case ESIService.get_character_info(character_id) do
      {:ok, character_info} -> Map.get(character_info, "name")
      _ -> "Unknown Character"
    end
  end

  @doc """
  Gets the list of recent kills from the kill processor
  Used for API endpoints.
  """
  def get_recent_kills do
    # Forward to the kill processor
    KillmailProcessor.get_recent_kills()
  end

  @doc """
  Sends a test kill notification.
  Used for testing kill notifications through the API.
  """
  def send_test_kill_notification do
    KillmailProcessor.send_test_kill_notification()
  end

  def start_websocket do
    if Config.websocket_enabled?() do
      AppLogger.api_info("Starting WebSocket")

      # Continue with the rest of the implementation...
    else
      AppLogger.api_info("WebSocket is disabled via configuration")
      :ok
    end
  end

end
