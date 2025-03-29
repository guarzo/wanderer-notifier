defmodule WandererNotifier.Services.KillProcessor do
  @moduledoc """
  Processes killmail data from various sources.
  This module is responsible for analyzing killmail data, determining what actions
  to take, and orchestrating notifications as needed.
  """

  require Logger

  # App-specific aliases
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Timing
  alias WandererNotifier.Data.Character
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Helpers.CacheHelpers
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Logger.BatchLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Resources.KillmailPersistence
  alias WandererNotifier.Service
  alias WandererNotifier.Services.NotificationDeterminer

  # Cache keys for recent kills
  @recent_kills_cache_key "zkill:recent_kills"
  @max_recent_kills 10
  # 1 hour TTL for cached kills
  @kill_ttl 3600

  # Add stats for tracking received kills during this session
  @kill_stats_key :kill_processor_stats

  # Cache for system names to avoid repeated API calls
  @system_names_cache_key :system_names_cache

  # Initialize stats on module load
  def init_stats do
    Process.put(@kill_stats_key, %{
      total_kills_received: 0,
      total_notifications_sent: 0,
      last_kill_time: nil,
      start_time: :os.system_time(:second)
    })

    # Initialize system names cache
    Process.put(@system_names_cache_key, %{})

    # Start a timer to periodically log stats
    schedule_stats_logging()
  end

  # Schedule periodic stats logging (every 5 minutes)
  def schedule_stats_logging do
    # Send the message to the main Service module since that's where GenServer is implemented
    Process.send_after(
      Service,
      :log_kill_stats,
      Timing.get_cache_check_interval()
    )
  end

  # Log kill statistics
  def log_kill_stats do
    stats =
      Process.get(@kill_stats_key) ||
        %{
          total_kills_received: 0,
          total_notifications_sent: 0,
          last_kill_time: nil,
          start_time: :os.system_time(:second)
        }

    current_time = :os.system_time(:second)
    uptime_seconds = current_time - stats.start_time
    hours = div(uptime_seconds, 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)
    seconds = rem(uptime_seconds, 60)

    # Format the last kill time if available
    last_kill_ago =
      if stats.last_kill_time do
        time_diff = current_time - stats.last_kill_time

        cond do
          time_diff < 60 -> "#{time_diff} seconds ago"
          time_diff < 3600 -> "#{div(time_diff, 60)} minutes ago"
          true -> "#{div(time_diff, 3600)} hours ago"
        end
      else
        "none received"
      end

    Logger.info(
      "📊 KILL STATS: Processed #{stats.total_kills_received} kills, sent #{stats.total_notifications_sent} notifications. Last kill: #{last_kill_ago}. Uptime: #{hours}h #{minutes}m #{seconds}s"
    )
  end

  # Update kill statistics
  defp update_kill_stats(type) do
    stats =
      Process.get(@kill_stats_key) ||
        %{
          total_kills_received: 0,
          total_notifications_sent: 0,
          last_kill_time: nil,
          start_time: :os.system_time(:second)
        }

    # Update the appropriate counter
    updated_stats =
      case type do
        :kill_received ->
          %{
            stats
            | total_kills_received: stats.total_kills_received + 1,
              last_kill_time: :os.system_time(:second)
          }

        :notification_sent ->
          %{stats | total_notifications_sent: stats.total_notifications_sent + 1}
      end

    # Store the updated stats
    Process.put(@kill_stats_key, updated_stats)
  end

  def process_zkill_message(message, state) when is_binary(message) do
    AppLogger.websocket_debug("Processing WebSocket message", bytes_size: byte_size(message))

    case Jason.decode(message) do
      {:ok, decoded_message} ->
        process_zkill_message(decoded_message, state)

      {:error, reason} ->
        AppLogger.websocket_error("Failed to decode WebSocket message", error: inspect(reason))
        state
    end
  end

  def process_zkill_message(message, state) when is_map(message) do
    # Determine message type based on structure
    cond do
      # TQ server status message
      Map.has_key?(message, "action") && message["action"] == "tqStatus" ->
        handle_tq_status(message)
        state

      # Killmail message - identified by either killmail_id or zkb key
      Map.has_key?(message, "killmail_id") || Map.has_key?(message, "zkb") ->
        # Update statistics for kill received
        update_kill_stats(:kill_received)
        handle_killmail(message, state)

      # Unknown message type
      true ->
        AppLogger.websocket_warn("Ignoring unknown message type",
          message_keys: Map.keys(message)
        )

        state
    end
  end

  defp handle_tq_status(%{"tqStatus" => %{"players" => player_count, "vip" => vip}}) do
    # Store in process dictionary for now, we could use the state or a separate GenServer later
    Process.put(:tq_status, %{
      player_count: player_count,
      vip: vip,
      timestamp: :os.system_time(:second)
    })

    AppLogger.websocket_debug("Received TQ status update",
      players_online: player_count,
      vip_mode: vip
    )
  end

  defp handle_tq_status(_status) do
    AppLogger.websocket_warn("Received malformed TQ status message")
  end

  defp handle_killmail(killmail, state) do
    # Extract the kill ID
    kill_id = get_killmail_id(killmail)
    AppLogger.kill_debug("Processing killmail", kill_id: kill_id)

    # Skip processing if no kill ID or already processed
    cond do
      is_nil(kill_id) ->
        AppLogger.kill_warn("Received killmail without kill ID")
        state

      Map.has_key?(state.processed_kill_ids, kill_id) ->
        AppLogger.kill_debug("Kill #{kill_id} already processed, skipping")
        state

      true ->
        # Process the new kill - first standardize to Killmail struct
        AppLogger.kill_debug("Processing new kill #{kill_id}")

        # Extract zkb data
        zkb_data = Map.get(killmail, "zkb", %{})

        # The rest is treated as ESI data, removing zkb key
        esi_data = Map.drop(killmail, ["zkb"])

        # Create a Killmail struct to standardize the data structure
        killmail_struct = Killmail.new(kill_id, zkb_data, esi_data)

        # Process the standardized data
        process_new_kill(killmail_struct, kill_id, state)
    end
  end

  defp process_new_kill(%Killmail{} = killmail, kill_id, state) do
    # Store the kill in the cache
    update_recent_kills(killmail)

    # Persist killmail if the feature is enabled and related to tracked character
    # Changed from asynchronous Task to synchronous call for data consistency
    persist_result = persist_killmail_synchronously(killmail)

    # Log the persistence result
    case persist_result do
      {:ok, _} ->
        AppLogger.kill_info("Successfully persisted killmail", kill_id: kill_id)

      :ignored ->
        AppLogger.kill_debug("Killmail #{kill_id} not relevant for persistence, ignoring")

      {:error, reason} ->
        AppLogger.kill_error("Error persisting killmail #{kill_id}: #{inspect(reason)}")
    end

    # Only continue with notification if persistence succeeded or was ignored
    # This ensures database and notifications stay in sync
    case persist_result do
      {:ok, _} ->
        process_killmail_notification(killmail, kill_id, state)

      :ignored ->
        # For ignored killmails (not relevant to tracked characters), we still notify
        process_killmail_notification(killmail, kill_id, state)

      {:error, _} ->
        # If persistence failed, we don't notify
        # This prevents notifications for data that wasn't persisted
        AppLogger.kill_warn(
          "Skipping notification for killmail #{kill_id} due to persistence failure"
        )

        state
    end
  end

  # Helper function to handle killmail persistence synchronously
  defp persist_killmail_synchronously(killmail) do
    result = KillmailPersistence.maybe_persist_killmail(killmail)
    # Properly handle all possible return types
    case result do
      {:ok, record} when is_map(record) or is_struct(record) ->
        # Normal success case with a record
        {:ok, record}

      {:ok, nil} ->
        # Success with no data
        {:ok, :persisted_with_no_data}

      {:ok, other} ->
        # Any other successful result
        AppLogger.kill_debug(
          "Persistence returned unexpected success format: #{inspect(other)}"
        )

        {:ok, :persisted}

      :ignored ->
        # Ignored case
        :ignored

      {:error, reason} ->
        # Error case
        {:error, reason}

      unexpected ->
        # Handle truly unexpected return values
        AppLogger.kill_warn("Persistence returned unexpected format: #{inspect(unexpected)}")
        {:ok, :persisted_with_unexpected_response}
    end
  rescue
    e ->
      AppLogger.kill_error("Error in persistence: #{Exception.message(e)}")
      AppLogger.kill_debug("Stacktrace: #{Exception.format_stacktrace()}")
      {:error, Exception.message(e)}
  end

  # Helper function to process killmail notification
  defp process_killmail_notification(killmail, kill_id, state) do
    # Process the kill for notification
    notification_result = enrich_and_notify(killmail)

    # Properly handle all possible return types
    case notification_result do
      :ok ->
        # Mark kill as processed in state
        Map.update(state, :processed_kill_ids, %{kill_id => :os.system_time(:second)}, fn ids ->
          Map.put(ids, kill_id, :os.system_time(:second))
        end)

      {:error, reason} ->
        AppLogger.kill_error("Error processing kill #{kill_id}: #{reason}")
        state

      other ->
        # Handle any other unexpected return type
        AppLogger.kill_warn(
          "Unexpected return from notification for kill #{kill_id}: #{inspect(other)}"
        )

        state
    end
  end

  # Simplified to remove validate_killmail since we're now using the Killmail struct properly
  defp enrich_and_notify(%Killmail{} = killmail) do
    # Extract basic kill information
    kill_info = extract_kill_info(killmail)

    # Debug tracking for this specific system
    debug_system_tracking(kill_info.system_id)

    # Extract and log victim/attacker information
    victim_info = extract_victim_info(killmail, kill_info.kill_id)
    attacker_info = extract_attacker_info(killmail, kill_info.kill_id)

    # Get tracking information
    tracking_info = get_tracking_info(killmail, victim_info, attacker_info)

    # Log tracking status
    log_tracking_status(tracking_info, kill_info)

    # Determine if notification should be sent and handle it
    handle_notification_decision(killmail, kill_info, tracking_info)
  rescue
    e ->
      AppLogger.kill_error("⚠️ EXCEPTION: Error during kill enrichment: #{Exception.message(e)}")
      {:error, "Failed to enrich kill: #{Exception.message(e)}"}
  end

  # Extract basic kill information (id, system)
  defp extract_kill_info(killmail) do
    kill_id = killmail.killmail_id
    system_id = get_system_id_from_killmail(killmail)
    system_name = get_system_name(system_id)
    system_info = if system_name, do: "#{system_id} (#{system_name})", else: system_id

    %{
      kill_id: kill_id,
      system_id: system_id,
      system_name: system_name,
      system_info: system_info
    }
  end

  # Extract victim information from killmail
  defp extract_victim_info(killmail, _kill_id) do
    victim_map = killmail.esi_data || %{}

    # Extract the victim's character ID if available
    victim_id = Map.get(victim_map, "character_id") || Map.get(victim_map, :character_id)

    if victim_id do
      AppLogger.kill_debug(
        "VICTIM ID EXTRACT: Using character_id #{victim_id} from killmail, will match against character IDs in tracked characters"
      )
    else
      AppLogger.kill_debug("VICTIM ID EXTRACT: No character_id found in killmail victim")
    end

    victim_ship_id = get_in(victim_map, ["ship_type_id"])

    %{
      victim_id: victim_id,
      victim_id_str: if(victim_id, do: to_string(victim_id), else: nil),
      victim_ship_id: victim_ship_id
    }
  end

  # Extract attacker information from killmail
  defp extract_attacker_info(killmail, kill_id) do
    attackers = get_in(killmail.esi_data || %{}, ["attackers"]) || []

    attacker_ids =
      attackers
      |> Enum.map(& &1["character_id"])
      |> Enum.reject(&is_nil/1)

    attacker_ids_str = Enum.map(attacker_ids, &to_string/1)

    # Log attacker information for debugging
    log_attacker_debug(attacker_ids, kill_id)

    %{
      attackers: attackers,
      attacker_ids: attacker_ids,
      attacker_ids_str: attacker_ids_str
    }
  end

  defp log_attacker_debug(attacker_ids, kill_id) do
    if length(attacker_ids) > 0 do
      AppLogger.kill_debug(
        "ATTACKER DEBUG: Kill #{kill_id} has #{length(attacker_ids)} attackers with character IDs"
      )

      Enum.each(attacker_ids, fn attacker_id ->
        AppLogger.kill_debug("ATTACKER DEBUG: Attacker ID: #{attacker_id} in kill #{kill_id}")
      end)
    end
  end

  # Get tracking information (systems and characters)
  defp get_tracking_info(killmail, victim_info, attacker_info) do
    # Get tracked systems - should always be a plain list
    tracked_systems = CacheHelpers.get_tracked_systems()

    if not is_list(tracked_systems) do
      AppLogger.kill_error(
        "ERROR: Expected list from get_tracked_systems but got: #{inspect(tracked_systems)}"
      )
    end

    # Get tracked characters - should always be a plain list
    tracked_characters = CacheHelpers.get_tracked_characters()

    if not is_list(tracked_characters) do
      AppLogger.kill_error(
        "ERROR: Expected list from get_tracked_characters but got: #{inspect(tracked_characters)}"
      )
    end

    # Get tracked character IDs as a set for efficient lookups
    tracked_char_ids =
      MapSet.new(Enum.map(tracked_characters, &extract_character_id/1) |> Enum.reject(&is_nil/1))

    # Log debug info
    if MapSet.size(tracked_char_ids) > 0 do
      sample = tracked_char_ids |> MapSet.to_list() |> Enum.take(3)

      AppLogger.kill_debug(
        "Tracking #{MapSet.size(tracked_char_ids)} character IDs. Sample: #{inspect(sample)}"
      )
    end

    # Check if victim is tracked
    victim_tracked = check_if_victim_tracked(victim_info.victim_id_str, tracked_char_ids)

    # Check which attackers are tracked
    tracked_attackers = find_tracked_attackers(attacker_info.attacker_ids_str, tracked_char_ids)

    # Log attacker matching information
    log_attacker_matching(attacker_info.attacker_ids_str, tracked_char_ids, killmail.killmail_id)

    # Extract the system ID from the killmail
    system_id = Killmail.get_system_id(killmail)

    # Check if system or any character is tracked using notification determiner
    is_system_tracked =
      NotificationDeterminer.tracked_system?(system_id)

    is_character_tracked =
      NotificationDeterminer.has_tracked_character?(killmail)

    # Return tracking information
    %{
      tracked_systems: tracked_systems,
      tracked_characters: tracked_characters,
      tracked_char_ids: tracked_char_ids,
      victim_tracked: victim_tracked,
      tracked_attackers: tracked_attackers,
      is_system_tracked: is_system_tracked,
      is_character_tracked: is_character_tracked
    }
  end

  # Check if the victim is among tracked characters
  defp check_if_victim_tracked(nil, _), do: false

  defp check_if_victim_tracked(victim_id_str, tracked_char_ids) do
    # Downgrade to debug level - happens for every kill
    AppLogger.kill_debug(
      "VICTIM TRACKING CHECK: Checking victim ID #{victim_id_str} against #{MapSet.size(tracked_char_ids)} tracked character IDs"
    )

    # Check if the victim ID is in our tracked characters set
    victim_in_set = MapSet.member?(tracked_char_ids, victim_id_str)

    # Only log at info level if victim is actually tracked
    if victim_in_set do
      AppLogger.kill_info("VICTIM ID MATCH: Victim #{victim_id_str} is tracked")
    end

    victim_in_set
  end

  # Find tracked attackers from attacker IDs
  defp find_tracked_attackers(attacker_ids_str, tracked_char_ids) do
    tracked_attackers =
      attacker_ids_str
      |> MapSet.new()
      |> MapSet.intersection(tracked_char_ids)
      |> MapSet.to_list()

    # Log if tracked attackers are found
    if length(tracked_attackers) > 0 do
      AppLogger.kill_debug(
        "ATTACKER TRACKING: Found #{length(tracked_attackers)} tracked attackers: #{inspect(tracked_attackers)}"
      )
    end

    tracked_attackers
  end

  # Log attacker matching information with reduced verbosity
  defp log_attacker_matching(attacker_ids_str, tracked_char_ids, kill_id) do
    if length(attacker_ids_str) > 0 do
      # Downgrade to debug level - this happens on every kill
      AppLogger.kill_debug(
        "ATTACKER MATCHING: Checking #{length(attacker_ids_str)} attackers against #{MapSet.size(tracked_char_ids)} tracked characters"
      )

      # Only log matches now, not each check - significantly reduces logs
      matched_attackers =
        attacker_ids_str
        |> Enum.filter(fn attacker_id -> MapSet.member?(tracked_char_ids, attacker_id) end)

      # Only log if we found matches
      if length(matched_attackers) > 0 do
        AppLogger.kill_info(
          "ATTACKER MATCH: Found #{length(matched_attackers)} tracked attackers in kill #{kill_id}: #{inspect(matched_attackers)}"
        )
      end
    end
  end

  # Log tracking status information
  defp log_tracking_status(tracking_info, kill_info) do
    # Use batch logger for kill received events
    BatchLogger.count_event(:kill_received, %{
      kill_id: kill_info.kill_id,
      system_id: kill_info.system_id,
      system_name: kill_info.system_name
    })

    # Log debug tracking information
    AppLogger.kill_debug(
      "TRACKING STATUS: #{length(tracking_info.tracked_systems)} systems and " <>
        "#{length(tracking_info.tracked_characters)} characters tracked"
    )

    # Log victim tracking if applicable
    if tracking_info.victim_tracked do
      AppLogger.kill_info("VICTIM TRACKING: Victim is tracked")
    end

    # Log tracked systems details if available
    log_tracked_systems_details(tracking_info.tracked_systems)

    # Log the tracking status for this specific kill
    AppLogger.kill_debug(
      "📊 KILL TRACKING: ID=#{kill_info.kill_id}, " <>
        "system_tracked=#{tracking_info.is_system_tracked}, " <>
        "character_tracked=#{tracking_info.is_character_tracked}"
    )
  end

  # Log details about tracked systems
  defp log_tracked_systems_details(tracked_systems) do
    if length(tracked_systems) > 0 do
      system_ids_with_names =
        Enum.map(tracked_systems, fn system ->
          extract_system_id_and_name(system)
        end)

      AppLogger.kill_debug("TRACKED SYSTEMS: #{inspect(system_ids_with_names)}")
    end
  end

  # Extract system ID and name from system data
  defp extract_system_id_and_name(system) do
    system_id =
      cond do
        is_map(system) && Map.has_key?(system, "solar_system_id") ->
          system["solar_system_id"]

        is_map(system) && Map.has_key?(system, :solar_system_id) ->
          system.solar_system_id

        true ->
          system
      end

    system_name = get_system_name(system_id)
    if system_name, do: "#{system_id} (#{system_name})", else: system_id
  end

  # Handle notification decision logic
  defp handle_notification_decision(killmail, kill_info, tracking_info) do
    if NotificationDeterminer.should_notify_kill?(
         killmail,
         kill_info.system_id
       ) do
      # Determine and log notification reason
      notification_reason =
        determine_notification_reason(
          tracking_info.is_system_tracked,
          tracking_info.is_character_tracked,
          tracking_info.victim_tracked,
          tracking_info.tracked_attackers,
          kill_info
        )

      AppLogger.kill_debug(
        "✅ NOTIFICATION DECISION: Kill #{kill_info.kill_id} in #{kill_info.system_info} - " <>
          "sending notification because #{notification_reason}"
      )

      # Get enriched killmail and send notification
      enriched_killmail = enrich_killmail_data(killmail)
      send_kill_notification(enriched_killmail, kill_info.kill_id)

      AppLogger.kill_info(
        "📢 NOTIFICATION SENT: Killmail #{kill_info.kill_id} notification delivered successfully"
      )

      :ok
    else
      # Log why notification was skipped
      reason =
        determine_skip_reason(
          tracking_info.is_system_tracked,
          tracking_info.is_character_tracked
        )

      AppLogger.kill_debug(
        "❌ NOTIFICATION SKIPPED: Kill #{kill_info.kill_id} in #{kill_info.system_info} filtered out - #{reason}"
      )

      :ok
    end
  end

  # Determine the reason for sending notification
  defp determine_notification_reason(
         is_system_tracked,
         is_character_tracked,
         victim_tracked,
         tracked_attackers,
         kill_info
       ) do
    cond do
      is_system_tracked && is_character_tracked ->
        "both system and character are tracked"

      is_system_tracked ->
        "system #{kill_info.system_info} is tracked"

      is_character_tracked && victim_tracked ->
        "victim is tracked"

      is_character_tracked && length(tracked_attackers) > 0 ->
        "attacker(s) #{inspect(tracked_attackers)} are tracked"

      true ->
        "matched tracking criteria"
    end
  end

  # Determine reason for skipping notification
  defp determine_skip_reason(is_system_tracked, is_character_tracked) do
    cond do
      !Features.kill_notifications_enabled?() ->
        "kill notifications are globally disabled"

      !is_system_tracked && !is_character_tracked ->
        "neither system nor any characters are tracked"

      true ->
        "unknown reason - check notification determiner"
    end
  end

  defp update_recent_kills(%Killmail{} = killmail) do
    # Add enhanced logging to trace cache updates
    AppLogger.kill_debug("Storing Killmail struct in shared cache repository")

    kill_id = killmail.killmail_id

    # Store the individual kill by ID
    individual_key = "#{@recent_kills_cache_key}:#{kill_id}"

    # Store the Killmail struct directly - no need to convert again
    CacheRepo.set(individual_key, killmail, @kill_ttl)

    # Now update the list of recent kill IDs
    update_recent_kill_ids(kill_id)

    AppLogger.kill_debug("Stored kill #{kill_id} in shared cache repository")
    :ok
  end

  # Update the list of recent kill IDs in the cache
  defp update_recent_kill_ids(new_kill_id) do
    # Get current list of kill IDs from the cache
    kill_ids = CacheRepo.get(@recent_kills_cache_key) || []

    # Add the new ID to the front
    updated_ids =
      [new_kill_id | kill_ids]
      # Remove duplicates
      |> Enum.uniq()
      # Keep only the most recent ones
      |> Enum.take(@max_recent_kills)

    # Update the cache
    CacheRepo.set(@recent_kills_cache_key, updated_ids, @kill_ttl)

    AppLogger.kill_debug("Updated recent kill IDs in cache - now has #{length(updated_ids)} IDs")
  end

  # Extract system ID from killmail
  defp get_system_id_from_killmail(%Killmail{} = killmail) do
    # Use the Killmail module's helper
    system_id = Killmail.get_system_id(killmail)
    system_id
  end

  defp get_system_id_from_killmail(_), do: nil

  # Send the notification for a kill
  defp send_kill_notification(enriched_killmail, kill_id, is_test \\ false) do
    # Add detailed logging for kill notification
    AppLogger.kill_info(
      "📝 NOTIFICATION PREP: Preparing to send notification for killmail #{kill_id}" <>
        if(is_test, do: " (TEST NOTIFICATION)", else: "")
    )

    # For test notifications, bypass deduplication check
    if is_test do
      AppLogger.kill_info(
        "✅ TEST KILL: Sending test notification for killmail #{kill_id}, bypassing deduplication"
      )

      DiscordNotifier.send_enriched_kill_embed(enriched_killmail, kill_id)

      # Update statistics for notification sent
      update_kill_stats(:notification_sent)

      # Log the notification for tracking purposes
      AppLogger.kill_info(
        "📢 TEST NOTIFICATION SENT: Killmail #{kill_id} test notification delivered successfully"
      )

      :ok
    else
      # Use the centralized deduplication check for normal notifications
      case NotificationDeterminer.check_deduplication(:kill, kill_id) do
        {:ok, :send} ->
          # This is not a duplicate, send the notification
          AppLogger.kill_info("✅ NEW KILL: Sending notification for killmail #{kill_id}")
          DiscordNotifier.send_enriched_kill_embed(enriched_killmail, kill_id)

          # Update statistics for notification sent
          update_kill_stats(:notification_sent)

          # Use batch logger for notification tracking
          BatchLogger.count_event(:notification_sent, %{
            type: :kill,
            id: kill_id
          })

          # Log the notification for tracking purposes (but less verbose)
          AppLogger.kill_debug(
            "📢 NOTIFICATION SENT: Killmail #{kill_id} notification delivered successfully"
          )

        {:ok, :skip} ->
          # This is a duplicate, skip the notification
          AppLogger.kill_info(
            "🔄 DUPLICATE KILL: Killmail #{kill_id} notification already sent, skipping"
          )

          :ok

        {:error, reason} ->
          # Error during deduplication check, log it
          AppLogger.kill_error(
            "⚠️ DEDUPLICATION ERROR: Failed to check killmail #{kill_id}: #{reason}"
          )

          # Default to sending the notification in case of errors
          AppLogger.kill_info("⚠️ FALLBACK: Sending notification despite deduplication error")
          DiscordNotifier.send_enriched_kill_embed(enriched_killmail, kill_id)
          :ok
      end
    end
  end

  @doc """
  Returns the list of recent kills from the shared cache repository.
  """
  def get_recent_kills do
    AppLogger.kill_debug("Retrieving recent kills from shared cache repository")

    # First get the list of recent kill IDs
    kill_ids = CacheRepo.get(@recent_kills_cache_key) || []
    AppLogger.kill_debug("Found #{length(kill_ids)} recent kill IDs in cache")

    # Then fetch each kill by its ID
    recent_kills =
      Enum.map(kill_ids, fn id ->
        key = "#{@recent_kills_cache_key}:#{id}"
        kill_data = CacheRepo.get(key)

        if kill_data do
          # Log successful retrieval
          AppLogger.kill_debug("Successfully retrieved kill #{id} from cache")
          kill_data
        else
          # Log cache miss
          AppLogger.kill_warning("Failed to retrieve kill #{id} from cache (expired or missing)")
          nil
        end
      end)
      # Remove any nils from the list
      |> Enum.filter(&(&1 != nil))

    AppLogger.kill_debug("Retrieved #{length(recent_kills)} cached kills from shared repository")

    recent_kills
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test_kill_notification do
    AppLogger.kill_info("Sending test kill notification...")

    # Get recent kills
    recent_kills = get_recent_kills()
    AppLogger.kill_debug("Found #{length(recent_kills)} recent kills in shared cache repository")

    if recent_kills == [] do
      error_message = "No recent kills available for test notification"
      AppLogger.kill_error(error_message)

      # Notify the user through Discord
      NotifierFactory.notify(
        :send_message,
        [
          "Error: #{error_message} - No test notification sent. Please wait for some kills to be processed."
        ]
      )

      {:error, error_message}
    else
      # Get the first kill - should already be a Killmail struct
      %Killmail{} = recent_kill = List.first(recent_kills)
      kill_id = recent_kill.killmail_id

      # Log what we're using for testing
      AppLogger.kill_debug("Using kill data for test notification with kill_id: #{kill_id}")

      # Make sure to enrich the killmail data before sending notification
      # This will try to get real data from APIs first
      enriched_kill = enrich_killmail_data(recent_kill)

      # Log the enriched data to help debug
      victim = Killmail.get_victim(enriched_kill)
      AppLogger.kill_info("TEST NOTIFICATION: Enriched victim data: #{inspect(victim)}")

      # Validate essential data is present - fail if not
      case validate_killmail_data(enriched_kill) do
        :ok ->
          # Use the normal notification flow but bypass deduplication
          AppLogger.kill_info(
            "TEST NOTIFICATION: Using normal notification flow for test kill notification"
          )

          send_kill_notification(enriched_kill, kill_id, true)
          {:ok, kill_id}

        {:error, reason} ->
          # Data validation failed, return error
          error_message = "Cannot send test notification: #{reason}"
          AppLogger.kill_error(error_message)

          # Notify the user through Discord
          NotifierFactory.notify(
            :send_message,
            [error_message]
          )

          {:error, error_message}
      end
    end
  end

  # Validate killmail has all required data for notification
  defp validate_killmail_data(%Killmail{} = killmail) do
    # Check victim data
    victim = Killmail.get_victim(killmail)

    # Check system name
    esi_data = killmail.esi_data || %{}
    system_name = Map.get(esi_data, "solar_system_name")

    cond do
      victim == nil ->
        {:error, "Killmail is missing victim data"}

      Map.get(victim, "character_name") == nil ->
        {:error, "Victim is missing character name"}

      Map.get(victim, "ship_type_name") == nil ->
        {:error, "Victim is missing ship type name"}

      system_name == nil ->
        {:error, "Killmail is missing system name"}

      true ->
        :ok
    end
  end

  # Helper function to extract the killmail ID from different possible structures
  defp get_killmail_id(kill_data) when is_map(kill_data) do
    # Based on the standard zKillboard websocket format, the killmail_id should be directly
    # available as a field named "killmail_id". If not, try to extract from the zkb data.
    kill_data["killmail_id"] ||
      (kill_data["zkb"] && kill_data["zkb"]["killID"])
  end

  defp get_killmail_id(_), do: nil

  # Enrich the killmail data with additional information needed for notifications
  defp enrich_killmail_data(%Killmail{} = killmail) do
    %Killmail{esi_data: esi_data} = killmail

    # Enrich with system name if needed
    esi_data = enrich_with_system_name(esi_data)

    # Log for debugging
    AppLogger.kill_debug(
      "[KillProcessor] System name after enrichment: #{Map.get(esi_data, "solar_system_name", "Not found")}"
    )

    # Enrich victim data if available
    esi_data =
      if Map.has_key?(esi_data, "victim") do
        victim = Map.get(esi_data, "victim")
        enriched_victim = enrich_entity(victim)
        Map.put(esi_data, "victim", enriched_victim)
      else
        # Log and continue without adding placeholder
        AppLogger.kill_warning("[KillProcessor] Missing victim data in killmail")
        esi_data
      end

    # Enrich attackers if available
    esi_data =
      if Map.has_key?(esi_data, "attackers") do
        attackers = Map.get(esi_data, "attackers", [])
        enriched_attackers = Enum.map(attackers, &enrich_entity/1)
        Map.put(esi_data, "attackers", enriched_attackers)
      else
        # Log and continue without adding placeholder
        AppLogger.kill_warning("[KillProcessor] Missing attackers data in killmail")
        esi_data
      end

    # Return updated killmail with enriched ESI data
    %Killmail{killmail | esi_data: esi_data}
  end

  # Enrich entity (victim or attacker) with additional information
  defp enrich_entity(entity) when is_map(entity) do
    entity
    |> add_character_name()
    |> add_corporation_name()
    |> add_alliance_name()
    |> add_ship_name()
  end

  defp enrich_entity(entity), do: entity

  # Add character name if missing
  defp add_character_name(entity) do
    add_entity_info(
      entity,
      "character_id",
      "character_name",
      &ESIService.get_character_info/1,
      "Unknown Pilot"
    )
  end

  # Add corporation name if missing
  defp add_corporation_name(entity) do
    add_entity_info(
      entity,
      "corporation_id",
      "corporation_name",
      &ESIService.get_corporation_info/1,
      "Unknown Corp"
    )
  end

  # Add alliance name if missing
  defp add_alliance_name(entity) do
    add_entity_info(
      entity,
      "alliance_id",
      "alliance_name",
      &ESIService.get_alliance_info/1,
      "Unknown Alliance"
    )
  end

  # Add ship name if missing
  defp add_ship_name(entity) do
    add_entity_info(
      entity,
      "ship_type_id",
      "ship_type_name",
      &ESIService.get_ship_type_name/1,
      "Unknown Ship"
    )
  end

  # Generic function to add entity information if missing
  defp add_entity_info(entity, id_key, name_key, fetch_fn, default_name) do
    if Map.has_key?(entity, id_key) && !Map.has_key?(entity, name_key) do
      id = Map.get(entity, id_key)
      name = fetch_entity_name(id, fetch_fn, default_name)
      Map.put(entity, name_key, name)
    else
      entity
    end
  end

  # Fetch entity name from ESI API
  defp fetch_entity_name(id, fetch_fn, default_name) do
    case fetch_fn.(id) do
      {:ok, info} -> Map.get(info, "name", default_name)
      _ -> default_name
    end
  end

  # Add system name to ESI data if missing
  defp enrich_with_system_name(esi_data) when is_map(esi_data) do
    # Already has a system name, no need to add it
    if Map.has_key?(esi_data, "solar_system_name") do
      esi_data
    else
      add_system_name_to_data(esi_data)
    end
  end

  defp enrich_with_system_name(data), do: data

  # Helper to add system name if system_id exists
  defp add_system_name_to_data(esi_data) do
    system_id = Map.get(esi_data, "solar_system_id")

    # No system ID, return original data
    if is_nil(system_id) do
      AppLogger.kill_warning("[KillProcessor] No system ID available in killmail data")
      esi_data
    else
      # Get system name and add it if found
      system_name = get_system_name(system_id)
      add_system_name_if_found(esi_data, system_id, system_name)
    end
  end

  # Add system name to data if found
  defp add_system_name_if_found(esi_data, system_id, nil) do
    AppLogger.kill_debug("[KillProcessor] No system name found for ID #{system_id}")
    esi_data
  end

  defp add_system_name_if_found(esi_data, _system_id, system_name) do
    Map.put(esi_data, "solar_system_name", system_name)
  end

  # Helper function to get system name with caching
  defp get_system_name(nil), do: nil

  defp get_system_name(system_id) do
    # Check the local process cache first
    cache = Process.get(@system_names_cache_key) || %{}

    case Map.get(cache, system_id) do
      nil ->
        # Not in cache, fetch from ESI
        system_name =
          case ESIService.get_system_info(system_id) do
            {:ok, system_info} ->
              Map.get(system_info, "name")

            {:error, :not_found} ->
              AppLogger.kill_warning(
                "System ID #{system_id} not found in ESI. This may be a J-space system or invalid data."
              )

              nil

            error ->
              AppLogger.kill_error(
                "Failed to fetch system name for ID #{system_id}: #{inspect(error)}"
              )

              nil
          end

        # Update cache if we got a name
        if system_name do
          updated_cache = Map.put(cache, system_id, system_name)
          Process.put(@system_names_cache_key, updated_cache)
        end

        system_name

      system_name ->
        # Return from cache
        system_name
    end
  end

  # Helper function to diagnose tracking issues for a specific system ID
  defp debug_system_tracking(system_id) do
    system_id_str = to_string(system_id)
    system_info = get_system_info_string(system_id)
    tracked_systems = CacheHelpers.get_tracked_systems()

    # Log basic information
    log_basic_tracking_info(system_info, tracked_systems)

    # Check using standard method
    standard_check = NotificationDeterminer.tracked_system?(system_id)

    # Check using manual matching
    {found, matches} = find_matching_systems(tracked_systems, system_id_str)

    # Log match results
    log_match_results(found, matches, tracked_systems)

    # Check direct cache lookup
    direct_result = check_direct_cache_lookup(system_id_str)

    # Return the results
    %{
      system_id: system_id,
      standard_check: standard_check,
      manual_check: found,
      matches: matches,
      direct_lookup: direct_result != nil
    }
  end

  # Get formatted system info string for logging
  defp get_system_info_string(system_id) do
    system_name = get_system_name(system_id)
    if system_name, do: "#{system_id} (#{system_name})", else: system_id
  end

  # Log basic information about the tracking check
  defp log_basic_tracking_info(system_info, tracked_systems) do
    AppLogger.kill_debug("DEBUG: Checking tracking for system #{system_info}")
    AppLogger.kill_debug("DEBUG: Found #{length(tracked_systems)} tracked systems")
  end

  # Check for system matches using various key formats
  defp find_matching_systems(tracked_systems, system_id_str) do
    matches = Enum.filter(tracked_systems, &system_matches?(&1, system_id_str))
    {length(matches) > 0, matches}
  end

  # Check if a system entry matches the target system ID
  defp system_matches?(system, system_id_str) do
    cond do
      # Match with solar_system_id (atom key)
      match_system_field?(system, :solar_system_id, system_id_str) ->
        log_match("solar_system_id (atom key)", Map.get(system, :solar_system_id))
        true

      # Match with solar_system_id (string key)
      match_system_field?(system, "solar_system_id", system_id_str) ->
        log_match("solar_system_id (string key)", Map.get(system, "solar_system_id"))
        true

      # Match with system_id (atom key)
      match_system_field?(system, :system_id, system_id_str) ->
        log_match("system_id (atom key)", Map.get(system, :system_id))
        true

      # Match with system_id (string key)
      match_system_field?(system, "system_id", system_id_str) ->
        log_match("system_id (string key)", Map.get(system, "system_id"))
        true

      # Match with direct ID value
      id_match?(system, system_id_str) ->
        log_match("direct ID value", system)
        true

      # No match
      true ->
        false
    end
  end

  # Check if a specific field in a map matches the target ID
  defp match_system_field?(system, field, target_id_str) when is_map(system) do
    if Map.has_key?(system, field) do
      id = Map.get(system, field)
      id != nil && to_string(id) == target_id_str
    else
      false
    end
  end

  # Check if a direct ID matches the target ID
  defp match_system_field?(_, _, _), do: false

  # Check if a value is a direct ID match
  defp id_match?(id, target_id_str) when is_integer(id) or is_binary(id) do
    to_string(id) == target_id_str
  end

  defp id_match?(_, _), do: false

  # Log when a match is found
  defp log_match(match_type, id) do
    AppLogger.kill_debug("DEBUG: Found match with #{match_type}: #{id}")
  end

  # Log results of the matching process
  defp log_match_results(found, matches, tracked_systems) do
    if found do
      AppLogger.kill_debug("DEBUG: Found #{length(matches)} matches in tracked systems")
    else
      # If no match found, log the first few systems for debugging
      sample = Enum.take(tracked_systems, min(3, length(tracked_systems)))

      AppLogger.kill_debug(
        "DEBUG: No match found. Sample tracked system structures: #{inspect(sample)}"
      )
    end
  end

  # Check for the system in direct cache lookup
  defp check_direct_cache_lookup(system_id_str) do
    direct_system = CacheRepo.get("map:system:#{system_id_str}")

    if direct_system != nil do
      AppLogger.kill_debug(
        "DEBUG: Found system in direct cache lookup: #{inspect(direct_system)}"
      )
    else
      AppLogger.kill_debug("DEBUG: System not found in direct cache lookup")
    end

    direct_system
  end

  # Public function to trigger special debug for a specific system
  def debug_special_system(system_id) do
    # Convert to integer if possible
    system_id =
      case system_id do
        id when is_binary(id) ->
          case Integer.parse(id) do
            {int_id, ""} -> int_id
            _ -> id
          end

        id ->
          id
      end

    AppLogger.kill_info("Triggering special debug for system ID: #{system_id}")
    # Send the message to the main Service module
    Process.send(Service, {:debug_special_system, system_id}, [])
  end

  # Extract character ID from character data
  defp extract_character_id(char) do
    cond do
      # Handle the Character struct directly
      is_struct(char, Character) ->
        to_string(char.character_id)

      is_map(char) ->
        extract_id_from_map(char)

      is_binary(char) || is_integer(char) ->
        to_string(char)

      true ->
        AppLogger.kill_error(
          "ERROR: Unexpected data type in extract_character_id: #{inspect(char)}"
        )

        nil
    end
  end

  # Helper to extract ID from map with various possible keys
  defp extract_id_from_map(char) do
    # Try each possible key format in order of preference
    character_id_atom = get_value_if_exists(char, :character_id)
    character_id_string = get_value_if_exists(char, "character_id")
    id_atom = get_value_if_exists(char, :id)
    id_string = get_value_if_exists(char, "id")

    # Return the first non-nil value found
    character_id_atom || character_id_string || id_atom || id_string || nil
  end

  # Helper to safely get and convert a value if the key exists and value isn't nil
  defp get_value_if_exists(map, key) do
    if Map.has_key?(map, key) && !is_nil(Map.get(map, key)) do
      to_string(Map.get(map, key))
    else
      nil
    end
  end
end
