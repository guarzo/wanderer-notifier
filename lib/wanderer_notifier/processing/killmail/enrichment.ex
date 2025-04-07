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

    # Print killmail enrichment header only when logging is enabled
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("\n=====================================================")
      IO.puts("🔍 ENRICHING KILLMAIL #{killmail.killmail_id}")
      IO.puts("=====================================================\n")
    end

    # Continue with regular AppLogger for non-IO.puts logging
    AppLogger.kill_debug(
      "[Enrichment] Starting enrichment process for killmail #{killmail.killmail_id}"
    )

    # Debug logging the initial state
    AppLogger.kill_debug("[Enrichment] Initial state:", %{
      has_esi_data: not is_nil(esi_data),
      has_victim: is_map(esi_data) && Map.has_key?(esi_data, "victim"),
      has_attackers: is_map(esi_data) && Map.has_key?(esi_data, "attackers"),
      has_system_id: is_map(esi_data) && Map.has_key?(esi_data, "solar_system_id"),
      has_system_name: is_map(esi_data) && Map.has_key?(esi_data, "solar_system_name")
    })

    # If esi_data is nil, initialize it
    esi_data = if is_nil(esi_data), do: %{}, else: esi_data

    # Print header for system data enrichment
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("\n------ SOLAR SYSTEM DATA ------")
    end

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

        # Print header for victim data
        if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
          IO.puts("\n------ VICTIM DATA ------")
        end

        AppLogger.kill_debug("[Enrichment] Processing victim data",
          kill_id: killmail.killmail_id,
          victim_data: inspect(victim, limit: 200)
        )

        enriched_victim = enrich_entity(victim)

        # Log the enriched victim data specifically
        AppLogger.kill_debug("[Enrichment] Victim after enrichment",
          ship_type_name: Map.get(enriched_victim, "ship_type_name"),
          character_name: Map.get(enriched_victim, "character_name"),
          corporation_name: Map.get(enriched_victim, "corporation_name"),
          alliance_name: Map.get(enriched_victim, "alliance_name")
        )

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

        # Print header for attacker data
        if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
          IO.puts("\n------ ATTACKER DATA ------")
        end

        AppLogger.kill_debug("[Enrichment] Processing attackers data",
          kill_id: killmail.killmail_id,
          attackers_count: length(attackers)
        )

        enriched_attackers =
          Enum.map(attackers, fn attacker ->
            enriched = enrich_entity(attacker)

            # Log each enriched attacker
            if Map.get(attacker, "final_blow") == true do
              AppLogger.kill_debug("[Enrichment] Final blow attacker after enrichment",
                ship_type_name: Map.get(enriched, "ship_type_name"),
                character_name: Map.get(enriched, "character_name"),
                corporation_name: Map.get(enriched, "corporation_name"),
                alliance_name: Map.get(enriched, "alliance_name")
              )
            end

            enriched
          end)

        Map.put(esi_data, "attackers", enriched_attackers)
      else
        # Log and continue without adding placeholder
        AppLogger.kill_warning("[Enrichment] Missing attackers data in killmail",
          kill_id: killmail.killmail_id
        )

        esi_data
      end

    # Print enrichment completion message
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("\n=====================================================")
      IO.puts("✅ ENRICHMENT COMPLETED FOR KILLMAIL #{killmail.killmail_id}")
      IO.puts("=====================================================\n")
    end

    AppLogger.kill_debug(
      "[Enrichment] Completed enrichment process for killmail #{killmail.killmail_id}"
    )

    # Return updated killmail with enriched ESI data
    %Killmail{killmail | esi_data: esi_data}
  end

  # Private functions

  # Enrich entity (victim or attacker) with additional information
  defp enrich_entity(entity) when is_map(entity) do
    # Log the start of entity enrichment using IO.puts
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      if Map.has_key?(entity, "character_id") do
        character_id = Map.get(entity, "character_id")
        IO.puts("\n------ ENTITY ENRICHMENT (ID: #{character_id}) ------")
      else
        IO.puts("\n------ ENTITY ENRICHMENT (Unknown ID) ------")
      end
    end

    # Directly apply the enrichment steps in sequence
    enriched =
      entity
      |> add_character_name()
      |> add_corporation_name()
      |> add_alliance_name()
      |> add_ship_name()

    # Add a visual separator after the entity enrichment
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("----------------------------------------")
    end

    enriched
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
    if Map.has_key?(entity, "ship_type_id") do
      ship_type_id = Map.get(entity, "ship_type_id")

      # Log using IO.puts format
      if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
        IO.puts("SHIP_TYPE_ID: #{ship_type_id}")
      end

      case ESIService.get_ship_type_name(ship_type_id) do
        {:ok, %{"name" => name}} ->
          if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
            IO.puts("SHIP_TYPE_NAME: #{name}")
          end

          Map.put(entity, "ship_type_name", name)

        {:error, reason} ->
          if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
            IO.puts("SHIP_TYPE_NAME: Unknown Ship (ESI error: #{inspect(reason)})")
          end

          Map.put(entity, "ship_type_name", "Unknown Ship")

        _ ->
          if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
            IO.puts("SHIP_TYPE_NAME: Unknown Ship (unexpected response)")
          end

          Map.put(entity, "ship_type_name", "Unknown Ship")
      end
    else
      if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
        IO.puts("SHIP_TYPE_ID: unknown (not present in data)")
        IO.puts("SHIP_TYPE_NAME: Unknown Ship (no type ID available)")
      end

      entity
    end
  end

  # Generic function to add entity information if missing
  defp add_entity_info(entity, id_key, name_key, fetch_fn, default_name) do
    if Map.has_key?(entity, id_key) do
      id = Map.get(entity, id_key)

      if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
        id_key_upper = String.upcase(id_key)
        IO.puts("#{id_key_upper}: #{id}")
      end

      case fetch_fn.(id) do
        {:ok, info} ->
          name = Map.get(info, "name", default_name)

          if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
            name_key_upper = String.upcase(name_key)
            IO.puts("#{name_key_upper}: #{name}")
          end

          Map.put(entity, name_key, name)

        error ->
          # Add explicit error logging for ESI failures
          AppLogger.kill_warn("ESI resolution failed for #{id_key}", %{
            entity_id: id,
            entity_type: id_key,
            error: inspect(error)
          })

          if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
            name_key_upper = String.upcase(name_key)
            IO.puts("#{name_key_upper}: #{default_name} (ESI error: #{inspect(error)})")
          end

          Map.put(entity, name_key, default_name)
      end
    else
      if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
        id_key_upper = String.upcase(id_key)
        name_key_upper = String.upcase(name_key)
        IO.puts("#{id_key_upper}: unknown (not present in data)")
        IO.puts("#{name_key_upper}: #{default_name} (no ID available)")
      end

      entity
    end
  end

  # Add system name to ESI data if missing
  defp enrich_with_system_name(esi_data) when is_map(esi_data) do
    # Already has a system name, no need to add it
    if Map.has_key?(esi_data, "solar_system_name") do
      system_name = Map.get(esi_data, "solar_system_name")

      # Log using IO.puts to match the killmail_tools format
      if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
        IO.puts("SOLAR_SYSTEM_NAME: #{system_name} (already present)")
      end

      esi_data
    else
      system_id = Map.get(esi_data, "solar_system_id")

      # Log using IO.puts to match the killmail_tools format
      if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
        IO.puts("SOLAR_SYSTEM_ID: #{system_id}")
      end

      # No system ID, return original data
      if is_nil(system_id) do
        if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
          IO.puts("SOLAR_SYSTEM_NAME: Unknown System (no system ID available)")
        end

        Map.put(esi_data, "solar_system_name", "Unknown System")
      else
        # Get system name and add it if found
        case ESIService.get_system_info(system_id) do
          {:ok, system_info} ->
            system_name = Map.get(system_info, "name")

            if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
              IO.puts("SOLAR_SYSTEM_NAME: #{system_name} (retrieved from ESI)")
            end

            Map.put(esi_data, "solar_system_name", system_name)

          {:error, reason} ->
            if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
              IO.puts("SOLAR_SYSTEM_NAME: Unknown System (ESI API error: #{inspect(reason)})")
            end

            Map.put(esi_data, "solar_system_name", "Unknown System")

          _ ->
            if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
              IO.puts("SOLAR_SYSTEM_NAME: Unknown System (unexpected ESI response)")
            end

            Map.put(esi_data, "solar_system_name", "Unknown System")
        end
      end
    end
  end

  defp enrich_with_system_name(data), do: data
end
