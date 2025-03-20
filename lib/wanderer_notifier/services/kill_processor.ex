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
  @kill_ttl 3600 # 1 hour TTL for cached kills

  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Killmail

  def process_zkill_message(message, state) when is_binary(message) do
    Logger.info("PROCESSOR TRACE: Processing raw message from WebSocket, length: #{String.length(message)}")
    case Jason.decode(message) do
      {:ok, decoded_message} ->
        Logger.info("PROCESSOR TRACE: Successfully decoded JSON message: #{inspect(Map.keys(decoded_message))}")
        process_zkill_message(decoded_message, state)

      {:error, reason} ->
        Logger.error("PROCESSOR TRACE: Failed to decode zKill message: #{inspect(reason)}")
        # Return the state unchanged if we couldn't decode the message
        state
    end
  end

  def process_zkill_message(message, state) when is_map(message) do
    # Enhanced logging to trace message processing
    Logger.info("PROCESSOR TRACE: Processing decoded message with keys: #{inspect(Map.keys(message))}")
    
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
    
    # Extract the kill ID if available - only use the correct field name
    kill_id = get_in(killmail, ["killmail_id"])
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
        # Process the kill
        Logger.info("KILLMAIL TRACE: Processing new kill #{kill_id}")
        process_new_kill(killmail, kill_id, state)
    end
  end

  defp process_new_kill(killmail, kill_id, state) do
    # Store each kill in memory - we'll limit to the last 50 kills
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

  # Validate kill data structure
  defp validate_killmail(killmail) do
    cond do
      not is_map(killmail) ->
        {:error, "Killmail is not a map"}

      is_nil(get_in(killmail, ["killmail_id"])) ->
        {:error, "Killmail has no killmail_id field"}

      true ->
        :ok
    end
  end

  # Simulate enrichment and notification
  defp enrich_and_notify(kill_id) do
    try do
      # This would be the real enrichment and notification logic
      Logger.info("Would enrich and notify about kill #{kill_id}")
      :ok
    rescue
      e ->
        Logger.error("Exception during enrichment: #{Exception.message(e)}")
        {:error, "Failed to enrich kill: #{Exception.message(e)}"}
    end
  end

  defp update_recent_kills(kill) do
    # Add enhanced logging to trace cache updates
    Logger.info("CACHE TRACE: Storing kill in shared cache repository")
    Logger.info("CACHE TRACE: Kill data keys: #{inspect(Map.keys(kill))}")
    
    # Make sure the kill has a killmail_id by ensuring it's properly structured
    kill_with_id = ensure_kill_has_id(kill)
    
    # Verify ID was properly set
    kill_id = get_killmail_id(kill_with_id)
    
    case kill_id do
      nil -> 
        Logger.warning("CACHE TRACE: Failed to extract/set killmail_id on kill data")
        # Can't store a kill without an ID
        :error
        
      id -> 
        Logger.info("CACHE TRACE: Successfully extracted killmail_id: #{id}")
        
        # Store the individual kill by ID
        individual_key = "#{@recent_kills_key}:#{id}"
        
        # Convert to a Killmail struct if we have the necessary data
        # This ensures consistent data structure for retrieval
        cache_data = try_create_killmail_struct(kill_with_id)
        
        # Store in cache with TTL
        CacheRepo.set(individual_key, cache_data, @kill_ttl)
        
        # Now update the list of recent kill IDs
        update_recent_kill_ids(id)
        
        Logger.info("CACHE TRACE: Stored kill #{id} in shared cache repository")
        :ok
    end
  end
  
  # Update the list of recent kill IDs in the cache
  defp update_recent_kill_ids(new_kill_id) do
    # Get current list of kill IDs from the cache
    kill_ids = CacheRepo.get(@recent_kills_key) || []
    
    # Add the new ID to the front
    updated_ids = [new_kill_id | kill_ids] 
                  |> Enum.uniq() # Remove duplicates
                  |> Enum.take(@max_recent_kills) # Keep only the most recent ones
    
    # Update the cache
    CacheRepo.set(@recent_kills_key, updated_ids, @kill_ttl)
    Logger.info("CACHE TRACE: Updated recent kill IDs in cache - now has #{length(updated_ids)} IDs")
  end
  
  # Try to create a Killmail struct from the raw data
  defp try_create_killmail_struct(kill_data) do
    kill_id = get_killmail_id(kill_data)
    
    if kill_id do
      # Extract zkb data if available
      zkb_data = Map.get(kill_data, "zkb") || %{}
      
      # The rest is treated as ESI data
      esi_data = Map.drop(kill_data, ["zkb"])
      
      # Create a proper Killmail struct
      try do
        Killmail.new(kill_id, zkb_data, esi_data)
      rescue
        # If struct creation fails, just store the raw data
        _ -> kill_data
      end
    else
      # If no kill ID, just return the raw data
      kill_data
    end
  end
  
  # Ensure kill has the proper id fields for easy access
  defp ensure_kill_has_id(kill) when is_map(kill) do
    if Map.has_key?(kill, "killmail_id") || Map.has_key?(kill, :killmail_id) do
      # Already has the right field
      kill
    else
      # May need to extract id from various structures
      kill_id = get_killmail_id(kill)
      if kill_id, do: Map.put(kill, "killmail_id", kill_id), else: kill
    end
  end
  
  defp ensure_kill_has_id(kill), do: kill

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
          Logger.warning("CACHE TRACE: Failed to retrieve kill #{id} from cache (expired or missing)")
          nil
        end
      end)
      |> Enum.filter(&(&1 != nil)) # Remove any nils from the list
    
    Logger.info("CACHE TRACE: Retrieved #{length(recent_kills)} cached kills from shared repository")
    recent_kills
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test_kill_notification do
    Logger.info("Sending test kill notification...")
    
    # Get recent kills or use sample data
    recent_kills = get_recent_kills()
    
    # Log what we're finding to debug the issue
    Logger.info("Found #{length(recent_kills)} recent kills in shared cache repository")
    if length(recent_kills) > 0 do
      first_kill = List.first(recent_kills)
      Logger.debug("First kill data structure: #{inspect(first_kill, pretty: true, limit: 200)}")
      
      # Check for Killmail struct
      is_struct = match?(%Killmail{}, first_kill)
      Logger.debug("First kill is Killmail struct? #{is_struct}")
      
      if is_struct do
        Logger.debug("Killmail struct ID: #{first_kill.killmail_id}")
      else
        # Regular map
        Logger.debug("First kill has killmail_id? #{Map.has_key?(first_kill, "killmail_id")}")
        Logger.debug("Keys in first kill: #{inspect(Map.keys(first_kill))}")
      end
    end
    
    cond do
      recent_kills == [] ->
        Logger.info("No recent kills available, using sample test data")
        sample_kill = get_sample_kill()
        kill_id = Map.get(sample_kill, "killmail_id")
        WandererNotifier.Notifiers.Factory.notify(:send_enriched_kill_embed, [sample_kill, kill_id])
        Logger.info("Test notification sent using SAMPLE DATA with kill_id: #{kill_id}")
        {:ok, kill_id}
        
      true ->
        recent_kill = List.first(recent_kills)
        
        # Handle different data formats
        {kill_data, kill_id} = extract_kill_data(recent_kill)
        
        if kill_id do
          # Log what we're using for testing clarity
          Logger.info("Using REAL KILL DATA for test notification with kill_id: #{kill_id}")
          # Send the actual notification
          WandererNotifier.Notifiers.Factory.notify(:send_enriched_kill_embed, [kill_data, kill_id])
          {:ok, kill_id}
        else
          Logger.error("No killmail_id found in recent kill data: #{inspect(recent_kill)}")
          # Fallback to sample data if recent kill is malformed
          sample_kill = get_sample_kill()
          fallback_kill_id = Map.get(sample_kill, "killmail_id")
          Logger.info("Falling back to SAMPLE DATA for test notification with kill_id: #{fallback_kill_id}")
          WandererNotifier.Notifiers.Factory.notify(:send_enriched_kill_embed, [sample_kill, fallback_kill_id])
          {:ok, fallback_kill_id}
        end
    end
  end
  
  # Helper function to extract kill data from either a Killmail struct or a map
  defp extract_kill_data(kill) do
    cond do
      # Case 1: It's a Killmail struct
      match?(%Killmail{}, kill) ->
        # Convert struct to a map format that the notifier expects
        kill_id = kill.killmail_id
        # Merge zkb and esi_data into a single map for the notifier
        kill_data = Map.merge(%{"killmail_id" => kill_id}, kill.zkb || %{})
        kill_data = if kill.esi_data, do: Map.merge(kill_data, kill.esi_data), else: kill_data
        {kill_data, kill_id}
      
      # Case 2: It's a binary string (JSON)
      is_binary(kill) ->
        case Jason.decode(kill) do
          {:ok, decoded} -> 
            kill_id = get_killmail_id(decoded)
            {decoded, kill_id}
          _ -> 
            {kill, nil}
        end
      
      # Case 3: It's a regular map
      is_map(kill) ->
        kill_id = get_killmail_id(kill)
        {kill, kill_id}
      
      # Case 4: Unknown format
      true ->
        {kill, nil}
    end
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
        kill_id = Map.get(kill_data, "killID") || 
                 get_in(kill_data, ["zkb", "killID"]) ||
                 get_in(kill_data, ["zkb", "killmail_id"])
                 
        # If we found a string ID, convert to integer
        if is_binary(kill_id) do
          String.to_integer(kill_id)
        else
          kill_id
        end
      
      true -> nil
    end
  end
  
  defp get_killmail_id(_), do: nil
  
  # Returns a sample kill for testing purposes
  defp get_sample_kill do
    # Use pre-enriched data to avoid ESI lookups
    # These are real IDs that exist in the game
    %{
      "killmail_id" => 12345678,
      "killmail_time" => "2023-05-01T12:00:00Z",
      "solar_system_id" => 30000142, # Jita
      "victim" => %{
        "character_id" => 1354830081, # CCP character
        "character_name" => "CCP Garthagk",
        "corporation_id" => 98356193,
        "corporation_name" => "C C P Alliance",
        "alliance_id" => 434243723,
        "alliance_name" => "C C P Alliance",
        "ship_type_id" => 670, # Capsule
        "ship_name" => "Capsule",
        "damage_taken" => 1000,
        "position" => %{
          "x" => 0.0,
          "y" => 0.0,
          "z" => 0.0
        }
      },
      "attackers" => [
        %{
          "character_id" => 92168909, # Another CCP character
          "character_name" => "CCP Zoetrope",
          "corporation_id" => 98356193,
          "corporation_name" => "C C P Alliance",
          "alliance_id" => 434243723,
          "alliance_name" => "C C P Alliance",
          "ship_type_id" => 11567, # Triglavian ship
          "ship_name" => "Drekavac",
          "damage_done" => 1000,
          "final_blow" => true
        }
      ],
      "zkb" => %{
        "locationID" => 30000142,
        "hash" => "samplehash",
        "fittedValue" => 100000000.00,
        "totalValue" => 150000000.00,
        "points" => 10,
        "npc" => false,
        "solo" => true,
        "awox" => false
      },
      # Add pre-enriched information to prevent ESI lookups
      "victim_info" => %{
        "character_name" => "CCP Garthagk",
        "corporation_name" => "C C P Alliance",
        "alliance_name" => "C C P Alliance"
      },
      "attacker_info" => %{
        "character_name" => "CCP Zoetrope",
        "corporation_name" => "C C P Alliance",
        "alliance_name" => "C C P Alliance"
      },
      "system_info" => %{
        "name" => "Jita",
        "security" => 0.9
      },
      "ship_info" => %{
        "victim_ship" => "Capsule",
        "attacker_ship" => "Drekavac"
      },
      # Add flags to skip ESI enrichment
      "_skip_esi_enrichment" => true
    }
  end
end
