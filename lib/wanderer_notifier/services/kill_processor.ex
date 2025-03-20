defmodule WandererNotifier.Services.KillProcessor do
  @moduledoc """
  Kill processor for WandererNotifier.
  Handles processing kill messages from zKill, including enrichment
  and deciding on notification based on tracked systems or characters.
  """
  require Logger

  alias WandererNotifier.Core.Features

  # Process dictionary key for recent kills
  @recent_kills_key "processor:recent_kills"
  @max_recent_kills 10

  def process_zkill_message(message, state) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, decoded_message} ->
        process_zkill_message(decoded_message, state)

      {:error, reason} ->
        Logger.error("Failed to decode zKill message: #{inspect(reason)}")
        # Return the state unchanged if we couldn't decode the message
        state
    end
  end

  def process_zkill_message(message, state) when is_map(message) do
    case Map.get(message, "action") do
      "tqStatus" ->
        # Handle server status updates
        handle_tq_status(message)
        state

      nil ->
        # Handle killmail
        handle_killmail(message, state)

      other ->
        Logger.debug("Ignoring zKill message with action: #{other}")
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
    # Extract the kill ID if available
    kill_id = get_in(killmail, ["killID"])

    # Check if this kill has already been processed or if kill_id is missing
    cond do
      is_nil(kill_id) ->
        Logger.warning("Received killmail without kill ID: #{inspect(killmail)}")
        state

      Map.has_key?(state.processed_kill_ids, kill_id) ->
        Logger.debug("Kill #{kill_id} already processed, skipping")
        state

      true ->
        # Process the kill
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

      is_nil(get_in(killmail, ["killID"])) ->
        {:error, "Killmail has no killID"}

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
    # Get the current list of recent kills
    recent_kills = Process.get(@recent_kills_key, [])

    # Add the new kill to the front
    updated_kills = [kill | recent_kills]
    # Keep only the most recent ones
    updated_kills = Enum.take(updated_kills, @max_recent_kills)

    # Update the process dictionary
    Process.put(@recent_kills_key, updated_kills)
  end

  @doc """
  Returns the list of recent kills from process dictionary.
  """
  def get_recent_kills do
    Process.get(@recent_kills_key, [])
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test_kill_notification do
    Logger.info("Sending test kill notification...")
    
    # Get recent kills or use sample data
    recent_kills = get_recent_kills()
    
    cond do
      recent_kills == [] ->
        Logger.info("No recent kills available, using sample test data")
        sample_kill = get_sample_kill()
        kill_id = Map.get(sample_kill, "killmail_id")
        WandererNotifier.Notifiers.Factory.notify(:send_enriched_kill_embed, [sample_kill, kill_id])
        {:ok, kill_id}
        
      true ->
        recent_kill = List.first(recent_kills)
        kill_id = Map.get(recent_kill, "killmail_id") || Map.get(recent_kill, :killmail_id)
        
        if kill_id do
          # Simulate a notification
          WandererNotifier.Notifiers.Factory.notify(:send_enriched_kill_embed, [recent_kill, kill_id])
          {:ok, kill_id}
        else
          Logger.error("No kill_id found in recent kill data")
          {:error, :no_kill_id}
        end
    end
  end
  
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
