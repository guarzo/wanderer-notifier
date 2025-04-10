defmodule WandererNotifier.Processing.Killmail.Enrichment do
  @moduledoc """
  Module for enriching killmail data with additional information.
  Retrieves solar system names, character names, and other details.
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.KillmailProcessing.Extractor
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Processing.Killmail.Notification

  @doc """
  Process the killmail for enrichment and notification.
  Called by the Core module to process enrichment and send notification.

  ## Parameters
    - killmail: The killmail data structure

  ## Returns
    - {:ok, killmail} if processed successfully
    - {:ok, :skipped} if skipped
    - {:error, reason} if an error occurred
  """
  @spec process_and_notify(map()) :: {:ok, map() | :skipped} | {:error, any()}
  def process_and_notify(killmail) do
    # First enrich the killmail data
    enriched_killmail = enrich_killmail_data(killmail)

    # Check if notification should be sent
    kill_id = Extractor.get_killmail_id(enriched_killmail)

    case Notification.send_kill_notification(enriched_killmail, kill_id) do
      {:ok, _} ->
        AppLogger.kill_debug("Successfully processed and notified killmail ##{kill_id}")
        {:ok, enriched_killmail}

      {:error, reason} ->
        AppLogger.kill_error("Failed to process notification for killmail ##{kill_id}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      AppLogger.kill_error("Exception in enrichment processing for killmail ##{Map.get(killmail, :killmail_id, "unknown")}: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  @doc """
  Enriches killmail data with additional information from ESI API.
  Retrieves solar system names, character information, etc.
  """
  @spec enrich_killmail_data(map()) :: map()
  def enrich_killmail_data(killmail) do
    # Get basic info for logging
    kill_id = Map.get(killmail, :killmail_id) || "unknown"

    # Simple log message
    AppLogger.kill_debug("ENRICHMENT: Starting for kill ##{kill_id}")

    # Get ESI data from killmail if available
    esi_data = Map.get(killmail, :esi_data) || %{}

    # Add system name if needed
    enriched_esi_data = enrich_with_system_name(esi_data)

    # Log victim data before enrichment
    log_victim_data_before_enrichment(kill_id, esi_data)

    # Ensure all data is complete and consistent
    complete_esi_data = ensure_complete_enrichment(enriched_esi_data)

    # Log successful enrichment and the data we found
    log_enrichment_results(kill_id, complete_esi_data)

    # Create the updated killmail with enriched data at top level
    enriched_killmail = Map.put(killmail, :esi_data, complete_esi_data)

    # Now update the top-level fields with the enriched data
    victim = Map.get(complete_esi_data, "victim") || %{}
    victim_id = Map.get(victim, "character_id")
    victim_name = Map.get(victim, "character_name")
    victim_ship_id = Map.get(victim, "ship_type_id")
    victim_ship = Map.get(victim, "ship_type_name")
    victim_corp_id = Map.get(victim, "corporation_id")
    victim_corp_name = Map.get(victim, "corporation_name")
    victim_alliance_id = Map.get(victim, "alliance_id")
    victim_alliance_name = Map.get(victim, "alliance_name")

    system_id = Map.get(complete_esi_data, "solar_system_id")
    system_name = Map.get(complete_esi_data, "solar_system_name")
    system_security = Map.get(complete_esi_data, "security_status")

    # Get attackers and final blow details
    attackers = Map.get(complete_esi_data, "attackers") || []
    attacker_count = length(attackers)

    # Find final blow attacker
    final_blow_attacker = Enum.find(attackers, fn attacker ->
      Map.get(attacker, "final_blow", false) == true
    end) || %{}

    final_blow_attacker_id = Map.get(final_blow_attacker, "character_id")
    final_blow_attacker_name = Map.get(final_blow_attacker, "character_name")
    final_blow_ship_id = Map.get(final_blow_attacker, "ship_type_id")
    final_blow_ship_name = Map.get(final_blow_attacker, "ship_type_name")

    # Get zkb data for economic info
    zkb_data = Map.get(killmail, :zkb_data) || %{}
    total_value = Map.get(zkb_data, "totalValue")
    is_npc = Map.get(zkb_data, "npc", false)

    # Create fully enriched killmail with all data both in esi_data and at top level
    fully_enriched = enriched_killmail
      |> maybe_put(:victim, victim)
      |> maybe_put(:solar_system_id, system_id)
      |> maybe_put(:solar_system_name, system_name)
      |> maybe_put(:solar_system_security, system_security)
      |> maybe_put(:victim_id, victim_id)
      |> maybe_put(:victim_name, victim_name)
      |> maybe_put(:victim_ship_id, victim_ship_id)
      |> maybe_put(:victim_ship_name, victim_ship)
      |> maybe_put(:victim_corporation_id, victim_corp_id)
      |> maybe_put(:victim_corporation_name, victim_corp_name)
      |> maybe_put(:victim_alliance_id, victim_alliance_id)
      |> maybe_put(:victim_alliance_name, victim_alliance_name)
      |> maybe_put(:attacker_count, attacker_count)
      |> maybe_put(:final_blow_attacker_id, final_blow_attacker_id)
      |> maybe_put(:final_blow_attacker_name, final_blow_attacker_name)
      |> maybe_put(:final_blow_ship_id, final_blow_ship_id)
      |> maybe_put(:final_blow_ship_name, final_blow_ship_name)
      |> maybe_put(:total_value, total_value)
      |> maybe_put(:is_npc, is_npc)

    # Log that we've updated top-level data
    AppLogger.kill_debug("ENRICHMENT: Updated top-level data for Kill ##{kill_id}: " <>
      "victim=#{victim_name || "nil"}, ship=#{victim_ship || "nil"}, system=#{system_name || "nil"}, " <>
      "attackers=#{attacker_count}, value=#{total_value || 0}")

    # Return the fully enriched killmail
    fully_enriched
  rescue
    e ->
      AppLogger.kill_error("ENRICHMENT ERROR: Kill ##{Map.get(killmail, :killmail_id, "unknown")}: #{Exception.message(e)}")

      # Return original killmail to prevent pipeline failure
      killmail
  end

  # Helper to conditionally update a field only if value is not nil
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Log victim data before enrichment to help diagnose issues
  defp log_victim_data_before_enrichment(kill_id, esi_data) do
    victim = Map.get(esi_data, "victim") || %{}
    victim_id = Map.get(victim, "character_id")
    victim_name = Map.get(victim, "character_name")
    ship_type_id = Map.get(victim, "ship_type_id")
    ship_type_name = Map.get(victim, "ship_type_name")

    AppLogger.kill_debug("ENRICHMENT: Kill ##{kill_id} - Raw victim data: " <>
                      "ID: #{victim_id || "missing"}, " <>
                      "Name: #{victim_name || "missing"}, " <>
                      "Ship ID: #{ship_type_id || "missing"}, " <>
                      "Ship Name: #{ship_type_name || "missing"}")
  end

  # Log enrichment results
  defp log_enrichment_results(kill_id, esi_data) do
    victim = Map.get(esi_data, "victim") || %{}
    victim_name = Map.get(victim, "character_name") || "Unknown Pilot"
    victim_ship = Map.get(victim, "ship_type_name") || "Unknown Ship"
    system_name = Map.get(esi_data, "solar_system_name") || "Unknown System"

    AppLogger.kill_debug("ENRICHMENT: Completed for kill ##{kill_id} - #{victim_name} (#{victim_ship}) in #{system_name}")
  end

  # Enrich with system name if needed
  defp enrich_with_system_name(esi_data) when is_map(esi_data) do
    system_id = Map.get(esi_data, "solar_system_id")

    # Log the actual system ID and type for debugging
    log_system_id_info(system_id)

    if is_nil(system_id) do
      # No system ID available, can't enrich
      esi_data
    else
      # Get normalized system ID and enrich with system name
      normalized_id = normalize_system_id(system_id)
      add_system_name_to_data(esi_data, normalized_id)
    end
  end

  defp enrich_with_system_name(data), do: data

  # Log system ID type and value for debugging
  defp log_system_id_info(system_id) do
    _system_type =
      cond do
        is_integer(system_id) -> "integer"
        is_binary(system_id) -> "string"
        true -> "other: #{inspect(system_id)}"
      end
  end

  # Convert system_id to integer if needed
  defp normalize_system_id(system_id) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {id, _} -> id
      :error -> nil
    end
  end

  defp normalize_system_id(system_id) when is_integer(system_id), do: system_id
  defp normalize_system_id(_), do: nil

  # Add system name to ESI data
  defp add_system_name_to_data(esi_data, normalized_id) when is_integer(normalized_id) do
    case ESIService.get_solar_system_name(normalized_id) do
      {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
        # Set the system name in ESI data and ensure system_id is stored as integer
        esi_data
        |> Map.put("solar_system_name", name)
        |> Map.put("solar_system_id", normalized_id)

      _ ->
        # Could not get system name, use a placeholder
        Map.put(esi_data, "solar_system_name", "Unknown System")
    end
  end

  defp add_system_name_to_data(esi_data, _) do
    Map.put(esi_data, "solar_system_name", "Unknown System")
  end

  # Ensure all enriched data is complete and consistent across the structure
  defp ensure_complete_enrichment(esi_data) when is_map(esi_data) do
    # Copy system info to victim data if needed
    system_name = Map.get(esi_data, "solar_system_name")
    victim = Map.get(esi_data, "victim")

    updated_esi_data = esi_data

    # First ensure system name is added to victim data
    updated_esi_data =
      if is_binary(system_name) && is_map(victim) && !Map.has_key?(victim, "solar_system_name") do
        # Add system name to victim data
        updated_victim = Map.put(victim, "solar_system_name", system_name)
        Map.put(updated_esi_data, "victim", updated_victim)
      else
        updated_esi_data
      end

    # Now ensure victim has character and ship names
    updated_esi_data = enrich_victim_data(updated_esi_data)

    # Finally, enhance attackers with names if needed
    updated_esi_data = enrich_attacker_data(updated_esi_data)

    # Return the fully enriched data
    updated_esi_data
  end

  defp ensure_complete_enrichment(data), do: data

  # Enrich victim data with additional details like character name and ship name
  defp enrich_victim_data(esi_data) do
    victim = Map.get(esi_data, "victim")

    if is_map(victim) do
      # Check for character_name
      updated_victim = ensure_character_name(victim)

      # Check for ship name
      updated_victim = ensure_ship_name(updated_victim)

      # Update the ESI data with enriched victim data
      Map.put(esi_data, "victim", updated_victim)
    else
      esi_data
    end
  end

  # Ensure character_name is present in data with character_id
  defp ensure_character_name(character_data) do
    # Check if we need to add a character name
    has_id = is_map(character_data) && Map.has_key?(character_data, "character_id")
    has_name = is_map(character_data) && Map.has_key?(character_data, "character_name")

    cond do
      # Case 1: Has ID but no name - try to look up the name
      has_id && !has_name ->
        character_id = Map.get(character_data, "character_id")
        lookup_and_add_character_name(character_data, character_id)

      # Case 2: No name (and no ID) - add default name
      !has_name ->
        AppLogger.kill_debug("ENRICHMENT: Adding default character name - no ID available")
        Map.put(character_data, "character_name", "Unknown Pilot")

      # Case 3: Already has a name, but let's check if it's valid
      has_name && Map.get(character_data, "character_name") in ["Unknown", "Unknown Pilot"] ->
        # If we already have an "Unknown" name but we have a character ID, try to enrich
        if has_id do
          character_id = Map.get(character_data, "character_id")
          AppLogger.kill_debug("ENRICHMENT: Trying to replace placeholder name for ID #{character_id}")
          lookup_and_add_character_name(character_data, character_id)
        else
          character_data
        end

      # Case 4: Already has a valid name
      true ->
        character_data
    end
  end

  # Helper to look up character name by ID
  defp lookup_and_add_character_name(character_data, character_id) do
    if is_integer(character_id) || is_binary(character_id) do
      # Try to get character name from ESI or existing data
      AppLogger.kill_debug("ENRICHMENT: Looking up character name for ID #{character_id}")

      # First try to look up in Repository - this should check cache first
      case WandererNotifier.Data.Repository.get_character_name(character_id) do
        # Direct name from repository
        {:ok, name} when is_binary(name) and name != "" and name not in ["Unknown", "Unknown Pilot"] ->
          AppLogger.kill_debug("ENRICHMENT: Found character name '#{name}' in repository for ID #{character_id}")
          Map.put(character_data, "character_name", name)

        # Handle cached map data case
        {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
          AppLogger.kill_debug("ENRICHMENT: Found character name '#{name}' in cached map for ID #{character_id}")
          Map.put(character_data, "character_name", name)

        # Handle the case where we get a map directly (as seen in logs)
        %{"name" => name} when is_binary(name) and name != "" ->
          AppLogger.kill_debug("ENRICHMENT: Found character name '#{name}' in direct map for ID #{character_id}")
          Map.put(character_data, "character_name", name)

        _ ->
          # No valid name in repository/cache, try direct ESI call
          case get_character_name(character_id) do
            # Standard ESI response
            {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
              AppLogger.kill_debug("ENRICHMENT: Found character name '#{name}' via ESI for ID #{character_id}")
              Map.put(character_data, "character_name", name)

            # Handle Character struct case
            {:ok, %{name: name}} when is_binary(name) and name != "" ->
              AppLogger.kill_debug("ENRICHMENT: Found character name '#{name}' in Character struct for ID #{character_id}")
              Map.put(character_data, "character_name", name)

            # Handle direct map with atom keys - can't use map[:name] in guard
            {:ok, map} when is_map(map) ->
              name = Map.get(map, :name)
              if is_binary(name) and name != "" do
                AppLogger.kill_debug("ENRICHMENT: Found character name '#{name}' in map with atom keys for ID #{character_id}")
                Map.put(character_data, "character_name", name)
              else
                AppLogger.kill_error("ENRICHMENT: Failed to find valid name in map for ID #{character_id} - #{inspect(map)}")
                Map.put(character_data, "character_name", "Unknown Pilot")
              end

            error ->
              AppLogger.kill_error("ENRICHMENT: Failed to find character name for ID #{character_id} - #{inspect(error)}")
              Map.put(character_data, "character_name", "Unknown Pilot")
          end
      end
    else
      AppLogger.kill_debug("ENRICHMENT: No valid character_id present - can't lookup name")
      Map.put(character_data, "character_name", "Unknown Pilot")
    end
  end

  # Ensure ship_type_name is present in data with ship_type_id
  defp ensure_ship_name(character_data) do
    # Check if we need to add a ship name
    has_ship_id = is_map(character_data) && Map.has_key?(character_data, "ship_type_id")
    has_ship_name = is_map(character_data) && Map.has_key?(character_data, "ship_type_name")

    cond do
      # Case 1: Has ship ID but no ship name - try to look up the name
      has_ship_id && !has_ship_name ->
        ship_type_id = Map.get(character_data, "ship_type_id")
        lookup_and_add_ship_name(character_data, ship_type_id)

      # Case 2: No ship name (and no ship ID) - add default name
      !has_ship_name ->
        AppLogger.kill_debug("ENRICHMENT: Adding default ship name - no ID available")
        Map.put(character_data, "ship_type_name", "Unknown Ship")

      # Case 3: Already has a ship name
      true ->
        character_data
    end
  end

  # Helper to look up ship name by ID
  defp lookup_and_add_ship_name(character_data, ship_type_id) do
    if is_integer(ship_type_id) || is_binary(ship_type_id) do
      # Try to get ship name from ESI
      AppLogger.kill_debug("ENRICHMENT: Looking up ship name for ID #{ship_type_id}")

      case get_ship_name(ship_type_id) do
        {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
          AppLogger.kill_debug("ENRICHMENT: Found ship name '#{name}' for ID #{ship_type_id}")
          Map.put(character_data, "ship_type_name", name)
        error ->
          AppLogger.kill_error("ENRICHMENT: Failed to find ship name for ID #{ship_type_id} - #{inspect(error)}")
          Map.put(character_data, "ship_type_name", "Unknown Ship")
      end
    else
      AppLogger.kill_debug("ENRICHMENT: No valid ship_type_id present - can't lookup name")
      Map.put(character_data, "ship_type_name", "Unknown Ship")
    end
  end

  # Enrich attackers data
  defp enrich_attacker_data(esi_data) do
    attackers = Map.get(esi_data, "attackers")

    if is_list(attackers) do
      # Process each attacker to enrich them
      updated_attackers = Enum.map(attackers, fn attacker ->
        attacker
        |> ensure_character_name()
        |> ensure_ship_name()
      end)

      # Update ESI data with enriched attackers
      Map.put(esi_data, "attackers", updated_attackers)
    else
      esi_data
    end
  end

  # Get character name from ESI
  defp get_character_name(character_id) do
    # First convert character_id to integer if it's a string
    character_id =
      if is_binary(character_id) do
        case Integer.parse(character_id) do
          {id, _} -> id
          :error -> character_id
        end
      else
        character_id
      end

    # Now try to get name from ESI
    try do
      # Import the ESI service
      alias WandererNotifier.Api.ESI.Service, as: ESIService

      ESIService.get_character_name(character_id)
    rescue
      e ->
        AppLogger.api_info("Exception getting character name: #{Exception.message(e)}")
        {:error, :exception}
    end
  end

  # Get ship name from ESI
  defp get_ship_name(ship_type_id) do
    # First convert ship_type_id to integer if it's a string
    ship_type_id =
      if is_binary(ship_type_id) do
        case Integer.parse(ship_type_id) do
          {id, _} -> id
          :error -> ship_type_id
        end
      else
        ship_type_id
      end

    # Now try to get name from ESI
    try do
      # Import the ESI service
      alias WandererNotifier.Api.ESI.Service, as: ESIService

      ESIService.get_type_name(ship_type_id)
    rescue
      e ->
        AppLogger.api_info("Exception getting ship name: #{Exception.message(e)}")
        {:error, :exception}
    end
  end
end
