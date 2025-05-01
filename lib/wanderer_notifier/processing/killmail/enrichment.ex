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
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Processing.Killmail.Notification, as: KillNotification

  @doc """
  Process and notify about a killmail.

  ## Parameters
  - killmail: The Killmail struct to process

  ## Returns
  - :ok on successful processing
  - {:ok, :skipped} if the killmail should not be notified
  """
  def process_and_notify(killmail) do
    # Check if we should notify about this kill
    should_notify = KillDeterminer.should_notify?(killmail)

    if should_notify do
      # Enrich the killmail data
      enriched_killmail = enrich_killmail_data(killmail)

      # Send notification and convert return value
      case KillNotification.send_kill_notification(enriched_killmail, killmail.killmail_id) do
        {:ok, _kill_id} ->
          AppLogger.kill_info("Kill notification sent successfully", %{
            kill_id: killmail.killmail_id
          })

          :ok

        {:error, reason} ->
          AppLogger.kill_error("Failed to send kill notification", %{
            kill_id: killmail.killmail_id,
            error: inspect(reason)
          })

          {:error, reason}
      end
    else
      AppLogger.kill_debug("Skipping notification for killmail: #{killmail.killmail_id}")
      {:ok, :skipped}
    end
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

    AppLogger.kill_debug("[Enrichment] Starting enrichment process",
      kill_id: killmail.killmail_id,
      initial_esi_data: inspect(esi_data, limit: 500)
    )

    # Enrich with system name if needed
    esi_data = enrich_with_system_name(esi_data)

    AppLogger.kill_debug("[Enrichment] After system name enrichment",
      kill_id: killmail.killmail_id,
      system_name: Map.get(esi_data, "solar_system_name"),
      has_victim: Map.has_key?(esi_data, "victim"),
      has_attackers: Map.has_key?(esi_data, "attackers")
    )

    # Enrich victim data if available
    esi_data =
      if Map.has_key?(esi_data, "victim") do
        victim = Map.get(esi_data, "victim")

        AppLogger.kill_debug("[Enrichment] Processing victim data",
          kill_id: killmail.killmail_id,
          victim_data: inspect(victim, limit: 200)
        )

        enriched_victim = enrich_entity(victim, killmail.killmail_id)
        Map.put(esi_data, "victim", enriched_victim)
      else
        # Log and continue without adding placeholder
        AppLogger.kill_warning("[Enrichment] Missing victim data in killmail",
          kill_id: killmail.killmail_id
        )

        esi_data
      end

    # Enrich attackers if available
    esi_data =
      if Map.has_key?(esi_data, "attackers") do
        attackers = Map.get(esi_data, "attackers", [])

        AppLogger.kill_debug("[Enrichment] Processing attackers data",
          kill_id: killmail.killmail_id,
          attackers_count: length(attackers),
          sample_attacker:
            if(length(attackers) > 0, do: inspect(hd(attackers), limit: 200), else: nil)
        )

        enriched_attackers = Enum.map(attackers, &enrich_entity(&1, killmail.killmail_id))
        Map.put(esi_data, "attackers", enriched_attackers)
      else
        # Log and continue without adding placeholder
        AppLogger.kill_warning("[Enrichment] Missing attackers data in killmail",
          kill_id: killmail.killmail_id
        )

        esi_data
      end

    AppLogger.kill_debug("[Enrichment] Completed enrichment process",
      kill_id: killmail.killmail_id,
      final_esi_data: inspect(esi_data, limit: 500)
    )

    # Return updated killmail with enriched ESI data
    %Killmail{killmail | esi_data: esi_data}
  end

  # Private functions

  # Add function header for enrich_entity/2 with default value
  defp enrich_entity(entity, killmail_id) when is_map(entity) do
    AppLogger.kill_debug("[Enrichment] Enriching entity: #{inspect(entity)}")

    enriched =
      entity
      |> add_character_name(killmail_id)
      |> add_corporation_name(killmail_id)
      |> add_alliance_name(killmail_id)
      |> add_ship_name()

    AppLogger.kill_debug("[Enrichment] Enriched entity result: #{inspect(enriched)}")
    enriched
  end

  defp enrich_entity(entity, _killmail_id), do: entity

  # Add character name if missing
  defp add_character_name(entity, killmail_id) do
    add_entity_info(
      entity,
      "character_id",
      "character_name",
      &ESIService.get_character_info/1,
      "Unknown Pilot",
      killmail_id
    )
  end

  # Add corporation name if missing
  defp add_corporation_name(entity, killmail_id) do
    add_entity_info(
      entity,
      "corporation_id",
      "corporation_name",
      &ESIService.get_corporation_info/1,
      "Unknown Corp",
      killmail_id
    )
  end

  # Add alliance name if missing
  defp add_alliance_name(entity, killmail_id) do
    add_entity_info(
      entity,
      "alliance_id",
      "alliance_name",
      &ESIService.get_alliance_info/1,
      "Unknown Alliance",
      killmail_id
    )
  end

  # Add ship name if missing
  defp add_ship_name(entity) do
    if Map.has_key?(entity, "ship_type_id") do
      ship_type_id = Map.get(entity, "ship_type_id")
      AppLogger.kill_debug("[Enrichment] Fetching ship name for ID: #{ship_type_id}")

      case ESIService.get_ship_type_name(ship_type_id) do
        {:ok, %{"name" => name}} ->
          AppLogger.kill_debug("[Enrichment] Got ship name: #{name}")
          Map.put(entity, "ship_type_name", name)

        {:error, reason} ->
          AppLogger.kill_warn(
            "[Enrichment] Failed to get ship name for ID #{ship_type_id}: #{inspect(reason)}"
          )

          Map.put(entity, "ship_type_name", "Unknown Ship")

        _ ->
          AppLogger.kill_warn(
            "[Enrichment] Unexpected response when fetching ship name for ID #{ship_type_id}"
          )

          Map.put(entity, "ship_type_name", "Unknown Ship")
      end
    else
      AppLogger.kill_debug("[Enrichment] No ship_type_id found in entity")
      entity
    end
  end

  # Generic function to add entity information if missing
  defp add_entity_info(entity, id_key, name_key, fetch_fn, default_name, killmail_id) do
    if Map.has_key?(entity, id_key) do
      id = Map.get(entity, id_key)
      AppLogger.kill_debug("[Enrichment] Fetching #{name_key} for ID: #{id}")
      name = fetch_entity_name(id, fetch_fn, default_name, killmail_id)
      # Ensure name is not nil or empty string
      name = if is_nil(name) or name == "", do: default_name, else: name
      AppLogger.kill_debug("[Enrichment] Got name: #{name}")
      Map.put(entity, name_key, name)
    else
      AppLogger.kill_debug("[Enrichment] No #{id_key} found in entity")
      entity
    end
  end

  # Fetch entity name from ESI API
  defp fetch_entity_name(id, fetch_fn, default_name, killmail_id) do
    case fetch_fn.(id) do
      {:ok, info} ->
        name = Map.get(info, "name", default_name)
        # Ensure name is not nil or empty string
        if is_nil(name) or name == "", do: default_name, else: name

      error ->
        AppLogger.kill_warn("[Enrichment] Failed to fetch name: #{inspect(error)}",
          killmail_id: killmail_id,
          entity_id: id
        )

        default_name
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

  # Helper method to get system name from ESI
  defp get_system_name(system_id) do
    case ESIService.get_system_info(system_id) do
      {:ok, system_info} -> Map.get(system_info, "name")
      _ -> nil
    end
  end
end
