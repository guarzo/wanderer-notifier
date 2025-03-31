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
  alias WandererNotifier.Notifiers.Determiner, as: Notification
  alias WandererNotifier.Processing.Killmail.Notification, as: KillNotification

  @doc """
  Process a killmail and send notification if required.

  ## Parameters
  - killmail: The Killmail struct to process

  ## Returns
  - :ok on successful processing
  - {:error, reason} on error
  """
  def process_and_notify(killmail) do
    # First check if this killmail should be notified
    should_notify = Notification.should_notify_kill?(killmail)

    AppLogger.kill_info(
      if should_notify do
        "👍 ENRICHMENT DECISION: Kill #{killmail.killmail_id} meets criteria for notification"
      else
        "👎 ENRICHMENT DECISION: Kill #{killmail.killmail_id} does not meet criteria for notification"
      end,
      %{
        kill_id: killmail.killmail_id,
        should_notify: should_notify,
        system_id: get_in(killmail.esi_data || %{}, ["solar_system_id"]),
        system_name: get_in(killmail.esi_data || %{}, ["solar_system_name"])
      }
    )

    if should_notify do
      # Enrich the killmail with additional data
      enriched_kill = enrich_killmail_data(killmail)

      # Send the notification
      AppLogger.kill_info(
        "🔄 SENDING NOTIFICATION: Kill #{killmail.killmail_id} is being sent for notification",
        %{kill_id: killmail.killmail_id}
      )

      KillNotification.send_kill_notification(enriched_kill, killmail.killmail_id)
    else
      AppLogger.kill_info(
        "⏭️ SKIPPING NOTIFICATION: Kill #{killmail.killmail_id} - does not meet criteria",
        %{kill_id: killmail.killmail_id}
      )
    end

    :ok
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
