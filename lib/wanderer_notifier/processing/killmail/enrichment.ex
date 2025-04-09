defmodule WandererNotifier.Processing.Killmail.Enrichment do
  @moduledoc """
  Handles enrichment of killmail data.

  - Adds additional information from external APIs
  - Processes victim and attacker information
  - Adds system information to kills
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Processing.Killmail.Notification, as: KillNotification
  alias WandererNotifier.Resources.Killmail

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
  def enrich_killmail_data(killmail) do
    esi_data = extract_esi_data(killmail)
    log_enrichment_start(killmail.killmail_id, esi_data)

    esi_data =
      %{}
      |> Map.merge(esi_data || %{})
      |> enrich_with_system_name()
      |> enrich_victim_data(killmail.killmail_id)
      |> enrich_attackers_data(killmail.killmail_id)
      |> verify_system_enrichment(killmail.killmail_id)
      |> ensure_complete_enrichment()

    log_enrichment_completion(killmail.killmail_id, esi_data)
    update_killmail_with_enriched_data(killmail, esi_data)
  end

  defp log_enrichment_start(killmail_id, esi_data) do
    log_enrichment_header(killmail_id)
    log_initial_state(killmail_id, esi_data)
  end

  defp log_enrichment_header(killmail_id) do
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("\n=====================================================")
      IO.puts("🔍 ENRICHING KILLMAIL #{killmail_id}")
      IO.puts("=====================================================\n")
    end

    AppLogger.kill_debug("[Enrichment] Starting enrichment process for killmail #{killmail_id}")
  end

  defp log_initial_state(_killmail_id, esi_data) do
    AppLogger.kill_debug("[Enrichment] Initial state:", %{
      has_esi_data: not is_nil(esi_data),
      has_victim: is_map(esi_data) && Map.has_key?(esi_data, "victim"),
      has_attackers: is_map(esi_data) && Map.has_key?(esi_data, "attackers"),
      has_system_id: is_map(esi_data) && Map.has_key?(esi_data, "solar_system_id"),
      has_system_name: is_map(esi_data) && Map.has_key?(esi_data, "solar_system_name")
    })

    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("\n------ SOLAR SYSTEM DATA ------")
    end
  end

  defp verify_system_enrichment(esi_data, killmail_id) do
    system_name = Map.get(esi_data, "solar_system_name")
    system_id = Map.get(esi_data, "solar_system_id")

    if needs_system_name_retry?(system_name) do
      log_system_enrichment_retry(system_id, system_name, killmail_id)
      retry_system_enrichment(esi_data, system_id, system_name, killmail_id)
    else
      esi_data
    end
  end

  defp needs_system_name_retry?(system_name) do
    system_name == "Unknown System" || is_nil(system_name)
  end

  defp log_system_enrichment_retry(system_id, system_name, killmail_id) do
    AppLogger.kill_warning(
      "[Enrichment] System name not properly enriched for system ID #{system_id}",
      %{
        kill_id: killmail_id,
        system_id: system_id,
        system_name: system_name
      }
    )
  end

  defp retry_system_enrichment(esi_data, system_id, system_name, killmail_id) do
    updated_data = try_system_name_retry(esi_data)
    updated_system_name = Map.get(updated_data, "solar_system_name")

    if updated_system_name != system_name && !needs_system_name_retry?(updated_system_name) do
      log_system_enrichment_success(system_id, system_name, updated_system_name, killmail_id)
    else
      log_system_enrichment_failure(system_id, killmail_id)
    end

    updated_data
  end

  defp log_system_enrichment_success(system_id, old_name, new_name, killmail_id) do
    AppLogger.kill_info(
      "[Enrichment] Successfully re-enriched system name on retry: '#{old_name}' → '#{new_name}'",
      %{
        kill_id: killmail_id,
        system_id: system_id,
        old_name: old_name,
        new_name: new_name
      }
    )
  end

  defp log_system_enrichment_failure(system_id, killmail_id) do
    AppLogger.kill_warning(
      "[Enrichment] System name still not properly enriched after retry for system ID #{system_id}",
      %{
        kill_id: killmail_id,
        system_id: system_id
      }
    )
  end

  defp log_enrichment_completion(killmail_id, esi_data) do
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("\n=====================================================")
      IO.puts("✅ ENRICHMENT COMPLETED FOR KILLMAIL #{killmail_id}")
      IO.puts("=====================================================\n")
    end

    AppLogger.kill_debug(
      "[Enrichment] Completed enrichment process for killmail #{killmail_id}",
      %{
        system_name: Map.get(esi_data, "solar_system_name", "not set"),
        has_victim: Map.has_key?(esi_data, "victim"),
        victim_name: (Map.get(esi_data, "victim") || %{}) |> Map.get("character_name", "not set"),
        has_attackers: Map.has_key?(esi_data, "attackers"),
        attacker_count: length(Map.get(esi_data, "attackers", []))
      }
    )
  end

  defp update_killmail_with_enriched_data(killmail, esi_data) do
    if is_struct(killmail, Killmail) do
      killmail
    else
      Map.put(killmail, :esi_data, esi_data)
    end
  end

  # Helper function to extract esi_data from killmail
  defp extract_esi_data(killmail) do
    cond do
      is_struct(killmail, Killmail) ->
        # For Resources.Killmail, create a compatible esi_data structure
        %{
          "solar_system_id" => killmail.solar_system_id,
          "solar_system_name" => killmail.solar_system_name,
          "victim" => killmail.full_victim_data,
          "attackers" => killmail.full_attacker_data,
          "killmail_time" => killmail.kill_time
        }

      is_map(killmail) && Map.has_key?(killmail, :esi_data) ->
        killmail.esi_data || %{}

      is_map(killmail) ->
        Map.get(killmail, "esi_data") || Map.get(killmail, :esi_data) || %{}

      true ->
        %{}
    end
  end

  # Helper function to enrich victim data
  defp enrich_victim_data(esi_data, killmail_id) do
    if Map.has_key?(esi_data, "victim") do
      victim = Map.get(esi_data, "victim")

      # Print header for victim data
      if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
        IO.puts("\n------ VICTIM DATA ------")
      end

      AppLogger.kill_debug("[Enrichment] Processing victim data",
        kill_id: killmail_id,
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

      # Verify victim enrichment
      enriched_victim = verify_and_reenrich_victim_if_needed(enriched_victim, killmail_id)

      Map.put(esi_data, "victim", enriched_victim)
    else
      # Log and continue without adding placeholder
      AppLogger.kill_warning("[Enrichment] Missing victim data in killmail",
        kill_id: killmail_id
      )

      esi_data
    end
  end

  # Further extract victim verification to reduce nesting
  defp verify_and_reenrich_victim_if_needed(enriched_victim, killmail_id) do
    if needs_reenrichment?(enriched_victim) do
      AppLogger.kill_warning("[Enrichment] Victim data not fully enriched", %{
        kill_id: killmail_id,
        ship_type_name: Map.get(enriched_victim, "ship_type_name"),
        character_name: Map.get(enriched_victim, "character_name")
      })

      # Try to re-enrich if data is missing
      re_enriched = retry_entity_enrichment(enriched_victim)

      # Log success if we managed to get better data
      log_reenrichment_success(enriched_victim, re_enriched, killmail_id)

      # Return the re-enriched entity
      re_enriched
    else
      enriched_victim
    end
  end

  # Check if an entity needs re-enrichment
  defp needs_reenrichment?(entity) do
    Map.get(entity, "ship_type_name") == "Unknown Ship" ||
      Map.get(entity, "character_name") in [
        "Unknown Pilot",
        "Unknown",
        "Unknown Character"
      ]
  end

  # Log success of re-enrichment
  defp log_reenrichment_success(original, re_enriched, killmail_id) do
    # Log character name improvement
    if Map.get(original, "character_name") in [
         "Unknown Pilot",
         "Unknown",
         "Unknown Character"
       ] &&
         !(Map.get(re_enriched, "character_name") in [
             "Unknown Pilot",
             "Unknown",
             "Unknown Character"
           ]) do
      AppLogger.kill_info(
        "[Enrichment] Successfully re-enriched victim character name",
        %{
          kill_id: killmail_id,
          character_id: Map.get(original, "character_id"),
          old_name: Map.get(original, "character_name"),
          new_name: Map.get(re_enriched, "character_name")
        }
      )
    end

    # Log ship name improvement
    if Map.get(original, "ship_type_name") == "Unknown Ship" &&
         Map.get(re_enriched, "ship_type_name") != "Unknown Ship" do
      AppLogger.kill_info("[Enrichment] Successfully re-enriched victim ship name", %{
        kill_id: killmail_id,
        ship_type_id: Map.get(original, "ship_type_id"),
        old_name: Map.get(original, "ship_type_name"),
        new_name: Map.get(re_enriched, "ship_type_name")
      })
    end
  end

  # Helper function to enrich attackers data
  defp enrich_attackers_data(esi_data, killmail_id) do
    case Map.get(esi_data, "attackers") do
      attackers when is_list(attackers) ->
        enriched_attackers = enrich_attacker_list(attackers, killmail_id)
        log_unknown_attackers(enriched_attackers, killmail_id)
        Map.put(esi_data, "attackers", enriched_attackers)

      _ ->
        AppLogger.kill_warning("[Enrichment] Missing attackers data in killmail",
          kill_id: killmail_id
        )

        esi_data
    end
  end

  defp enrich_attacker_list(attackers, killmail_id) do
    Enum.map(attackers, fn attacker ->
      enriched = enrich_entity(attacker)
      maybe_enrich_final_blow(enriched, killmail_id)
    end)
  end

  defp maybe_enrich_final_blow(enriched, killmail_id) do
    if Map.get(enriched, "final_blow", false) do
      enrich_final_blow_attacker(enriched, killmail_id)
    else
      enriched
    end
  end

  defp enrich_final_blow_attacker(enriched, killmail_id) do
    enriched_char_name = Map.get(enriched, "character_name")
    char_id = Map.get(enriched, "character_id")

    if needs_name_resolution?(enriched_char_name) && char_id do
      updated_enriched = apply_direct_character_resolution(enriched)
      log_name_resolution_result(updated_enriched, enriched_char_name, char_id, killmail_id)
      updated_enriched
    else
      enriched
    end
  end

  defp needs_name_resolution?(name) do
    name in ["Unknown Pilot", "Unknown", "Unknown Character"]
  end

  defp log_name_resolution_result(updated_enriched, original_name, char_id, killmail_id) do
    new_name = Map.get(updated_enriched, "character_name")

    if new_name != original_name do
      AppLogger.kill_info(
        "[Enrichment] Successfully resolved character name for final blow attacker",
        %{
          kill_id: killmail_id,
          character_id: char_id,
          original_name: original_name,
          new_name: new_name
        }
      )
    end
  end

  defp log_unknown_attackers(enriched_attackers, killmail_id) do
    unknown_count =
      enriched_attackers
      |> Enum.count(&needs_name_resolution?(Map.get(&1, "character_name")))

    if unknown_count > 0 do
      AppLogger.kill_warning(
        "[Enrichment] #{unknown_count} of #{length(enriched_attackers)} attackers still have unknown character names after enrichment",
        %{kill_id: killmail_id}
      )
    end
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
    if not Map.has_key?(entity, "ship_type_id") do
      log_missing_ship_type_id()
      entity
    else
      ship_type_id = Map.get(entity, "ship_type_id")
      log_ship_type_id(ship_type_id)
      add_ship_name_from_esi(entity, ship_type_id)
    end
  end

  defp log_missing_ship_type_id do
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("SHIP_TYPE_ID: unknown (not present in data)")
      IO.puts("SHIP_TYPE_NAME: Unknown Ship (no type ID available)")
    end
  end

  defp log_ship_type_id(ship_type_id) do
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("SHIP_TYPE_ID: #{ship_type_id}")
    end
  end

  defp add_ship_name_from_esi(entity, ship_type_id) do
    case ESIService.get_ship_type_name(ship_type_id) do
      {:ok, %{"name" => name}} ->
        log_ship_name_success(name)
        Map.put(entity, "ship_type_name", name)

      {:error, reason} ->
        log_ship_name_error(reason)
        Map.put(entity, "ship_type_name", "Unknown Ship")

      _ ->
        log_ship_name_unexpected()
        Map.put(entity, "ship_type_name", "Unknown Ship")
    end
  end

  defp log_ship_name_success(name) do
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("SHIP_TYPE_NAME: #{name}")
    end
  end

  defp log_ship_name_error(reason) do
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("SHIP_TYPE_NAME: Unknown Ship (ESI error: #{inspect(reason)})")
    end
  end

  defp log_ship_name_unexpected do
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      IO.puts("SHIP_TYPE_NAME: Unknown Ship (unexpected response)")
    end
  end

  # Generic function to add entity information if missing
  defp add_entity_info(entity, id_key, name_key, fetch_fn, default_name) do
    # Get the entity ID if it exists
    id = Map.get(entity, id_key)

    if is_integer(id) || (is_binary(id) && id != "") do
      # Fetch info for entity
      fetch_and_add_entity_name(entity, id, id_key, name_key, fetch_fn, default_name)
    else
      # No ID available, add default name and log
      log_missing_entity_id(id_key, name_key, default_name)
      entity
    end
  end

  # Helper function to fetch entity information and add name to entity
  defp fetch_and_add_entity_name(entity, id, id_key, name_key, fetch_fn, default_name) do
    case fetch_fn.(id) do
      {:ok, info} ->
        name = Map.get(info, "name", default_name)
        log_successful_name_lookup(name_key, name)
        Map.put(entity, name_key, name)

      error ->
        # Add explicit error logging for ESI failures
        log_failed_name_lookup(id_key, name_key, id, error, default_name)
        Map.put(entity, name_key, default_name)
    end
  end

  # Helper function to log successful name lookup
  defp log_successful_name_lookup(name_key, name) do
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      name_key_upper = String.upcase(name_key)
      IO.puts("#{name_key_upper}: #{name}")
    end
  end

  # Helper function to log failed name lookup
  defp log_failed_name_lookup(id_key, name_key, id, error, default_name) do
    AppLogger.kill_warn("ESI resolution failed for #{id_key}", %{
      entity_id: id,
      entity_type: id_key,
      error: inspect(error)
    })

    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      name_key_upper = String.upcase(name_key)
      IO.puts("#{name_key_upper}: #{default_name} (ESI error: #{inspect(error)})")
    end
  end

  # Helper function to log missing entity ID
  defp log_missing_entity_id(id_key, name_key, default_name) do
    if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
      id_key_upper = String.upcase(id_key)
      name_key_upper = String.upcase(name_key)
      IO.puts("#{id_key_upper}: unknown (not present in data)")
      IO.puts("#{name_key_upper}: #{default_name} (no ID available)")
    end
  end

  # Enrich with system name if needed
  defp enrich_with_system_name(esi_data) when is_map(esi_data) do
    # Already has a system name, no need to add it
    if Map.has_key?(esi_data, "solar_system_name") &&
         Map.get(esi_data, "solar_system_name") != "Unknown System" do
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
        # Get system name using the cached function to ensure we have proper retries and caching
        case get_system_name_with_retries(system_id) do
          {:ok, system_name} when is_binary(system_name) and system_name != "" ->
            # Log success
            AppLogger.kill_info("[Enrichment] Retrieved system name", %{
              system_id: system_id,
              system_name: system_name
            })

            if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
              IO.puts("SOLAR_SYSTEM_NAME: #{system_name} (retrieved from ESI or cache)")
            end

            # Always update the name to avoid using previous placeholder values
            Map.put(esi_data, "solar_system_name", system_name)

          _ ->
            AppLogger.kill_warn("[Enrichment] Failed to get system name after retries", %{
              system_id: system_id
            })

            if Application.get_env(:wanderer_notifier, :log_next_killmail, false) do
              IO.puts("SOLAR_SYSTEM_NAME: Unknown System (all retrieval attempts failed)")
            end

            Map.put(esi_data, "solar_system_name", "Unknown System")
        end
      end
    end
  end

  defp enrich_with_system_name(data), do: data

  # Get system name with retries
  defp get_system_name_with_retries(system_id, max_attempts \\ 3) do
    get_system_name_with_retry(system_id, 1, max_attempts)
  end

  # Recursive function to try getting system name with exponential backoff
  defp get_system_name_with_retry(_system_id, attempt, max_attempts)
       when attempt > max_attempts do
    {:error, :max_retries_exceeded}
  end

  defp get_system_name_with_retry(system_id, attempt, max_attempts) do
    case try_get_system_name_from_cache(system_id) do
      name when is_binary(name) and name != "" ->
        log_system_name_cache_hit(system_id, name, attempt)
        {:ok, name}

      _ ->
        try_get_system_name_from_esi(system_id, attempt, max_attempts)
    end
  end

  defp try_get_system_name_from_esi(system_id, attempt, max_attempts) do
    case ESIService.get_system_info(system_id) do
      {:ok, system_info} ->
        handle_system_info_response(system_info, system_id, attempt, max_attempts)

      error ->
        handle_system_error_response(error, system_id, attempt, max_attempts)
    end
  end

  defp handle_system_info_response(system_info, system_id, attempt, max_attempts) do
    case Map.get(system_info, "name") do
      name when is_binary(name) and name != "" ->
        log_system_name_success(system_id, name, attempt)
        cache_system_info(system_id, system_info)
        {:ok, name}

      _ ->
        retry_system_name_lookup(system_id, attempt, max_attempts)
    end
  end

  defp handle_system_error_response(error, system_id, attempt, max_attempts) do
    log_system_name_error(system_id, attempt, error)
    retry_system_name_lookup(system_id, attempt, max_attempts)
  end

  defp retry_system_name_lookup(system_id, attempt, max_attempts) do
    backoff = calculate_backoff_time(attempt)
    Process.sleep(backoff)
    get_system_name_with_retry(system_id, attempt + 1, max_attempts)
  end

  defp log_system_name_cache_hit(system_id, name, attempt) do
    AppLogger.kill_debug("[Enrichment] Found system name in cache", %{
      system_id: system_id,
      name: name,
      attempt: attempt
    })
  end

  defp log_system_name_success(system_id, name, attempt) do
    AppLogger.kill_debug("[Enrichment] Retrieved system name from ESI", %{
      system_id: system_id,
      name: name,
      attempt: attempt
    })
  end

  defp log_system_name_error(system_id, attempt, error) do
    AppLogger.kill_debug("[Enrichment] ESI error, retrying after backoff", %{
      system_id: system_id,
      attempt: attempt,
      error: inspect(error)
    })
  end

  defp cache_system_info(system_id, system_info) do
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    cache_key = CacheKeys.system_info(system_id)
    CacheRepo.set(cache_key, system_info, 30 * 86_400)
  end

  # Retry entity enrichment if critical data is missing
  defp retry_entity_enrichment(entity) when is_map(entity) do
    # Only retry if we have character_id (critical for lookup)
    if Map.has_key?(entity, "character_id") do
      character_id = Map.get(entity, "character_id")

      AppLogger.kill_info(
        "[Enrichment] Retrying entity enrichment for character_id #{character_id}"
      )

      # Copy the original entity for modifications
      updated_entity = entity

      # Try to get a better name if current one is placeholder
      updated_entity =
        if Map.get(entity, "character_name") in ["Unknown Pilot", "Unknown", "Unknown Character"] do
          # Use the get_character_name_with_cache function for better caching
          case get_character_name_with_cache(character_id) do
            {:ok, name} when is_binary(name) and name != "" ->
              AppLogger.kill_info(
                "[Enrichment] Retrieved better character name on retry: #{name}",
                %{
                  character_id: character_id,
                  old_name: Map.get(entity, "character_name"),
                  new_name: name
                }
              )

              Map.put(updated_entity, "character_name", name)

            _ ->
              updated_entity
          end
        else
          updated_entity
        end

      # Try to get better ship name if current one is placeholder
      updated_entity =
        if Map.get(updated_entity, "ship_type_name") == "Unknown Ship" &&
             Map.has_key?(updated_entity, "ship_type_id") do
          ship_type_id = Map.get(updated_entity, "ship_type_id")

          # Use the get_ship_type_name_with_cache function for better caching
          case get_ship_type_name_with_cache(ship_type_id) do
            {:ok, name} when is_binary(name) and name != "" ->
              AppLogger.kill_info("[Enrichment] Retrieved better ship name on retry: #{name}", %{
                ship_type_id: ship_type_id,
                old_name: Map.get(updated_entity, "ship_type_name"),
                new_name: name
              })

              Map.put(updated_entity, "ship_type_name", name)

            _ ->
              updated_entity
          end
        else
          updated_entity
        end

      updated_entity
    else
      entity
    end
  end

  # Get character name with caching and retries
  defp get_character_name_with_cache(character_id, max_attempts \\ 3) do
    get_character_name_with_retry(character_id, 1, max_attempts)
  end

  defp get_character_name_with_retry(_character_id, attempt, max_attempts)
       when attempt > max_attempts do
    {:error, :max_retries_exceeded}
  end

  defp get_character_name_with_retry(character_id, attempt, max_attempts) do
    case try_get_character_name_from_cache(character_id) do
      {:ok, name} -> {:ok, name}
      _ -> try_get_character_name_from_esi(character_id, attempt, max_attempts)
    end
  end

  defp try_get_character_name_from_cache(character_id) do
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    cache_key = CacheKeys.character_info(character_id)

    case CacheRepo.get(cache_key) do
      %{"name" => name} when is_binary(name) and name != "" ->
        log_character_name_cache_hit(character_id, name)
        {:ok, name}

      _ ->
        {:error, :not_in_cache}
    end
  end

  defp try_get_character_name_from_esi(character_id, attempt, max_attempts) do
    case ESIService.get_character_info(character_id) do
      {:ok, character_info} when is_map(character_info) ->
        handle_character_info_response(character_info, character_id, attempt, max_attempts)

      error ->
        handle_character_error_response(error, character_id, attempt, max_attempts)
    end
  end

  defp handle_character_info_response(character_info, character_id, attempt, max_attempts) do
    case Map.get(character_info, "name") do
      name when is_binary(name) and name != "" ->
        log_character_name_success(character_id, name, attempt)
        cache_character_info(character_id, character_info)
        {:ok, name}

      _ ->
        retry_character_name_lookup(character_id, attempt, max_attempts)
    end
  end

  defp handle_character_error_response(error, character_id, attempt, max_attempts) do
    log_character_name_error(character_id, attempt, error)
    retry_character_name_lookup(character_id, attempt, max_attempts)
  end

  defp retry_character_name_lookup(character_id, attempt, max_attempts) do
    backoff = calculate_backoff_time(attempt)
    Process.sleep(backoff)
    get_character_name_with_retry(character_id, attempt + 1, max_attempts)
  end

  defp log_character_name_cache_hit(character_id, name) do
    AppLogger.kill_debug("[Enrichment] Found character name in cache", %{
      character_id: character_id,
      name: name
    })
  end

  defp log_character_name_success(character_id, name, attempt) do
    AppLogger.kill_debug("[Enrichment] Retrieved character name from ESI", %{
      character_id: character_id,
      name: name,
      attempt: attempt
    })
  end

  defp log_character_name_error(character_id, attempt, error) do
    AppLogger.kill_debug("[Enrichment] ESI error for character, retrying after backoff", %{
      character_id: character_id,
      attempt: attempt,
      error: inspect(error)
    })
  end

  defp cache_character_info(character_id, character_info) do
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    cache_key = CacheKeys.character_info(character_id)
    CacheRepo.set(cache_key, character_info, 7 * 86_400)
  end

  # Get ship type name with caching and retries
  defp get_ship_type_name_with_cache(ship_type_id, max_attempts \\ 3) do
    get_ship_type_name_with_retry(ship_type_id, 1, max_attempts)
  end

  # Recursive function to try getting ship type name with exponential backoff
  defp get_ship_type_name_with_retry(_ship_type_id, attempt, max_attempts)
       when attempt > max_attempts do
    {:error, :max_retries_exceeded}
  end

  defp get_ship_type_name_with_retry(ship_type_id, attempt, max_attempts) do
    case try_get_ship_name_from_cache(ship_type_id) do
      {:ok, name} -> {:ok, name}
      _ -> try_get_ship_name_from_esi(ship_type_id, attempt, max_attempts)
    end
  end

  defp try_get_ship_name_from_cache(ship_type_id) do
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    cache_key = CacheKeys.ship_info(ship_type_id)

    case CacheRepo.get(cache_key) do
      %{"name" => name} when is_binary(name) and name != "" ->
        log_ship_name_cache_hit(ship_type_id, name)
        {:ok, name}

      _ ->
        {:error, :not_in_cache}
    end
  end

  defp try_get_ship_name_from_esi(ship_type_id, attempt, max_attempts) do
    case ESIService.get_ship_type_name(ship_type_id) do
      {:ok, ship_info} when is_map(ship_info) ->
        handle_ship_info_response(ship_info, ship_type_id, attempt, max_attempts)

      error ->
        handle_ship_error_response(error, ship_type_id, attempt, max_attempts)
    end
  end

  defp handle_ship_info_response(ship_info, ship_type_id, attempt, max_attempts) do
    case Map.get(ship_info, "name") do
      name when is_binary(name) and name != "" ->
        log_ship_name_success(ship_type_id, name, attempt)
        cache_ship_info(ship_type_id, ship_info)
        {:ok, name}

      _ ->
        retry_ship_name_lookup(ship_type_id, attempt, max_attempts)
    end
  end

  defp handle_ship_error_response(error, ship_type_id, attempt, max_attempts) do
    log_ship_name_error(ship_type_id, attempt, error)
    retry_ship_name_lookup(ship_type_id, attempt, max_attempts)
  end

  defp retry_ship_name_lookup(ship_type_id, attempt, max_attempts) do
    backoff = calculate_backoff_time(attempt)
    Process.sleep(backoff)
    get_ship_type_name_with_retry(ship_type_id, attempt + 1, max_attempts)
  end

  defp log_ship_name_cache_hit(ship_type_id, name) do
    AppLogger.kill_debug("[Enrichment] Found ship name in cache", %{
      ship_type_id: ship_type_id,
      name: name
    })
  end

  defp log_ship_name_success(ship_type_id, name, attempt) do
    AppLogger.kill_debug("[Enrichment] Retrieved ship name from ESI", %{
      ship_type_id: ship_type_id,
      name: name,
      attempt: attempt
    })
  end

  defp log_ship_name_error(ship_type_id, attempt, error) do
    AppLogger.kill_debug("[Enrichment] ESI error for ship, retrying after backoff", %{
      ship_type_id: ship_type_id,
      attempt: attempt,
      error: inspect(error)
    })
  end

  defp cache_ship_info(ship_type_id, ship_info) do
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    cache_key = CacheKeys.ship_info(ship_type_id)
    CacheRepo.set(cache_key, ship_info, 90 * 86_400)
  end

  defp calculate_backoff_time(attempt) do
    (:math.pow(2, attempt) * 100) |> round()
  end

  # Try again to get system name
  defp try_system_name_retry(esi_data) do
    if Map.has_key?(esi_data, "solar_system_id") do
      system_id = Map.get(esi_data, "solar_system_id")

      AppLogger.kill_info(
        "[Enrichment] Retrying system name enrichment for system_id #{system_id}"
      )

      # Try with more retries and a different approach
      # Increase max attempts to 5
      case get_system_name_with_retries(system_id, 5) do
        {:ok, system_name} when is_binary(system_name) and system_name != "" ->
          AppLogger.kill_info(
            "[Enrichment] Retrieved better system name on retry: #{system_name}",
            %{
              system_id: system_id,
              old_name: Map.get(esi_data, "solar_system_name", "Unknown System"),
              new_name: system_name
            }
          )

          # Update at top level
          updated_esi_data = Map.put(esi_data, "solar_system_name", system_name)

          # Also ensure it's in victim data if present
          updated_esi_data =
            if victim = Map.get(updated_esi_data, "victim") do
              updated_victim = Map.put(victim, "solar_system_name", system_name)
              Map.put(updated_esi_data, "victim", updated_victim)
            else
              updated_esi_data
            end

          # Also update attackers if present
          updated_esi_data =
            if attackers = Map.get(updated_esi_data, "attackers") do
              updated_attackers =
                Enum.map(attackers, fn attacker ->
                  Map.put(attacker, "solar_system_name", system_name)
                end)

              Map.put(updated_esi_data, "attackers", updated_attackers)
            else
              updated_esi_data
            end

          updated_esi_data

        _ ->
          esi_data
      end
    else
      esi_data
    end
  end

  # Ensure all enriched data is complete and consistent across the structure
  defp ensure_complete_enrichment(esi_data) when is_map(esi_data) do
    best_system_name = determine_best_system_name(esi_data)
    update_system_names(esi_data, best_system_name)
  end

  defp ensure_complete_enrichment(data), do: data

  defp determine_best_system_name(esi_data) do
    top_level_system_name = Map.get(esi_data, "solar_system_name")
    victim = Map.get(esi_data, "victim", %{})
    victim_system_name = Map.get(victim, "solar_system_name")

    cond do
      is_valid_system_name?(top_level_system_name) ->
        top_level_system_name

      is_valid_system_name?(victim_system_name) ->
        victim_system_name

      system_id = Map.get(esi_data, "solar_system_id") ->
        fetch_system_name(system_id, top_level_system_name)

      true ->
        top_level_system_name || "Unknown System"
    end
  end

  defp is_valid_system_name?(name) do
    is_binary(name) && name != "" && name != "Unknown System"
  end

  defp fetch_system_name(system_id, fallback_name) do
    case get_system_name_with_retries(system_id, 3) do
      {:ok, name} when is_binary(name) and name != "" ->
        log_system_name_fetch_success(system_id, name)
        name

      _ ->
        fallback_name || "Unknown System"
    end
  end

  defp log_system_name_fetch_success(system_id, name) do
    AppLogger.kill_info(
      "[Enrichment] Retrieved system name in final consistency check",
      %{
        system_id: system_id,
        system_name: name
      }
    )
  end

  defp update_system_names(esi_data, system_name) do
    esi_data
    |> Map.put("solar_system_name", system_name)
    |> update_victim_system_name(system_name)
  end

  defp update_victim_system_name(esi_data, system_name) do
    if Map.has_key?(esi_data, "victim") do
      victim = Map.get(esi_data, "victim")
      updated_victim = Map.put(victim, "solar_system_name", system_name)
      Map.put(esi_data, "victim", updated_victim)
    else
      esi_data
    end
  end

  # Direct resolution for character name
  defp apply_direct_character_resolution(entity) when is_map(entity) do
    if character_id = Map.get(entity, "character_id") do
      # Use direct ESI service call to bypass caching issues
      case ESIService.get_character_info(character_id) do
        {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
          AppLogger.kill_info(
            "[Enrichment] Direct character resolution succeeded for character_id #{character_id}",
            %{
              character_id: character_id,
              old_name: Map.get(entity, "character_name"),
              new_name: name
            }
          )

          # Always update the cache with this fresh data
          alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
          alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
          cache_key = CacheKeys.character_info(character_id)
          CacheRepo.set(cache_key, %{"name" => name}, 86_400)

          # Return entity with updated name
          Map.put(entity, "character_name", name)

        error ->
          AppLogger.kill_error("[Enrichment] Direct character resolution failed", %{
            character_id: character_id,
            error: inspect(error)
          })

          entity
      end
    else
      entity
    end
  end

  defp apply_direct_character_resolution(entity), do: entity

  # Try to get system name from cache
  defp try_get_system_name_from_cache(system_id) do
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
    cache_key = CacheKeys.system_info(system_id)

    case CacheRepo.get(cache_key) do
      %{"name" => name} when is_binary(name) and name != "" ->
        name

      _ ->
        nil
    end
  end
end
