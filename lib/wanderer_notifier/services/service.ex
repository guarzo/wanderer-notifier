defmodule WandererNotifier.Services.Service do
  @moduledoc """
  The main WandererNotifier service (GenServer).
  Coordinates periodic maintenance and kill processing.
  """
  use GenServer
  require Logger

  alias WandererNotifier.Api.ZKill.Websocket, as: ZKillWebsocket
  alias WandererNotifier.Core.Config.Timings
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Services.Maintenance.Scheduler, as: MaintenanceScheduler

  @zkill_ws_url "wss://zkillboard.com/websocket/"

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

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: WandererNotifier.Service)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Initializing WandererNotifier Service...")
    # Trap exits so the GenServer doesn't crash when a linked process dies
    Process.flag(:trap_exit, true)
    now = :os.system_time(:second)

    # Initialize kill stats for tracking
    WandererNotifier.Services.KillProcessor.init_stats()

    # The DeduplicationHelper is already started by the application supervisor
    # so we don't need to initialize it here

    state = %State{
      service_start_time: now,
      last_status_time: now,
      last_systems_update: now,
      last_characters_update: now
    }

    state = start_zkill_ws(state)
    # Send one startup notification to Discord.
    WandererNotifier.Notifiers.Factory.notify(:send_message, [
      "WandererNotifier Service started. Listening for notifications."
    ])

    # Run initial maintenance tasks immediately
    Logger.info("Running initial maintenance tasks at startup...")
    # Run after 5 seconds to allow system to initialize
    Process.send_after(self(), :initial_maintenance, 5000)

    # Schedule regular maintenance
    schedule_maintenance()
    {:ok, state}
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
  def handle_info(:maintenance, state) do
    # Schedule the next maintenance check
    schedule_maintenance()

    # Run maintenance checks using the aliased module
    new_state = MaintenanceScheduler.tick(state)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:initial_maintenance, state) do
    Logger.info("Running initial maintenance tasks...")

    # Add error handling around maintenance tasks
    new_state =
      try do
        # Force a full update of all systems and characters using the aliased module
        MaintenanceScheduler.do_initial_checks(state)
      rescue
        e ->
          Logger.error("Error during initial maintenance: #{inspect(e)}")
          Logger.error("Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
          # Return the original state if maintenance fails
          state
      end

    Logger.info("Initial maintenance tasks completed")
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:zkill_message, message}, state) do
    # Process the message with the KillProcessor
    new_state = WandererNotifier.Services.KillProcessor.process_zkill_message(message, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:ws_disconnected, state) do
    Logger.warning(
      "Websocket disconnected, scheduling reconnect in #{Timings.reconnect_delay()}ms"
    )

    Process.send_after(self(), :reconnect_ws, Timings.reconnect_delay())
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect_ws, state) do
    Logger.info("Attempting to reconnect zKill websocket...")
    new_state = reconnect_zkill_ws(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:force_refresh_cache, state) do
    Logger.warning(
      "Received force_refresh_cache message. Refreshing critical data after cache recovery..."
    )

    # Run maintenance tasks to repopulate the cache using the aliased module
    new_state = MaintenanceScheduler.do_initial_checks(state)

    Logger.info("Cache refresh completed after recovery")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:log_kill_stats, state) do
    try do
      WandererNotifier.Services.KillProcessor.log_kill_stats()
    rescue
      e -> Logger.error("Error logging kill stats: #{Exception.message(e)}")
    end

    # Reschedule for the next interval
    schedule_stats_logging()

    {:noreply, state}
  end

  @impl true
  def handle_info({:debug_special_system, system_id}, state) do
    # Get system name for better logging
    system_name = get_system_name(system_id)
    system_info = if system_name, do: "#{system_id} (#{system_name})", else: system_id

    Logger.info("SPECIAL DEBUG: Processing debug request for system #{system_info}")

    # Get all tracked systems from cache
    tracked_systems = WandererNotifier.Helpers.CacheHelpers.get_tracked_systems()

    Logger.info("SPECIAL DEBUG: Found #{length(tracked_systems)} tracked systems")

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

    Logger.info("SPECIAL DEBUG: System #{system_info} found in tracked systems: #{found}")

    # Try direct cache lookup
    direct_system = WandererNotifier.Data.Cache.Repository.get("map:system:#{system_id}")
    Logger.info("SPECIAL DEBUG: Direct cache lookup result: #{inspect(direct_system)}")

    # Use the new CacheHelpers function instead of directly manipulating the cache
    :ok = WandererNotifier.Helpers.CacheHelpers.add_system_to_tracked(system_id, system_name)
    Logger.info("SPECIAL DEBUG: Added system #{system_info} to tracked systems")

    Logger.info("SPECIAL DEBUG: Debug tracking operation complete for #{system_info}")

    {:noreply, state}
  end

  @impl true
  def handle_info({:debug_special_character, character_id}, state) do
    # Get character name for better logging
    character_name = get_character_name(character_id)

    character_info =
      if character_name, do: "#{character_id} (#{character_name})", else: character_id

    Logger.info("SPECIAL DEBUG: Processing debug request for character #{character_info}")

    # Get all tracked characters from cache
    tracked_characters = WandererNotifier.Helpers.CacheHelpers.get_tracked_characters()

    Logger.info("SPECIAL DEBUG: Found #{length(tracked_characters)} tracked characters")

    # Check if character is already tracked
    character_id_str = to_string(character_id)

    # Try direct cache lookup
    direct_character =
      WandererNotifier.Data.Cache.Repository.get("tracked:character:#{character_id_str}")

    Logger.info("SPECIAL DEBUG: Direct cache lookup result: #{inspect(direct_character)}")

    # Use the CacheHelpers function to add the character
    :ok =
      WandererNotifier.Helpers.CacheHelpers.add_character_to_tracked(character_id, character_name)

    Logger.info("SPECIAL DEBUG: Added character #{character_info} to tracked characters")

    Logger.info("SPECIAL DEBUG: Debug tracking operation complete for #{character_info}")

    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) when reason == :normal do
    Logger.debug("Linked process #{inspect(pid)} exited normally")
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warning("Linked process #{inspect(pid)} exited with reason: #{inspect(reason)}")

    # Check if the crashed process is the ZKill websocket
    if pid == state.ws_pid do
      Logger.warning(
        "ZKill websocket crashed. Scheduling reconnect in #{Timings.reconnect_delay()}ms"
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
    WandererNotifier.Helpers.DeduplicationHelper.handle_clear_key(key)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.ws_pid, do: Process.exit(state.ws_pid, :normal)
    :ok
  end

  defp schedule_maintenance do
    Process.send_after(self(), :maintenance, Timings.maintenance_interval())
  end

  defp start_zkill_ws(state) do
    case ZKillWebsocket.start_link(self(), @zkill_ws_url) do
      {:ok, pid} ->
        Logger.info("ZKill websocket started: #{inspect(pid)}")
        %{state | ws_pid: pid}

      {:error, reason} ->
        Logger.error("Failed to start websocket: #{inspect(reason)}")
        NotifierFactory.notify(:send_message, ["Failed to start websocket: #{inspect(reason)}"])
        state
    end
  end

  defp reconnect_zkill_ws(state) do
    case ZKillWebsocket.start_link(self(), @zkill_ws_url) do
      {:ok, pid} ->
        Logger.info("Reconnected to zKill websocket: #{inspect(pid)}")
        %{state | ws_pid: pid}

      {:error, reason} ->
        Logger.error("Reconnection failed: #{inspect(reason)}")
        Process.send_after(self(), :reconnect_ws, Timings.reconnect_delay())
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
    tracked_systems = WandererNotifier.Helpers.CacheHelpers.get_tracked_systems()
    system_count = length(tracked_systems)
    Logger.info("DEBUG: Found #{system_count} tracked systems")

    # Fetch raw systems from cache and log count
    raw_systems = WandererNotifier.Data.Cache.Repository.get("map:systems")
    raw_system_count = if is_list(raw_systems), do: length(raw_systems), else: 0
    Logger.info("DEBUG: Raw map:systems cache has #{raw_system_count} systems")

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
    Logger.info("DEBUG: Sample system structure: #{inspect(sample)}")

    # Extract and log ID formats for sample systems
    id_formats = extract_id_formats(sample)
    Logger.info("DEBUG: ID formats: #{inspect(id_formats)}")
  end

  # Analyze test system
  defp analyze_test_system(tracked_systems, test_system_id) do
    Logger.info("DEBUG: Checking if system #{test_system_id} is tracked")

    matches = find_test_system(tracked_systems, test_system_id)

    if matches == [] do
      Logger.info("DEBUG: System #{test_system_id} is NOT in the tracked systems list")
    else
      Logger.info(
        "DEBUG: System #{test_system_id} IS in the tracked systems list: #{inspect(matches)}"
      )
    end

    # Check additional cache data
    check_additional_cache_data(test_system_id)

    %{matches: matches}
  end

  # Schedule the next kill stats logging interval (every 5 minutes)
  defp schedule_stats_logging do
    Process.send_after(self(), :log_kill_stats, 5 * 60 * 1000)
  end

  @doc """
  Dumps the current tracked characters data for debugging purposes.
  """
  def debug_tracked_characters do
    tracked_characters = WandererNotifier.Helpers.CacheHelpers.get_tracked_characters()
    character_count = length(tracked_characters)
    Logger.info("DEBUG: Found #{character_count} tracked characters")

    # Get raw data from cache for comparison
    raw_characters = WandererNotifier.Data.Cache.Repository.get("map:characters")
    raw_character_count = if is_list(raw_characters), do: length(raw_characters), else: 0
    Logger.info("DEBUG: Raw map:characters cache has #{raw_character_count} characters")

    # Examine a few characters for structure
    if character_count > 0 do
      sample = Enum.take(tracked_characters, min(3, character_count))
      Logger.info("DEBUG: Sample character structure: #{inspect(sample)}")

      # Get the possible ID formats for each character
      id_formats =
        Enum.map(sample, fn character ->
          %{
            character: character,
            formats: %{
              raw: character,
              character_id_atom: is_map(character) && Map.get(character, :character_id),
              character_id_string: is_map(character) && Map.get(character, "character_id"),
              eve_id_atom: is_map(character) && Map.get(character, :eve_id),
              eve_id_string: is_map(character) && Map.get(character, "eve_id")
            }
          }
        end)

      Logger.info("DEBUG: Character ID formats: #{inspect(id_formats)}")
    end

    # Try additional cache keys
    character_ids_key = WandererNotifier.Data.Cache.Repository.get("map:character_ids")
    tracked_characters_key = WandererNotifier.Data.Cache.Repository.get("tracked:characters")

    Logger.info("DEBUG: map:character_ids contains: #{inspect(character_ids_key)}")
    Logger.info("DEBUG: tracked:characters contains: #{inspect(tracked_characters_key)}")

    %{
      tracked_characters_count: character_count,
      raw_characters_count: raw_character_count,
      sample_characters: Enum.take(tracked_characters, min(3, character_count))
    }
  end

  # Helper function to get system name
  defp get_system_name(system_id) do
    case WandererNotifier.Api.ESI.Service.get_system_info(system_id) do
      {:ok, system_info} -> Map.get(system_info, "name")
      {:error, :not_found} -> "Unknown System (ID: #{system_id})"
      _ -> "Unknown System"
    end
  end

  # Helper function to get character name
  defp get_character_name(character_id) do
    case WandererNotifier.Api.ESI.Service.get_character_info(character_id) do
      {:ok, character_info} -> Map.get(character_info, "name")
      _ -> "Unknown Character"
    end
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

  # Find test system in tracked systems
  defp find_test_system(tracked_systems, test_system_id) do
    Logger.info("DEBUG: Checking if system #{test_system_id} is tracked")

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
    system_ids_key = WandererNotifier.Data.Cache.Repository.get("map:system_ids")

    specific_system_key =
      WandererNotifier.Data.Cache.Repository.get("map:system:#{test_system_id}")

    Logger.info("DEBUG: map:system_ids contains: #{inspect(system_ids_key)}")
    Logger.info("DEBUG: map:system:#{test_system_id} contains: #{inspect(specific_system_key)}")
  end
end
