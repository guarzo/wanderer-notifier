defmodule WandererNotifier.Services.KillProcessor do
  @moduledoc """
  Kill processor for WandererNotifier.
  Handles processing kill messages from zKill, including enrichment
  and deciding on notification based on tracked systems or characters.
  """
  require Logger

  alias WandererNotifier.Core.Features

  # Cache keys for recent kills
  @recent_kills_key "zkill:recent_kills"
  @max_recent_kills 10
  # 1 hour TTL for cached kills
  @kill_ttl 3600

  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Killmail

  def process_zkill_message(message, state) when is_binary(message) do
    Logger.info(
      "PROCESSOR TRACE: Processing raw message from WebSocket, length: #{String.length(message)}"
    )

    case Jason.decode(message) do
      {:ok, decoded_message} ->
        Logger.info(
          "PROCESSOR TRACE: Successfully decoded JSON message: #{inspect(Map.keys(decoded_message))}"
        )

        process_zkill_message(decoded_message, state)

      {:error, reason} ->
        Logger.error("PROCESSOR TRACE: Failed to decode zKill message: #{inspect(reason)}")
        # Return the state unchanged if we couldn't decode the message
        state
    end
  end

  def process_zkill_message(message, state) when is_map(message) do
    # Enhanced logging to trace message processing
    Logger.info(
      "PROCESSOR TRACE: Processing decoded message with keys: #{inspect(Map.keys(message))}"
    )

    # Check for killmail_id or zkb, which would indicate a kill message regardless of action field
    if Map.has_key?(message, "killmail_id") || Map.has_key?(message, "zkb") do
      Logger.info("PROCESSOR TRACE: Message has killmail_id or zkb key - treating as killmail")
      handle_killmail(message, state)
    else
      # Normal path for non-kill messages
      case Map.get(message, "action") do
        "tqStatus" ->
          # Handle server status updates
          Logger.info("PROCESSOR TRACE: Processing tqStatus message")
          handle_tq_status(message)
          state

        nil ->
          # Handle message with no action as potential killmail
          Logger.info("PROCESSOR TRACE: Processing message with no action as potential killmail")
          handle_killmail(message, state)

        other ->
          Logger.info("PROCESSOR TRACE: Ignoring zKill message with action: #{other}")
          state
      end
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
    # Enhanced logging to trace kill handling
    Logger.info("KILLMAIL TRACE: Handling potential killmail: #{inspect(Map.keys(killmail))}")

    # Extract the kill ID if available
    kill_id = get_killmail_id(killmail)
    Logger.info("KILLMAIL TRACE: Extracted killmail_id: #{inspect(kill_id)}")

    # Check if this kill has already been processed or if kill_id is missing
    cond do
      is_nil(kill_id) ->
        Logger.warning("KILLMAIL TRACE: Received killmail without kill ID: #{inspect(killmail)}")
        state

      Map.has_key?(state.processed_kill_ids, kill_id) ->
        Logger.info("KILLMAIL TRACE: Kill #{kill_id} already processed, skipping")
        state

      true ->
        # Process the kill - first convert to Killmail struct for consistent handling
        Logger.info("KILLMAIL TRACE: Processing new kill #{kill_id}")

        # Extract zkb data
        zkb_data = Map.get(killmail, "zkb", %{})

        # The rest is treated as ESI data, except for fields we know aren't ESI data
        # This ensures we don't drop important data when organizing it
        esi_data = Map.drop(killmail, ["zkb"])

        # Create a Killmail struct - standardizing the data structure early
        killmail_struct = Killmail.new(kill_id, zkb_data, esi_data)

        # Now process the standardized data structure
        process_new_kill(killmail_struct, kill_id, state)
    end
  end

  defp process_new_kill(%Killmail{} = killmail, kill_id, state) do
    # Store the kill in the cache - now we're passing a Killmail struct
    update_recent_kills(killmail)

    # Only continue with processing if feature is enabled
    if Features.enabled?(:backup_kills_processing) do
      with :ok <- validate_killmail(killmail),
           :ok <- enrich_and_notify(kill_id) do
        # Return the state with the kill marked as processed
        Map.update(state, :processed_kill_ids, %{kill_id => :os.system_time(:second)}, fn ids ->
          Map.put(ids, kill_id, :os.system_time(:second))
        end)
      else
        {:error, reason} ->
          Logger.error("Error processing kill #{kill_id}: #{reason}")
          Logger.debug("Problematic killmail: #{inspect(killmail)}")
          state
      end
    else
      Logger.debug("Backup kills processing disabled, not enriching kill #{kill_id}")
      state
    end
  end

  # Validate Killmail struct
  defp validate_killmail(%Killmail{} = killmail) do
    # Standardized validation for Killmail struct
    if is_nil(killmail.killmail_id) do
      {:error, "Killmail struct has no killmail_id field"}
    else
      :ok
    end
  end

  defp update_recent_kills(%Killmail{} = killmail) do
    # Add enhanced logging to trace cache updates
    Logger.info("CACHE TRACE: Storing Killmail struct in shared cache repository")

    kill_id = killmail.killmail_id

    # Store the individual kill by ID
    individual_key = "#{@recent_kills_key}:#{kill_id}"

    # Store the Killmail struct directly - no need to convert again
    CacheRepo.set(individual_key, killmail, @kill_ttl)

    # Now update the list of recent kill IDs
    update_recent_kill_ids(kill_id)

    Logger.info("CACHE TRACE: Stored kill #{kill_id} in shared cache repository")
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

    Logger.info(
      "CACHE TRACE: Updated recent kill IDs in cache - now has #{length(updated_ids)} IDs"
    )
  end

  # Simulate enrichment and notification
  defp enrich_and_notify(kill_id) do
    try do
      # Get the cached killmail
      key = "#{@recent_kills_key}:#{kill_id}"
      killmail = CacheRepo.get(key)

      if is_nil(killmail) do
        Logger.error("Cannot find cached killmail for kill_id=#{kill_id}")
        {:error, "Killmail not found in cache"}
      else
        # Extract the system ID from the killmail
        system_id = get_system_id_from_killmail(killmail)

        # Determine if this kill should trigger a notification
        if WandererNotifier.Services.NotificationDeterminer.should_notify_kill?(
             killmail,
             system_id
           ) do
          # Get the enriched killmail data
          enriched_killmail = enrich_killmail_data(killmail)

          # Send the notification
          send_kill_notification(enriched_killmail, kill_id)
          Logger.info("Successfully sent notification for kill_id=#{kill_id}")
          :ok
        else
          Logger.info(
            "Kill #{kill_id} filtered out - not in tracked system or involving tracked character"
          )

          :ok
        end
      end
    rescue
      e ->
        Logger.error("Exception during enrichment: #{Exception.message(e)}")
        {:error, "Failed to enrich kill: #{Exception.message(e)}"}
    end
  end

  # Extract system ID from killmail
  defp get_system_id_from_killmail(%Killmail{} = killmail) do
    case killmail do
      %Killmail{esi_data: esi_data} when is_map(esi_data) ->
        Map.get(esi_data, "solar_system_id")

      _ ->
        nil
    end
  end

  defp get_system_id_from_killmail(killmail) when is_map(killmail) do
    # Try to get system ID from various possible locations
    Map.get(killmail, "solar_system_id") ||
      Map.get(killmail, :solar_system_id) ||
      get_in(killmail, ["esi_data", "solar_system_id"]) ||
      get_in(killmail, [:esi_data, "solar_system_id"])
  end

  defp get_system_id_from_killmail(_), do: nil

  # Send the notification for a kill
  defp send_kill_notification(enriched_killmail, kill_id) do
    # Format and send the notification using Discord notifier
    WandererNotifier.Discord.Notifier.send_enriched_kill_embed(enriched_killmail, kill_id)

    # Log the notification for tracking purposes
    Logger.info("Kill notification sent for kill_id=#{kill_id}")
  end

  @doc """
  Returns the list of recent kills from the shared cache repository.
  """
  def get_recent_kills do
    Logger.info("CACHE TRACE: Retrieving recent kills from shared cache repository")

    # First get the list of recent kill IDs
    kill_ids = CacheRepo.get(@recent_kills_key) || []
    Logger.info("CACHE TRACE: Found #{length(kill_ids)} recent kill IDs in cache")

    # Then fetch each kill by its ID
    recent_kills =
      Enum.map(kill_ids, fn id ->
        key = "#{@recent_kills_key}:#{id}"
        kill_data = CacheRepo.get(key)

        if kill_data do
          # Log successful retrieval
          Logger.debug("CACHE TRACE: Successfully retrieved kill #{id} from cache")
          kill_data
        else
          # Log cache miss
          Logger.warning(
            "CACHE TRACE: Failed to retrieve kill #{id} from cache (expired or missing)"
          )

          nil
        end
      end)
      # Remove any nils from the list
      |> Enum.filter(&(&1 != nil))

    Logger.info(
      "CACHE TRACE: Retrieved #{length(recent_kills)} cached kills from shared repository"
    )

    recent_kills
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test_kill_notification do
    Logger.info("Sending test kill notification...")

    # Get recent kills
    recent_kills = get_recent_kills()

    # Log what we're finding to debug the issue
    Logger.info("Found #{length(recent_kills)} recent kills in shared cache repository")

    if length(recent_kills) > 0 do
      first_kill = List.first(recent_kills)
      Logger.debug("First kill data structure: #{inspect(first_kill, pretty: true, limit: 200)}")

      # Check for Killmail struct
      is_struct = match?(%Killmail{}, first_kill)
      Logger.debug("First kill is Killmail struct? #{is_struct}")
    end

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
      # Use the first kill - it should already be a Killmail struct
      recent_kill = List.first(recent_kills)

      kill_id =
        if match?(%Killmail{}, recent_kill),
          do: recent_kill.killmail_id,
          else: get_killmail_id(recent_kill)

      if kill_id do
        # Log what we're using for testing clarity
        Logger.info("Using REAL KILL DATA for test notification with kill_id: #{kill_id}")

        # Ensure we're working with a Killmail struct
        kill_data =
          if match?(%Killmail{}, recent_kill),
            do: recent_kill,
            else: convert_to_killmail(recent_kill, kill_id)

        # Log the kill data structure for debugging
        Logger.info(
          "Using Killmail struct with id=#{kill_data.killmail_id}, esi_data keys: #{inspect(Map.keys(kill_data.esi_data || %{}))}"
        )

        # Directly call the notifier to avoid translation layers
        WandererNotifier.Discord.Notifier.send_enriched_kill_embed(
          kill_data,
          kill_id
        )

        {:ok, kill_id}
      else
        error_message = "No valid killmail_id found in recent kill data"
        Logger.error("#{error_message}: #{inspect(recent_kill)}")

        # Notify the user through Discord
        WandererNotifier.Notifiers.Factory.notify(
          :send_message,
          ["Error: #{error_message} - No test notification sent."]
        )

        {:error, error_message}
      end
    end
  end

  # Helper function to convert a map to a Killmail struct
  defp convert_to_killmail(kill_data, kill_id) when is_map(kill_data) do
    # Extract zkb data if available
    zkb_data = Map.get(kill_data, "zkb", %{})

    # The rest is treated as ESI data
    esi_data = Map.drop(kill_data, ["zkb"])

    # Add solar_system_name if we have solar_system_id but no name
    esi_data =
      if Map.has_key?(esi_data, "solar_system_id") && !Map.has_key?(esi_data, "solar_system_name") do
        # We have a system_id but no name - we'll need to look it up when enriching
        # Just preserve the id for now
        esi_data
      else
        esi_data
      end

    # Create a Killmail struct
    Killmail.new(kill_id, zkb_data, esi_data)
  end

  defp convert_to_killmail(kill_data, kill_id) do
    # For non-map data, create a minimal struct
    Logger.warning("Converting non-map data to Killmail struct: #{inspect(kill_data)}")
    Killmail.new(kill_id, %{}, %{})
  end

  # Helper function to extract the killmail ID from different possible structures
  defp get_killmail_id(kill_data) when is_map(kill_data) do
    cond do
      # Direct field
      Map.has_key?(kill_data, "killmail_id") ->
        Map.get(kill_data, "killmail_id")

      # Check for nested structure
      Map.has_key?(kill_data, "zkb") && Map.has_key?(kill_data, "killmail") ->
        get_in(kill_data, ["killmail", "killmail_id"])

      # Check for string keys converted to atoms
      Map.has_key?(kill_data, :killmail_id) ->
        Map.get(kill_data, :killmail_id)

      # Try to extract from the raw data if it has a zkb key
      # (common format in real-time websocket feed)
      Map.has_key?(kill_data, "zkb") ->
        kill_id =
          Map.get(kill_data, "killID") ||
            get_in(kill_data, ["zkb", "killID"]) ||
            get_in(kill_data, ["zkb", "killmail_id"])

        # If we found a string ID, convert to integer
        if is_binary(kill_id) do
          String.to_integer(kill_id)
        else
          kill_id
        end

      true ->
        nil
    end
  end

  defp get_killmail_id(_), do: nil

  # Enrich the killmail data with additional information needed for notifications
  defp enrich_killmail_data(%Killmail{} = killmail) do
    # Since we can't use the private enrichment function directly,
    # we'll implement our own basic enrichment logic
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

  # Handle non-Killmail structured data
  defp enrich_killmail_data(killmail) when is_map(killmail) do
    # Convert to Killmail struct if possible
    kill_id = Map.get(killmail, "killmail_id") || Map.get(killmail, :killmail_id)
    zkb_data = Map.get(killmail, "zkb") || Map.get(killmail, :zkb) || %{}
    esi_data = Map.drop(killmail, ["zkb", :zkb])

    # Create a new Killmail struct
    killmail_struct = Killmail.new(kill_id, zkb_data, esi_data)

    # Now enrich using the struct version
    enrich_killmail_data(killmail_struct)
  end

  defp enrich_killmail_data(data) do
    # For anything else, return as is with a warning
    Logger.warning("Cannot enrich killmail data of unknown format: #{inspect(data, limit: 100)}")
    data
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
end
