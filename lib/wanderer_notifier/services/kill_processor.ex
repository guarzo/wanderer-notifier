defmodule WandererNotifier.Services.KillProcessor do
  @moduledoc """
  Kill processor for WandererNotifier.
  Handles processing kill messages from zKill, including enrichment
  and deciding on notification based on tracked systems or characters.
  """
  require Logger

  # Cache keys for recent kills
  @recent_kills_key "zkill:recent_kills"
  @max_recent_kills 10
  # 1 hour TTL for cached kills
  @kill_ttl 3600

  # Add stats for tracking received kills during this session
  @kill_stats_key :kill_processor_stats

  # Cache for system names to avoid repeated API calls
  @system_names_cache_key :system_names_cache

  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Killmail

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
    Process.send_after(WandererNotifier.Service, :log_kill_stats, 5 * 60 * 1000)
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
    Logger.debug("Processing raw message from WebSocket")

    case Jason.decode(message) do
      {:ok, decoded_message} ->
        process_zkill_message(decoded_message, state)

      {:error, reason} ->
        Logger.error("Failed to decode zKill message: #{inspect(reason)}")
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
        Logger.debug("Ignoring unknown zKill message type")
        state
    end
  end

  defp handle_tq_status(%{"tqStatus" => %{"players" => player_count, "vip" => vip}}) do
    # Store in process dictionary for now, we could use the state or a separate GenServer later
    Process.put(:tq_status, %{
      players: player_count,
      vip: vip,
      updated_at: :os.system_time(:second)
    })

    Logger.debug("TQ Status: #{player_count} players online, VIP: #{vip}")
  end

  defp handle_tq_status(_) do
    Logger.warning("Received malformed TQ status message")
  end

  defp handle_killmail(killmail, state) do
    # Extract the kill ID
    kill_id = get_killmail_id(killmail)
    Logger.debug("Extracted killmail_id: #{inspect(kill_id)}")

    # Skip processing if no kill ID or already processed
    cond do
      is_nil(kill_id) ->
        Logger.warning("Received killmail without kill ID")
        state

      Map.has_key?(state.processed_kill_ids, kill_id) ->
        Logger.debug("Kill #{kill_id} already processed, skipping")
        state

      true ->
        # Process the new kill - first standardize to Killmail struct
        Logger.debug("Processing new kill #{kill_id}")

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

    # Process the kill for notification (removed check for backup_kills_processing)
    case enrich_and_notify(killmail) do
      :ok ->
        # Mark kill as processed in state
        Map.update(state, :processed_kill_ids, %{kill_id => :os.system_time(:second)}, fn ids ->
          Map.put(ids, kill_id, :os.system_time(:second))
        end)

      {:error, reason} ->
        Logger.error("Error processing kill #{kill_id}: #{reason}")
        state
    end
  end

  # Simplified to remove validate_killmail since we're now using the Killmail struct properly
  defp enrich_and_notify(%Killmail{} = killmail) do
    try do
      # Get the kill details for better logging
      kill_id = killmail.killmail_id

      # Get the system ID from the killmail
      system_id = get_system_id_from_killmail(killmail)

      # Get system name for better logging
      system_name = get_system_name(system_id)
      system_info = if system_name, do: "#{system_id} (#{system_name})", else: system_id

      # Debug tracking for this specific system
      debug_system_tracking(system_id)

      # Extract victim info if available for better logging
      victim_id = get_in(killmail.esi_data || %{}, ["victim", "character_id"])
      victim_ship_id = get_in(killmail.esi_data || %{}, ["victim", "ship_type_id"])

      Logger.debug(
        "VICTIM ID EXTRACT: Using character_id #{victim_id} from killmail, will match against eve_id in tracked characters"
      )

      # Extract attacker info if available
      attackers = get_in(killmail.esi_data || %{}, ["attackers"]) || []

      attacker_ids =
        attackers
        |> Enum.map(& &1["character_id"])
        |> Enum.reject(&is_nil/1)

      Logger.info(
        "📥 KILL RECEIVED: ID=#{kill_id} in system=#{system_info}, victim_id=#{victim_id}, victim_ship=#{victim_ship_id}, attackers=#{Enum.count(attackers)}"
      )

      # Log more details about attackers for debugging
      if length(attacker_ids) > 0 do
        Logger.debug(
          "ATTACKER DEBUG: Kill #{kill_id} has #{length(attacker_ids)} attackers with character IDs"
        )

        Enum.each(attacker_ids, fn attacker_id ->
          Logger.debug("ATTACKER DEBUG: Attacker ID: #{attacker_id} in kill #{kill_id}")
        end)
      end

      # Get counts of tracked systems and characters for debugging
      tracked_systems = WandererNotifier.Helpers.CacheHelpers.get_tracked_systems()
      tracked_characters = WandererNotifier.Helpers.CacheHelpers.get_tracked_characters()

      # Convert tracked character IDs to strings for easier comparison
      tracked_char_ids =
        tracked_characters
        |> Enum.map(fn char ->
          case char do
            %{eve_id: id} when not is_nil(id) -> to_string(id)
            %{"eve_id" => id} when not is_nil(id) -> to_string(id)
            _ -> nil
          end
        end)
        |> Enum.filter(&(&1 != nil))
        |> MapSet.new()

      # Log some tracked character IDs for debugging
      sample_tracked_ids =
        MapSet.to_list(tracked_char_ids) |> Enum.take(min(5, MapSet.size(tracked_char_ids)))

      Logger.info(
        "TRACKING DEBUG: Using #{MapSet.size(tracked_char_ids)} character IDs from eve_id field. Sample: #{inspect(sample_tracked_ids)}"
      )

      # Check if victim is tracked
      victim_id_str = if victim_id, do: to_string(victim_id), else: nil

      # Log more detailed information about the victim tracking check
      if victim_id_str do
        Logger.info(
          "VICTIM TRACKING CHECK: Checking victim ID #{victim_id_str} against #{MapSet.size(tracked_char_ids)} tracked character eve_ids"
        )

        # Check if the victim ID is in our tracked characters set
        victim_in_set = MapSet.member?(tracked_char_ids, victim_id_str)
        Logger.info("VICTIM ID MATCH RESULT: #{victim_in_set}")
      end

      victim_tracked = victim_id_str && MapSet.member?(tracked_char_ids, victim_id_str)

      # Check which attackers are tracked - convert to strings first to ensure consistent comparison
      attacker_ids_str = Enum.map(attacker_ids, &to_string/1)

      tracked_attackers =
        attacker_ids_str
        |> MapSet.new()
        |> MapSet.intersection(tracked_char_ids)
        |> MapSet.to_list()

      # Enhanced logging for attacker checking
      if length(attacker_ids_str) > 0 do
        Logger.info(
          "ATTACKER MATCHING: Checking #{length(attacker_ids_str)} attackers against #{MapSet.size(tracked_char_ids)} tracked characters"
        )

        # Log each attacker ID for better tracking
        Enum.each(attacker_ids_str, fn attacker_id ->
          is_tracked = MapSet.member?(tracked_char_ids, attacker_id)

          if is_tracked do
            Logger.info("ATTACKER MATCH: Attacker #{attacker_id} in kill #{kill_id} IS TRACKED ✓")
          else
            Logger.debug(
              "ATTACKER MATCH: Attacker #{attacker_id} in kill #{kill_id} is not tracked"
            )
          end
        end)
      end

      Logger.debug(
        "TRACKING STATUS: #{length(tracked_systems)} systems and #{length(tracked_characters)} characters tracked"
      )

      # Log detailed character tracking information
      if victim_tracked do
        Logger.info("VICTIM TRACKING: Victim #{victim_id_str} is tracked")
      end

      if length(tracked_attackers) > 0 do
        Logger.debug(
          "ATTACKER TRACKING: Found #{length(tracked_attackers)} tracked attackers: #{inspect(tracked_attackers)}"
        )
      end

      # Log the specific systems being tracked for easier debugging
      if length(tracked_systems) > 0 do
        system_ids_with_names =
          Enum.map(tracked_systems, fn system ->
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
          end)

        Logger.debug("TRACKED SYSTEMS: #{inspect(system_ids_with_names)}")
      end

      # Check if system is tracked
      is_system_tracked =
        WandererNotifier.Services.NotificationDeterminer.tracked_system?(system_id)

      # Check if any character is tracked
      is_character_tracked =
        WandererNotifier.Services.NotificationDeterminer.has_tracked_character?(killmail)

      # Log the tracking status for this specific kill
      Logger.debug(
        "📊 KILL TRACKING: ID=#{kill_id}, system_tracked=#{is_system_tracked}, character_tracked=#{is_character_tracked}"
      )

      # Determine if this kill should trigger a notification
      if WandererNotifier.Services.NotificationDeterminer.should_notify_kill?(killmail, system_id) do
        # Log the specific reason for notification
        notification_reason =
          cond do
            is_system_tracked && is_character_tracked ->
              "both system and character are tracked"

            is_system_tracked ->
              "system #{system_info} is tracked"

            is_character_tracked && victim_tracked ->
              "victim #{victim_id_str} is tracked"

            is_character_tracked && length(tracked_attackers) > 0 ->
              "attacker(s) #{inspect(tracked_attackers)} are tracked"

            true ->
              "matched tracking criteria"
          end

        Logger.debug(
          "✅ NOTIFICATION DECISION: Kill #{kill_id} in #{system_info} - sending notification because #{notification_reason}"
        )

        # Get the enriched killmail data
        enriched_killmail = enrich_killmail_data(killmail)

        # Send the notification
        send_kill_notification(enriched_killmail, kill_id)

        Logger.info(
          "📢 NOTIFICATION SENT: Killmail #{kill_id} notification delivered successfully"
        )

        :ok
      else
        # Log detailed information about why the kill was filtered out
        reason =
          cond do
            !WandererNotifier.Core.Features.kill_notifications_enabled?() ->
              "kill notifications are globally disabled"

            !is_system_tracked && !is_character_tracked ->
              "neither system nor any characters are tracked"

            true ->
              "unknown reason - check notification determiner"
          end

        Logger.debug(
          "❌ NOTIFICATION SKIPPED: Kill #{kill_id} in #{system_info} filtered out - #{reason}"
        )

        :ok
      end
    rescue
      e ->
        Logger.error("⚠️ EXCEPTION: Error during kill enrichment: #{Exception.message(e)}")
        {:error, "Failed to enrich kill: #{Exception.message(e)}"}
    end
  end

  defp update_recent_kills(%Killmail{} = killmail) do
    # Add enhanced logging to trace cache updates
    Logger.debug("Storing Killmail struct in shared cache repository")

    kill_id = killmail.killmail_id

    # Store the individual kill by ID
    individual_key = "#{@recent_kills_key}:#{kill_id}"

    # Store the Killmail struct directly - no need to convert again
    CacheRepo.set(individual_key, killmail, @kill_ttl)

    # Now update the list of recent kill IDs
    update_recent_kill_ids(kill_id)

    Logger.debug("Stored kill #{kill_id} in shared cache repository")
    :ok
  end

  # Update the list of recent kill IDs in the cache
  defp update_recent_kill_ids(new_kill_id) do
    # Get current list of kill IDs from the cache
    kill_ids = CacheRepo.get(@recent_kills_key) || []

    # Add the new ID to the front
    updated_ids =
      [new_kill_id | kill_ids]
      # Remove duplicates
      |> Enum.uniq()
      # Keep only the most recent ones
      |> Enum.take(@max_recent_kills)

    # Update the cache
    CacheRepo.set(@recent_kills_key, updated_ids, @kill_ttl)

    Logger.debug("Updated recent kill IDs in cache - now has #{length(updated_ids)} IDs")
  end

  # Extract system ID from killmail
  defp get_system_id_from_killmail(%Killmail{} = killmail) do
    # Use the Killmail module's helper
    system_id = Killmail.get_system_id(killmail)

    # Special debug for DAYP-G system (30000253)
    if system_id == 30_000_253 or system_id == "30000253" do
      Logger.info("SPECIAL DEBUG: Found DAYP-G system ID: #{system_id}")

      # Force the service to debug tracked systems
      WandererNotifier.Services.Service.debug_tracked_systems()

      # Test a manual notification for this system
      handle_dayp_test_notification(killmail, system_id)
    end

    system_id
  end

  defp get_system_id_from_killmail(_), do: nil

  # Special handler for DAYP-G system notifications for debugging
  defp handle_dayp_test_notification(killmail, system_id) do
    try do
      # Get system name
      system_name = get_system_name(system_id)
      system_info = if system_name, do: "#{system_id} (#{system_name})", else: system_id

      # Log the special case
      Logger.info(
        "DAYP-G TEST: Attempting to manually send notification for kill in #{system_info}"
      )

      # Get the enriched killmail data
      enriched_killmail = enrich_killmail_data(killmail)

      # Force a notification
      kill_id = killmail.killmail_id

      # Send the notification
      WandererNotifier.Discord.Notifier.send_enriched_kill_embed(enriched_killmail, kill_id)

      Logger.info("DAYP-G TEST: Manually sent notification for kill #{kill_id} in #{system_info}")

      # Update stats
      update_kill_stats(:notification_sent)

      :ok
    rescue
      e ->
        Logger.error(
          "DAYP-G TEST ERROR: Failed to send manual notification: #{Exception.message(e)}"
        )

        {:error, Exception.message(e)}
    end
  end

  # Send the notification for a kill
  defp send_kill_notification(enriched_killmail, kill_id) do
    # Add detailed logging for kill notification
    Logger.info("📝 NOTIFICATION PREP: Preparing to send notification for killmail #{kill_id}")

    # Use the centralized deduplication check
    case WandererNotifier.Services.NotificationDeterminer.check_deduplication(:kill, kill_id) do
      {:ok, :send} ->
        # This is not a duplicate, send the notification
        Logger.info("✅ NEW KILL: Sending notification for killmail #{kill_id}")
        WandererNotifier.Discord.Notifier.send_enriched_kill_embed(enriched_killmail, kill_id)

        # Update statistics for notification sent
        update_kill_stats(:notification_sent)

        # Log the notification for tracking purposes
        Logger.info(
          "📢 NOTIFICATION SENT: Killmail #{kill_id} notification delivered successfully"
        )

      {:ok, :skip} ->
        # This is a duplicate, skip the notification
        Logger.info("🔄 DUPLICATE KILL: Killmail #{kill_id} notification already sent, skipping")
        :ok

      {:error, reason} ->
        # Error during deduplication check, log it
        Logger.error("⚠️ DEDUPLICATION ERROR: Failed to check killmail #{kill_id}: #{reason}")
        # Default to sending the notification in case of errors
        Logger.info("⚠️ FALLBACK: Sending notification despite deduplication error")
        WandererNotifier.Discord.Notifier.send_enriched_kill_embed(enriched_killmail, kill_id)
        :ok
    end
  end

  @doc """
  Returns the list of recent kills from the shared cache repository.
  """
  def get_recent_kills do
    Logger.debug("Retrieving recent kills from shared cache repository")

    # First get the list of recent kill IDs
    kill_ids = CacheRepo.get(@recent_kills_key) || []
    Logger.debug("Found #{length(kill_ids)} recent kill IDs in cache")

    # Then fetch each kill by its ID
    recent_kills =
      Enum.map(kill_ids, fn id ->
        key = "#{@recent_kills_key}:#{id}"
        kill_data = CacheRepo.get(key)

        if kill_data do
          # Log successful retrieval
          Logger.debug("Successfully retrieved kill #{id} from cache")
          kill_data
        else
          # Log cache miss
          Logger.warning("Failed to retrieve kill #{id} from cache (expired or missing)")
          nil
        end
      end)
      # Remove any nils from the list
      |> Enum.filter(&(&1 != nil))

    Logger.debug("Retrieved #{length(recent_kills)} cached kills from shared repository")

    recent_kills
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test_kill_notification do
    Logger.info("Sending test kill notification...")

    # Get recent kills
    recent_kills = get_recent_kills()
    Logger.debug("Found #{length(recent_kills)} recent kills in shared cache repository")

    if recent_kills == [] do
      error_message = "No recent kills available for test notification"
      Logger.error(error_message)

      # Notify the user through Discord
      WandererNotifier.Notifiers.Factory.notify(
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
      Logger.debug("Using kill data for test notification with kill_id: #{kill_id}")

      # Directly call the notifier with the killmail struct
      WandererNotifier.Discord.Notifier.send_enriched_kill_embed(
        recent_kill,
        kill_id
      )

      {:ok, kill_id}
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

    # Enrich victim data if available
    esi_data =
      if Map.has_key?(esi_data, "victim") do
        victim = Map.get(esi_data, "victim")
        enriched_victim = enrich_entity(victim)
        Map.put(esi_data, "victim", enriched_victim)
      else
        esi_data
      end

    # Enrich attackers if available
    esi_data =
      if Map.has_key?(esi_data, "attackers") do
        attackers = Map.get(esi_data, "attackers", [])
        enriched_attackers = Enum.map(attackers, &enrich_entity/1)
        Map.put(esi_data, "attackers", enriched_attackers)
      else
        esi_data
      end

    # Return updated killmail with enriched ESI data
    %Killmail{killmail | esi_data: esi_data}
  end

  # Enrich entity (victim or attacker) with additional information
  defp enrich_entity(entity) when is_map(entity) do
    # Add character name if missing
    entity =
      if Map.has_key?(entity, "character_id") && !Map.has_key?(entity, "character_name") do
        character_id = Map.get(entity, "character_id")

        character_name =
          case WandererNotifier.Api.ESI.Service.get_character_info(character_id) do
            {:ok, char_info} -> Map.get(char_info, "name", "Unknown Pilot")
            _ -> "Unknown Pilot"
          end

        Map.put(entity, "character_name", character_name)
      else
        entity
      end

    # Add corporation name if missing
    entity =
      if Map.has_key?(entity, "corporation_id") && !Map.has_key?(entity, "corporation_name") do
        corporation_id = Map.get(entity, "corporation_id")

        corporation_name =
          case WandererNotifier.Api.ESI.Service.get_corporation_info(corporation_id) do
            {:ok, corp_info} -> Map.get(corp_info, "name", "Unknown Corp")
            _ -> "Unknown Corp"
          end

        Map.put(entity, "corporation_name", corporation_name)
      else
        entity
      end

    # Add alliance name if missing
    entity =
      if Map.has_key?(entity, "alliance_id") && !Map.has_key?(entity, "alliance_name") do
        alliance_id = Map.get(entity, "alliance_id")

        alliance_name =
          case WandererNotifier.Api.ESI.Service.get_alliance_info(alliance_id) do
            {:ok, alliance_info} -> Map.get(alliance_info, "name", "Unknown Alliance")
            _ -> "Unknown Alliance"
          end

        Map.put(entity, "alliance_name", alliance_name)
      else
        entity
      end

    # Add ship name if missing
    entity =
      if Map.has_key?(entity, "ship_type_id") && !Map.has_key?(entity, "ship_type_name") do
        ship_id = Map.get(entity, "ship_type_id")

        ship_name =
          case WandererNotifier.Api.ESI.Service.get_ship_type_name(ship_id) do
            {:ok, type_info} -> Map.get(type_info, "name", "Unknown Ship")
            _ -> "Unknown Ship"
          end

        Map.put(entity, "ship_type_name", ship_name)
      else
        entity
      end

    entity
  end

  defp enrich_entity(entity), do: entity

  # Add system name to ESI data if missing
  defp enrich_with_system_name(esi_data) when is_map(esi_data) do
    if Map.has_key?(esi_data, "solar_system_id") && !Map.has_key?(esi_data, "solar_system_name") do
      system_id = Map.get(esi_data, "solar_system_id")

      system_name =
        case WandererNotifier.Api.ESI.Service.get_system_info(system_id) do
          {:ok, system_info} -> Map.get(system_info, "name", "Unknown System")
          _ -> "Unknown System"
        end

      Map.put(esi_data, "solar_system_name", system_name)
    else
      esi_data
    end
  end

  defp enrich_with_system_name(data), do: data

  # Helper function to get system name with caching
  defp get_system_name(nil), do: nil

  defp get_system_name(system_id) do
    # Check the local process cache first
    cache = Process.get(@system_names_cache_key) || %{}

    case Map.get(cache, system_id) do
      nil ->
        # Not in cache, fetch from ESI
        system_name =
          case WandererNotifier.Api.ESI.Service.get_system_info(system_id) do
            {:ok, system_info} -> Map.get(system_info, "name")
            _ -> nil
          end

        # Update cache
        updated_cache = Map.put(cache, system_id, system_name)
        Process.put(@system_names_cache_key, updated_cache)

        system_name

      system_name ->
        # Return from cache
        system_name
    end
  end

  # Helper function to diagnose tracking issues for a specific system ID
  defp debug_system_tracking(system_id) do
    system_id_str = to_string(system_id)

    # Get system name for better logging
    system_name = get_system_name(system_id)
    system_info = if system_name, do: "#{system_id} (#{system_name})", else: system_id

    # Get all tracked systems from cache
    tracked_systems = WandererNotifier.Helpers.CacheHelpers.get_tracked_systems()

    Logger.debug("DEBUG: Checking tracking for system #{system_info}")
    Logger.debug("DEBUG: Found #{length(tracked_systems)} tracked systems")

    # Try standard check first
    standard_check =
      WandererNotifier.Services.NotificationDeterminer.tracked_system?(system_id)

    Logger.debug("DEBUG: Standard tracking check result: #{standard_check}")

    # Manual check with each possible format
    matches =
      Enum.filter(tracked_systems, fn system ->
        case system do
          %{solar_system_id: id} when not is_nil(id) ->
            id_str = to_string(id)
            match = id_str == system_id_str

            if match,
              do: Logger.debug("DEBUG: Found match with solar_system_id (atom key): #{id}")

            match

          %{"solar_system_id" => id} when not is_nil(id) ->
            id_str = to_string(id)
            match = id_str == system_id_str

            if match,
              do: Logger.debug("DEBUG: Found match with solar_system_id (string key): #{id}")

            match

          %{system_id: id} when not is_nil(id) ->
            id_str = to_string(id)
            match = id_str == system_id_str
            if match, do: Logger.debug("DEBUG: Found match with system_id (atom key): #{id}")
            match

          %{"system_id" => id} when not is_nil(id) ->
            id_str = to_string(id)
            match = id_str == system_id_str
            if match, do: Logger.debug("DEBUG: Found match with system_id (string key): #{id}")
            match

          id when is_integer(id) or is_binary(id) ->
            id_str = to_string(id)
            match = id_str == system_id_str
            if match, do: Logger.debug("DEBUG: Found match with direct ID value: #{id}")
            match

          _ ->
            # No match for this system
            false
        end
      end)

    found = length(matches) > 0

    if found do
      Logger.debug("DEBUG: Found #{length(matches)} matches in tracked systems")
    else
      # If no match found, log the first few systems for debugging
      sample = Enum.take(tracked_systems, min(3, length(tracked_systems)))
      Logger.debug("DEBUG: No match found. Sample tracked system structures: #{inspect(sample)}")
    end

    # Try to find the system by direct lookup
    direct_system = WandererNotifier.Data.Cache.Repository.get("map:system:#{system_id_str}")

    if direct_system != nil do
      Logger.debug("DEBUG: Found system in direct cache lookup: #{inspect(direct_system)}")
    else
      Logger.debug("DEBUG: System not found in direct cache lookup")
    end

    # Return the results
    %{
      system_id: system_id,
      standard_check: standard_check,
      manual_check: found,
      matches: matches,
      direct_lookup: direct_system != nil
    }
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

    Logger.info("Triggering special debug for system ID: #{system_id}")
    # Send the message to the main Service module
    Process.send(WandererNotifier.Service, {:debug_special_system, system_id}, [])
  end
end
