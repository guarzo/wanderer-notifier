defmodule WandererNotifier.Processing.Killmail.Enrichment do
  @moduledoc """
  Handles enrichment of killmail data.

  - Adds additional information from external APIs
  - Processes victim and attacker information
  - Adds system information to kills
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Process a killmail for notification by enriching it and
  delegating to the notification system.

  ## Parameters
  - killmail: The killmail struct to process

  ## Returns
  - :ok if processing and notification was successful
  - {:error, reason} if an error occurred
  """
  def process_and_notify(%Killmail{} = killmail) do
    # Extract basic kill information
    kill_info = extract_kill_info(killmail)

    # Extract and log victim/attacker information
    _victim_info = extract_victim_info(killmail, kill_info.kill_id)
    _attacker_info = extract_attacker_info(killmail, kill_info.kill_id)

    # Get tracking information
    _tracking_info = get_tracking_info()

    # Log tracking status
    log_tracking_status()

    # Determine if notification should be sent and handle it
    handle_notification_decision()
  rescue
    e ->
      AppLogger.kill_error("⚠️ EXCEPTION: Error during kill enrichment: #{Exception.message(e)}")
      {:error, "Failed to enrich kill: #{Exception.message(e)}"}
  end

  @doc """
  Enrich a killmail with additional data from external APIs.

  ## Parameters
  - killmail: The killmail struct to enrich

  ## Returns
  - Enriched killmail struct
  """
  def enrich_killmail_data(%Killmail{} = killmail) do
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
        # Log and continue without adding placeholder
        AppLogger.kill_warning("[Enrichment] Missing victim data in killmail")
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
        AppLogger.kill_warning("[Enrichment] Missing attackers data in killmail")
        esi_data
      end

    # Return updated killmail with enriched ESI data
    %Killmail{killmail | esi_data: esi_data}
  end

  # Private functions

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

  # Extract system ID from killmail
  defp get_system_id_from_killmail(%Killmail{} = killmail) do
    # Use the Killmail module's helper
    system_id = Killmail.get_system_id(killmail)
    system_id
  end

  defp get_system_id_from_killmail(_), do: nil

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
  defp get_tracking_info do
    # Mock implementation - would reference tracked systems and characters
    # to determine if this kill should be tracked
    %{
      is_system_tracked: false,
      is_character_tracked: false,
      victim_tracked: false,
      tracked_attackers: []
    }
  end

  # Log tracking status information
  defp log_tracking_status do
    # Mock implementation - would log tracking status
    :ok
  end

  # Handle notification decision logic
  defp handle_notification_decision do
    # Mock implementation - would determine if notification should be sent
    # and handle sending it
    :ok
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
      AppLogger.kill_warning("[Enrichment] No system ID available in killmail data")
      esi_data
    else
      # Get system name and add it if found
      system_name = get_system_name(system_id)
      add_system_name_if_found(esi_data, system_id, system_name)
    end
  end

  # Add system name to data if found
  defp add_system_name_if_found(esi_data, system_id, nil) do
    AppLogger.kill_debug("[Enrichment] No system name found for ID #{system_id}")
    esi_data
  end

  defp add_system_name_if_found(esi_data, _system_id, system_name) do
    Map.put(esi_data, "solar_system_name", system_name)
  end

  # Helper method to get system name - would call to Cache in complete implementation
  defp get_system_name(_system_id) do
    nil
  end
end
