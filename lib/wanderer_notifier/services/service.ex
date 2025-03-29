defmodule WandererNotifier.Services.Service do
  @moduledoc """
  The main WandererNotifier service (GenServer).
  Coordinates periodic maintenance and kill processing.
  """

  require Logger
  use GenServer
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Api.ZKill.Websocket, as: ZKillWebsocket
  alias WandererNotifier.Core.Config.Timings
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Helpers.CacheHelpers
  alias WandererNotifier.Helpers.DeduplicationHelper
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Services.KillProcessor
  alias WandererNotifier.Services.Maintenance.Scheduler, as: MaintenanceScheduler

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
    AppLogger.startup_info("Starting WandererNotifier Service")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  @impl true
  def init(_opts) do
    AppLogger.startup_info("Initializing WandererNotifier Service")
    # Trap exits so the GenServer doesn't crash when a linked process dies
    Process.flag(:trap_exit, true)
    now = :os.system_time(:second)

    # Initialize kill stats for tracking
    KillProcessor.init_stats()

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
    KillProcessor.schedule_stats_logging()

    {:ok, state}
  rescue
    e ->
      Logger.error("Error in Service.init: #{Exception.message(e)}")
      Logger.error("#{Exception.format_stacktrace(__STACKTRACE__)}")
      # Return a basic valid state to avoid crashing
      {:ok, %State{service_start_time: :os.system_time(:second)}}
  end

  @impl true
  def handle_info(:send_startup_notification, state) do
    # Send delayed startup notification to Discord
    AppLogger.startup_info("Sending delayed startup notification to Discord")
    DiscordNotifier.send_message("WandererNotifier Service started. Listening for notifications.")
    {:noreply, state}
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
    # Process the message with the KillProcessor
    new_state = KillProcessor.process_zkill_message(message, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:ws_disconnected, state) do
    AppLogger.websocket_warn("Websocket disconnected, scheduling reconnect",
      reconnect_delay_ms: Timings.reconnect_delay()
    )

    Process.send_after(self(), :reconnect_ws, Timings.reconnect_delay())
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect_ws, state) do
    # Check if the websocket is enabled in config
    if websocket_enabled?() do
      AppLogger.websocket_info("Attempting to reconnect zKill websocket")
      new_state = reconnect_zkill_ws(state)
      {:noreply, new_state}
    else
      AppLogger.websocket_info(
        "Skipping zKill websocket reconnection - disabled by configuration"
      )

      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:force_refresh_cache, state) do
    AppLogger.cache_warn(
      "Received force_refresh_cache message. Refreshing critical data after cache recovery"
    )

    # Run maintenance tasks to repopulate the cache using the aliased module
    new_state = MaintenanceScheduler.do_initial_checks(state)

    AppLogger.cache_info("Cache refresh completed after recovery")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:log_kill_stats, state) do
    KillProcessor.log_kill_stats()
    {:noreply, state}
  rescue
    e ->
      AppLogger.kill_error("Error logging kill stats", error: Exception.message(e))
      {:noreply, state}
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
    tracked_systems = CacheHelpers.get_tracked_systems()

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
    direct_system = CacheRepo.get("map:system:#{system_id}")

    AppLogger.cache_debug("Direct cache lookup result",
      key: "map:system:#{system_id}",
      result: inspect(direct_system)
    )

    # Use the new CacheHelpers function instead of directly manipulating the cache
    :ok = CacheHelpers.add_system_to_tracked(system_id, system_name)

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
    tracked_characters = CacheHelpers.get_tracked_characters()

    AppLogger.maintenance_info("Found tracked characters", count: length(tracked_characters))

    # Check if character is already tracked
    character_id_str = to_string(character_id)

    # Try direct cache lookup
    direct_character = CacheRepo.get("tracked:character:#{character_id_str}")

    AppLogger.cache_debug("Direct cache lookup result",
      key: "tracked:character:#{character_id_str}",
      result: inspect(direct_character)
    )

    # Use the CacheHelpers function to add the character
    :ok = CacheHelpers.add_character_to_tracked(character_id, character_name)

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

    # Check if the crashed process is the ZKill websocket
    if pid == state.ws_pid do
      AppLogger.websocket_warn("ZKill websocket crashed. Scheduling reconnect",
        reconnect_delay_ms: Timings.reconnect_delay()
      )

      Process.send_after(self(), :reconnect_ws, Timings.reconnect_delay())
      {:noreply, %{state | ws_pid: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:clear_dedup_key, key}, state) do
    # Handle deduplication key expiration
    DeduplicationHelper.handle_clear_key(key)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.ws_pid, do: Process.exit(state.ws_pid, :normal)
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

  defp websocket_enabled? do
    websocket_config = Application.get_env(:wanderer_notifier, :websocket, [])

    enabled =
      case websocket_config do
        config when is_list(config) -> Keyword.get(config, :enabled, true)
        config when is_map(config) -> Map.get(config, :enabled, true)
        # Default to enabled if no config
        nil -> true
        # Default to enabled for unexpected format
        _ -> true
      end

    # Check direct env var as a fallback
    raw_ws_env = System.get_env("WANDERER_WEBSOCKET_ENABLED")
    if is_nil(raw_ws_env), do: enabled, else: raw_ws_env == "true"
  end

  defp start_zkill_ws(state) do
    AppLogger.startup_info("Service attempting to start ZKill websocket")

    # Check if the websocket is enabled in config
    if websocket_enabled?() do
      case ZKillWebsocket.start_link(self()) do
        {:ok, pid} ->
          AppLogger.websocket_info("ZKill websocket started", pid: inspect(pid))
          # Monitor the websocket process
          Process.monitor(pid)
          %{state | ws_pid: pid}

        {:error, reason} ->
          AppLogger.websocket_error("Failed to start websocket", error: inspect(reason))
          DiscordNotifier.send_message("Failed to start websocket: #{inspect(reason)}")
          # Schedule a retry
          Process.send_after(self(), :reconnect_ws, Timings.reconnect_delay())
          state
      end
    else
      AppLogger.websocket_info("ZKill websocket disabled by configuration")
      state
    end
  end

  defp reconnect_zkill_ws(state) do
    # Check if the websocket is enabled in config
    if websocket_enabled?() do
      case ZKillWebsocket.start_link(self()) do
        {:ok, pid} ->
          AppLogger.websocket_info("Reconnected to zKill websocket", pid: inspect(pid))
          %{state | ws_pid: pid}

        {:error, reason} ->
          AppLogger.websocket_error("Reconnection failed", error: inspect(reason))
          Process.send_after(self(), :reconnect_ws, Timings.reconnect_delay())
          state
      end
    else
      AppLogger.websocket_info("ZKill websocket reconnection skipped - disabled by configuration")
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
    tracked_systems = CacheHelpers.get_tracked_systems()
    system_count = length(tracked_systems)
    AppLogger.maintenance_info("Found tracked systems", count: system_count)

    # Fetch raw systems from cache and log count
    raw_systems = CacheRepo.get("map:systems")
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
    system_ids_key = CacheRepo.get("map:system_ids")

    specific_system_key = CacheRepo.get("map:system:#{test_system_id}")

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

  # Helper function to get character name
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
    KillProcessor.get_recent_kills()
  end

  @doc """
  Sends a test kill notification.
  Used for testing kill notifications through the API.
  """
  def send_test_kill_notification do
    KillProcessor.send_test_kill_notification()
  end
end
