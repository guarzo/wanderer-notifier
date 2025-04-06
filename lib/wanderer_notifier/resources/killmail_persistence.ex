defmodule WandererNotifier.Resources.KillmailPersistence do
  use Ash.Resource,
    domain: WandererNotifier.Resources.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  @moduledoc """
  Handles persistence of killmails to database for historical analysis and reporting.
  """

  @behaviour WandererNotifier.Resources.KillmailPersistenceBehaviour

  # Suppress dialyzer warnings for functions used indirectly
  @dialyzer {:nowarn_function,
             [
               update_recent_killmails_cache: 1,
               update_character_killmails_cache: 1,
               transform_killmail_to_resource: 4,
               parse_integer: 1,
               parse_decimal: 1,
               get_kill_time: 1,
               find_attacker_by_character_id: 2,
               create_killmail_record: 1
             ]}

  require Ash.Query
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Killmail, as: KillmailStruct
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Utils.ListUtils
  alias WandererNotifier.Api.ESI.Service, as: ESIService

  # Cache TTL for processed kill IDs - 24 hours
  @processed_kills_ttl_seconds 86_400
  # TTL for zkillboard data - 1 hour
  @zkillboard_cache_ttl_seconds 3600

  postgres do
    table("killmails")
    repo(WandererNotifier.Data.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:killmail_id, :integer)
    attribute(:zkb_data, :map)
    attribute(:esi_data, :map)
    timestamps()
  end

  # Gets list of tracked characters from the cache
  defp get_tracked_characters do
    # Get characters from cache and ensure we return a proper list
    characters = CacheRepo.get(CacheKeys.character_list()) || []

    AppLogger.persistence_info("Retrieved tracked characters from cache",
      character_count: length(ListUtils.ensure_list(characters)),
      characters: ListUtils.ensure_list(characters)
    )

    ListUtils.ensure_list(characters)
  end

  # Checks if a character ID is in the list of tracked characters
  defp tracked_character?(character_id, tracked_characters) do
    # Ensure we're working with a proper list
    characters_list = ListUtils.ensure_list(tracked_characters)

    # Convert the character_id to string for consistent comparison
    character_id_str = to_string(character_id)

    # Log the tracking check for debugging
    AppLogger.persistence_info("Checking if character is tracked", %{
      character_id: character_id,
      tracked_characters_count: length(characters_list)
    })

    # Now we can safely use Enum functions
    result =
      Enum.any?(characters_list, fn tracked ->
        # Try to extract character_id using different approaches
        tracked_id =
          cond do
            is_map(tracked) && Map.has_key?(tracked, "character_id") ->
              tracked["character_id"]

            is_map(tracked) && Map.has_key?(tracked, :character_id) ->
              tracked.character_id

            true ->
              nil
          end

        # Compare as strings for consistency
        tracked_id && to_string(tracked_id) == character_id_str
      end)

    result
  end

  @doc """
  Gets statistics about tracked characters and their killmails.

  ## Returns
    - Map containing tracked_characters (count), total_kills (count)
  """
  def get_tracked_kills_stats do
    # Get the number of tracked characters from the cache
    tracked_characters = get_tracked_characters()
    character_count = length(tracked_characters)

    # Count the total number of killmails in the database
    total_kills = count_total_killmails()

    # Return the stats as a map
    %{
      tracked_characters: character_count,
      total_kills: total_kills
    }
  rescue
    e ->
      AppLogger.persistence_error("Error getting stats", error: Exception.message(e))
      %{tracked_characters: 0, total_kills: 0}
  end

  def count_total_killmails do
    case Killmail
         |> Ash.Query.new()
         |> Ash.Query.aggregate(:count, :id, :total)
         |> Api.read() do
      {:ok, [%{total: count}]} -> count
      _ -> 0
    end
  end

  @doc """
  Checks if kill charts feature is enabled.
  Only logs the status once at startup.
  """
  def kill_charts_enabled? do
    enabled = Features.kill_charts_enabled?()

    # Only log feature status if we haven't logged it before
    if !Process.get(:kill_charts_status_logged) do
      status_text = if enabled, do: "enabled", else: "disabled"

      AppLogger.persistence_info("Kill charts feature status: #{status_text}", %{enabled: enabled})

      Process.put(:kill_charts_status_logged, true)
    end

    enabled
  end

  @doc """
  Explicitly logs the current kill charts feature status.
  Use this function only when you specifically want to know the status.
  """
  def log_kill_charts_status do
    enabled = Features.kill_charts_enabled?()
    status_text = if enabled, do: "enabled", else: "disabled"
    AppLogger.persistence_info("Kill charts feature status: #{status_text}", %{enabled: enabled})
    enabled
  end

  @impl true
  def persist_killmail(%KillmailStruct{} = killmail, nil) do
    process_killmail_without_character_id(killmail)
  end

  @impl true
  def persist_killmail(%KillmailStruct{} = killmail, character_id) do
    process_provided_character_id(killmail, character_id)
  end

  @impl true
  def persist_killmail(%KillmailStruct{} = killmail) do
    # Call the function with nil character_id to perform the default processing
    persist_killmail(killmail, nil)
  end

  defp process_provided_character_id(killmail, character_id) do
    # Validate character_id doesn't match kill_id (indicates data error)
    kill_id = killmail.killmail_id

    if character_id == kill_id do
      AppLogger.kill_error(
        "Character ID equals kill ID in process_provided_character_id - likely a data error",
        %{
          character_id: character_id,
          kill_id: kill_id
        }
      )

      :ignored
    else
      if tracked_character?(character_id, get_tracked_characters()) do
        process_tracked_character(killmail, character_id)
      else
        AppLogger.persistence_info("Provided character_id is not tracked",
          killmail_id: killmail.killmail_id,
          character_id: character_id
        )

        :ignored
      end
    end
  end

  defp process_tracked_character(killmail, character_id) do
    case determine_character_role(killmail, character_id) do
      {:ok, role} ->
        character_name = get_character_name(killmail, character_id, role)

        handle_tracked_character_found(
          killmail,
          to_string(killmail.killmail_id),
          character_id,
          character_name,
          role
        )

      _ ->
        AppLogger.persistence_info("Could not determine role for character in killmail",
          killmail_id: killmail.killmail_id,
          character_id: character_id
        )

        :ignored
    end
  end

  defp process_killmail_without_character_id(killmail) do
    case find_tracked_character_in_killmail(killmail) do
      {character_id, character_name, role} ->
        handle_tracked_character_found(
          killmail,
          to_string(killmail.killmail_id),
          character_id,
          character_name,
          role
        )

      nil ->
        AppLogger.persistence_info("No tracked character found in killmail",
          killmail_id: killmail.killmail_id
        )

        :ignored
    end
  end

  @impl true
  def maybe_persist_killmail(%KillmailStruct{} = killmail, character_id \\ nil) do
    # First do a dry run to log what would be persisted (for debugging)
    dry_run_persist_killmail(killmail, character_id)

    kill_id = killmail.killmail_id
    system_id = KillmailStruct.get_system_id(killmail)
    system_name = KillmailStruct.get(killmail, "solar_system_name") || "Unknown System"

    # Validate character_id doesn't match kill_id (indicates data error)
    character_id_validated =
      if character_id == kill_id do
        AppLogger.kill_error(
          "Character ID equals kill ID in maybe_persist_killmail - likely a data error",
          %{
            character_id: character_id,
            kill_id: kill_id
          }
        )

        # Treat as if no character ID was provided
        nil
      else
        character_id
      end

    case get_killmail(kill_id) do
      nil ->
        process_new_killmail(killmail, character_id_validated, kill_id, system_id, system_name)

      _ ->
        AppLogger.kill_info("Killmail already exists", %{
          kill_id: kill_id,
          system_id: system_id,
          system_name: system_name
        })

        {:ok, :already_exists}
    end
  end

  @doc """
  DEBUGGING FUNCTION: Performs a dry run of the killmail persistence process.
  Logs what would be persisted but doesn't actually write to the database.

  ## Parameters
    - killmail: The killmail struct to process
    - character_id: Optional character ID for persistence

  ## Returns
    - nothing meaningful; this is only for logging
  """
  def dry_run_persist_killmail(%KillmailStruct{} = killmail, character_id) do
    # First log raw killmail debugging data
    debug_data = KillmailStruct.debug_data(killmail)
    AppLogger.kill_info("[DEBUG DRY-RUN] Raw killmail debug data:", debug_data)

    # Find the character in the killmail
    character_result =
      if character_id do
        # If character_id is provided, determine role
        case determine_character_role(killmail, character_id) do
          {:ok, role} ->
            # Get character name
            character_name = get_character_name(killmail, character_id, role)
            {character_id, character_name, role}

          _ ->
            nil
        end
      else
        # Find both the character and role at once
        find_tracked_character_in_killmail(killmail)
      end

    # If we found a character, log what we would persist
    case character_result do
      {id, name, role} ->
        # Transform the killmail without persisting
        data_to_persist = transform_killmail_to_resource(killmail, id, name, role)

        # Log the full data that would be persisted
        AppLogger.kill_info("[DEBUG DRY-RUN] Would persist killmail:", %{
          killmail_id: killmail.killmail_id,
          character_id: id,
          character_name: name,
          character_role: role,
          solar_system_id: data_to_persist.solar_system_id,
          solar_system_name: data_to_persist.solar_system_name,
          region_id: data_to_persist.region_id,
          region_name: data_to_persist.region_name,
          ship_type_id: data_to_persist.ship_type_id,
          ship_type_name: data_to_persist.ship_type_name,
          kill_time: data_to_persist.kill_time,
          total_value: data_to_persist.total_value
        })

        # Log warnings for missing important data
        if is_nil(data_to_persist.solar_system_name) || data_to_persist.solar_system_name == "" do
          AppLogger.kill_warning("[DEBUG DRY-RUN] Missing solar_system_name in killmail", %{
            killmail_id: killmail.killmail_id,
            solar_system_id: data_to_persist.solar_system_id
          })
        end

        if is_nil(data_to_persist.region_name) || data_to_persist.region_name == "" do
          AppLogger.kill_warning("[DEBUG DRY-RUN] Missing region_name in killmail", %{
            killmail_id: killmail.killmail_id,
            region_id: data_to_persist.region_id
          })
        end

        if is_nil(data_to_persist.character_name) || data_to_persist.character_name == "" do
          AppLogger.kill_warning("[DEBUG DRY-RUN] Missing character_name in killmail", %{
            killmail_id: killmail.killmail_id,
            character_id: id
          })
        end

      nil ->
        AppLogger.kill_info("[DEBUG DRY-RUN] No tracked character found in killmail:", %{
          killmail_id: killmail.killmail_id,
          esi_data_keys: (killmail.esi_data && Map.keys(killmail.esi_data)) || []
        })
    end

    # Return nil since this is just for logging
    nil
  end

  defp process_new_killmail(killmail, character_id, kill_id, system_id, system_name) do
    # Add validation to ensure character_id isn't the same as kill_id - this indicates a data problem
    character_id_validated =
      if character_id == kill_id do
        AppLogger.kill_error("Character ID equals kill ID - likely a data error", %{
          character_id: character_id,
          kill_id: kill_id
        })

        # Treat as if no character ID was provided
        nil
      else
        character_id
      end

    # Use find_tracked_character_in_killmail directly to get both ID and role
    character_result =
      if character_id_validated do
        # If character_id is provided, still need to determine role
        case determine_character_role(killmail, character_id_validated) do
          {:ok, role} ->
            # Get character name
            character_name = get_character_name(killmail, character_id_validated, role)
            {character_id_validated, character_name, role}

          _ ->
            nil
        end
      else
        # Find both the character and role at once
        find_tracked_character_in_killmail(killmail)
      end

    case character_result do
      {id, name, role} ->
        AppLogger.kill_info("Processing killmail with identified character", %{
          kill_id: kill_id,
          character_id: id,
          character_name: name,
          role: role,
          system_id: system_id,
          system_name: system_name
        })

        # Process directly with the character info we already have
        handle_tracked_character_found(killmail, to_string(kill_id), id, name, role)

      nil ->
        AppLogger.kill_info("No tracked character found in killmail",
          kill_id: kill_id,
          system_id: system_id,
          system_name: system_name
        )

        :ignored
    end
  end

  # Helper functions for finding tracked characters in killmails
  defp find_tracked_character_in_killmail(%KillmailStruct{} = killmail) do
    # Get victim and attacker information
    victim = KillmailStruct.get_victim(killmail)
    victim_character_id = victim && Map.get(victim, "character_id")
    victim_id_str = victim_character_id && to_string(victim_character_id)
    attackers = KillmailStruct.get_attacker(killmail) || []

    # Log victim and attacker information for debugging
    log_killmail_characters(killmail.killmail_id, victim, victim_id_str, length(attackers))

    # Get tracked characters
    tracked_characters = get_tracked_characters()

    # Check if we have any tracked characters
    if Enum.empty?(tracked_characters) do
      log_no_tracked_characters(killmail.killmail_id)
      nil
    else
      # Extract tracked IDs for easier comparison
      tracked_ids = extract_and_log_tracked_ids(tracked_characters)

      # Check if victim is tracked
      check_if_victim_is_tracked(
        killmail,
        victim,
        victim_character_id,
        victim_id_str,
        tracked_ids
      )
    end
  end

  # Helper function to log victim and attacker information
  defp log_killmail_characters(killmail_id, victim, victim_id_str, attacker_count) do
    AppLogger.kill_info(
      "Searching for tracked character in killmail #{killmail_id}: " <>
        "victim=#{victim_id_str || "none"} (#{(victim && Map.get(victim, "character_name")) || "unknown"}), " <>
        "attackers=#{attacker_count}",
      %{
        killmail_id: killmail_id,
        victim_id: victim && Map.get(victim, "character_id"),
        victim_id_str: victim_id_str,
        victim_name: victim && Map.get(victim, "character_name"),
        attacker_count: attacker_count
      }
    )
  end

  # Helper function to log when no tracked characters are found
  defp log_no_tracked_characters(killmail_id) do
    AppLogger.kill_info("No tracked characters found for killmail",
      killmail_id: killmail_id
    )
  end

  # Helper function to extract and log tracked IDs
  defp extract_and_log_tracked_ids(tracked_characters) do
    # Log tracked characters for debugging
    sample_chars = Enum.take(tracked_characters, min(3, length(tracked_characters)))

    AppLogger.kill_info("Tracked characters found", %{
      count: length(tracked_characters),
      sample: sample_chars
    })

    # Safely extract IDs based on structure
    tracked_ids = extract_tracked_ids(tracked_characters)

    # Log the extracted tracked IDs
    AppLogger.kill_info("Extracted tracked character IDs", %{
      count: MapSet.size(tracked_ids),
      sample: Enum.take(MapSet.to_list(tracked_ids), min(3, MapSet.size(tracked_ids)))
    })

    tracked_ids
  end

  # Helper function to check if victim is tracked
  defp check_if_victim_is_tracked(
         killmail,
         victim,
         victim_character_id,
         victim_id_str,
         tracked_ids
       ) do
    # Check if victim is tracked using string comparison
    if victim_id_str && MapSet.member?(tracked_ids, victim_id_str) do
      # Log and return victim information
      log_found_tracked_victim(victim_character_id, victim, killmail.killmail_id)
      {victim_character_id, Map.get(victim, "character_name"), :victim}
    else
      # Check attackers if victim isn't tracked
      find_tracked_attacker_in_killmail(killmail, tracked_ids)
    end
  end

  # Helper function to log when a tracked victim is found
  defp log_found_tracked_victim(victim_character_id, victim, killmail_id) do
    AppLogger.kill_info("Found tracked character as victim", %{
      character_id: victim_character_id,
      character_name: Map.get(victim, "character_name"),
      killmail_id: killmail_id
    })
  end

  # Updated to accept tracked_ids (removed default parameter)
  defp find_tracked_attacker_in_killmail(%KillmailStruct{} = killmail, tracked_ids) do
    # Get attackers list
    attackers = KillmailStruct.get_attacker(killmail) || []

    # If no tracked_ids provided or no attackers, return early
    if is_nil(tracked_ids) || Enum.empty?(attackers) do
      log_no_tracked_ids_or_attackers(killmail.killmail_id)
      nil
    else
      # Log attacker information for debugging
      log_attacker_info(killmail.killmail_id, attackers, tracked_ids)

      # Find the first tracked attacker
      find_first_tracked_attacker(attackers, tracked_ids, killmail.killmail_id)
    end
  end

  # Helper to log when no tracked IDs or attackers are found
  defp log_no_tracked_ids_or_attackers(killmail_id) do
    AppLogger.kill_info("No tracked IDs or attackers found for killmail",
      killmail_id: killmail_id
    )
  end

  # Helper to log attacker information
  defp log_attacker_info(killmail_id, attackers, tracked_ids) do
    attacker_sample = Enum.take(attackers, min(5, length(attackers)))

    AppLogger.kill_info("Checking attackers for tracked characters", %{
      killmail_id: killmail_id,
      attacker_count: length(attackers),
      tracked_ids_count: MapSet.size(tracked_ids),
      sample_attacker_ids:
        Enum.map(
          attacker_sample,
          &%{
            id: Map.get(&1, "character_id"),
            name: Map.get(&1, "character_name")
          }
        )
    })
  end

  # Helper to find the first tracked attacker
  defp find_first_tracked_attacker(attackers, tracked_ids, killmail_id) do
    result =
      Enum.find_value(attackers, fn attacker ->
        character_id = Map.get(attacker, "character_id")
        character_name = Map.get(attacker, "character_name")
        character_id_str = character_id && to_string(character_id)

        if character_id_str && MapSet.member?(tracked_ids, character_id_str) do
          log_found_tracked_attacker(character_id, character_name, killmail_id)
          {character_id, character_name, :attacker}
        else
          nil
        end
      end)

    # Log if no tracked attackers were found
    if is_nil(result) do
      AppLogger.kill_info("No tracked attackers found in killmail", %{
        killmail_id: killmail_id
      })
    end

    result
  end

  # Helper to log when a tracked attacker is found
  defp log_found_tracked_attacker(character_id, character_name, killmail_id) do
    AppLogger.kill_info("Found tracked character as attacker", %{
      character_id: character_id,
      character_name: character_name,
      killmail_id: killmail_id
    })
  end

  # Helper to safely extract IDs regardless of structure
  defp extract_tracked_ids(characters) do
    ids =
      Enum.map(characters, fn char ->
        cond do
          is_map(char) && Map.has_key?(char, "character_id") ->
            to_string(char["character_id"])

          is_map(char) && Map.has_key?(char, :character_id) ->
            to_string(char.character_id)

          true ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    MapSet.new(ids)
  end

  # Helper functions for character role determination
  defp determine_character_role(killmail, character_id) do
    victim = KillmailStruct.get_victim(killmail)
    attackers = KillmailStruct.get_attacker(killmail) || []

    # Get character ID as string for consistent comparison
    char_id_str = to_string(character_id)

    # Convert victim ID to string if present
    victim_id = get_in(victim, ["character_id"])
    victim_id_str = victim_id && to_string(victim_id)

    # Check victim match with comprehensive logging
    victim_match = char_id_str == victim_id_str

    # Log checks for better debugging
    log_role_determination_info(killmail, character_id, victim_id, victim_match, attackers)

    # Check victim role first
    if victim_match do
      log_character_as_victim(killmail.killmail_id, character_id, victim)
      {:ok, :victim}
    else
      # Check if character is an attacker
      check_if_character_is_attacker(killmail.killmail_id, attackers, character_id, char_id_str)
    end
  end

  # Helper to log role determination information
  defp log_role_determination_info(killmail, character_id, victim_id, victim_match, attackers) do
    char_id_str = to_string(character_id)
    victim_id_str = victim_id && to_string(victim_id)

    AppLogger.kill_info(
      "Character role determination: character_id=#{character_id} victim_id=#{victim_id} matched=#{victim_match} (attackers: #{length(attackers)})",
      %{
        killmail_id: killmail.killmail_id,
        character_id: character_id,
        character_id_type: typeof(character_id),
        char_id_str: char_id_str,
        victim_id: victim_id,
        victim_id_type: victim_id && typeof(victim_id),
        victim_id_str: victim_id_str,
        victim_matched: victim_match,
        attacker_count: length(attackers)
      }
    )
  end

  # Helper to log when character is found as victim
  defp log_character_as_victim(killmail_id, character_id, victim) do
    AppLogger.kill_info("Character found as victim", %{
      killmail_id: killmail_id,
      character_id: character_id,
      character_name: Map.get(victim, "character_name")
    })
  end

  # Helper to check if character is an attacker
  defp check_if_character_is_attacker(killmail_id, attackers, character_id, char_id_str) do
    # Find matching attacker using string comparison
    found_attacker = find_matching_attacker(attackers, character_id, char_id_str)

    case found_attacker do
      nil ->
        log_attacker_not_found(killmail_id, attackers, character_id, char_id_str)
        {:error, :character_not_found}

      attacker ->
        log_character_as_attacker(killmail_id, character_id, attacker)
        {:ok, :attacker}
    end
  end

  # Helper to find a matching attacker
  defp find_matching_attacker(attackers, character_id, char_id_str) do
    Enum.find(attackers, fn attacker ->
      attacker_id = Map.get(attacker, "character_id")
      attacker_id_str = attacker_id && to_string(attacker_id)
      matched = attacker_id_str == char_id_str

      if matched do
        AppLogger.kill_info("Found matching attacker ID", %{
          character_id: character_id,
          attacker_id: attacker_id,
          attacker_id_str: attacker_id_str,
          char_id_str: char_id_str
        })
      end

      matched
    end)
  end

  # Helper to log when attacker is not found
  defp log_attacker_not_found(killmail_id, attackers, character_id, char_id_str) do
    attacker_sample = Enum.take(attackers, min(5, length(attackers)))
    sample_ids = Enum.map(attacker_sample, &Map.get(&1, "character_id"))

    AppLogger.kill_info(
      "Character not found in attackers: character_id=#{character_id} (#{char_id_str}) - " <>
        "checked #{length(attackers)} attackers, sample IDs: #{inspect(Enum.take(sample_ids, 3))}",
      %{
        killmail_id: killmail_id,
        character_id: character_id,
        char_id_str: char_id_str,
        sample_attacker_ids: sample_ids
      }
    )
  end

  # Helper to log when character is found as attacker
  defp log_character_as_attacker(killmail_id, character_id, attacker) do
    AppLogger.kill_info("Character found as attacker", %{
      killmail_id: killmail_id,
      character_id: character_id,
      character_name: Map.get(attacker, "character_name")
    })
  end

  defp get_character_name(killmail, character_id, {:ok, role}) do
    get_character_name(killmail, character_id, role)
  end

  defp get_character_name(killmail, character_id, role) do
    # Try to get the name from the killmail data first
    character_name =
      case role do
        :victim ->
          victim = KillmailStruct.get_victim(killmail)
          victim && Map.get(victim, "character_name")

        :attacker ->
          attackers = KillmailStruct.get_attacker(killmail) || []

          attacker =
            Enum.find(attackers, fn a ->
              a_id = Map.get(a, "character_id")
              a_id && to_string(a_id) == to_string(character_id)
            end)

          attacker && Map.get(attacker, "character_name")

        _ ->
          nil
      end

    # If we don't have a name from the killmail data, try to get it from ESI
    if character_name == nil || character_name == "" do
      AppLogger.kill_debug("Character name not found in killmail, fetching from ESI",
        character_id: character_id,
        killmail_id: killmail.killmail_id
      )

      case ESIService.get_character_info(character_id) do
        {:ok, char_info} ->
          name = Map.get(char_info, "name")

          AppLogger.kill_debug("Got character name from ESI: #{name}",
            character_id: character_id,
            killmail_id: killmail.killmail_id
          )

          name

        _ ->
          AppLogger.kill_debug("Failed to get character name from ESI",
            character_id: character_id,
            killmail_id: killmail.killmail_id
          )

          "Unknown Pilot"
      end
    else
      character_name
    end
  end

  # Helper functions for persistence
  defp handle_tracked_character_found(
         killmail,
         killmail_id_str,
         character_id,
         character_name,
         {:ok, role}
       ) do
    handle_tracked_character_found(killmail, killmail_id_str, character_id, character_name, role)
  end

  defp handle_tracked_character_found(
         killmail,
         killmail_id_str,
         character_id,
         character_name,
         role
       ) do
    str_character_id = to_string(character_id)

    # Check if this killmail already exists for this character and role
    if check_killmail_exists_in_database(killmail_id_str, str_character_id, role) do
      AppLogger.kill_info("Killmail already exists", %{
        kill_id: killmail_id_str,
        character_id: str_character_id
      })

      {:ok, :already_exists}
    else
      # Transform and persist the killmail
      killmail_attrs =
        transform_killmail_to_resource(killmail, character_id, character_name, role)

      case create_killmail_record(killmail_attrs) do
        {:ok, record} ->
          AppLogger.kill_info("✅ Successfully persisted killmail", %{
            kill_id: killmail_id_str,
            character_id: str_character_id,
            role: role
          })

          # Update cache with recent killmails for this character
          update_character_killmails_cache(str_character_id)

          # Also update recent killmails cache
          update_recent_killmails_cache(killmail)

          {:ok, record}

        {:error, error} ->
          AppLogger.kill_error("❌ Failed to persist killmail", %{
            kill_id: killmail_id_str,
            character_id: str_character_id,
            error: inspect(error)
          })

          {:error, error}
      end
    end
  end

  # Helper functions for database operations
  @doc """
  Checks directly in the database if a killmail exists for a specific character and role.
  Bypasses caching for accuracy.
  """
  def check_killmail_exists_in_database(killmail_id, character_id, role) do
    case Killmail.exists_with_character(killmail_id, character_id, role) do
      {:ok, []} -> false
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Helper functions for data transformation
  defp transform_killmail_to_resource(
         %KillmailStruct{} = killmail,
         character_id,
         character_name,
         {:ok, role}
       ) do
    transform_killmail_to_resource(killmail, character_id, character_name, role)
  end

  defp transform_killmail_to_resource(
         %KillmailStruct{} = killmail,
         character_id,
         character_name,
         role
       )
       when role in [:victim, :attacker] do
    # Extract killmail data
    kill_time = get_kill_time(killmail)
    solar_system_id = KillmailStruct.get_system_id(killmail)
    solar_system_name = KillmailStruct.get(killmail, "solar_system_name")
    region_id = KillmailStruct.get(killmail, "region_id")
    region_name = KillmailStruct.get(killmail, "region_name")

    # Extract victim data
    victim = KillmailStruct.get_victim(killmail) || %{}

    # Get ZKB data
    zkb_data = killmail.zkb || %{}
    total_value = Map.get(zkb_data, "totalValue")

    # Get ship information depending on the character's role
    {ship_type_id, ship_type_name} =
      case role do
        :victim ->
          {
            Map.get(victim, "ship_type_id"),
            Map.get(victim, "ship_type_name")
          }

        :attacker ->
          attacker = find_attacker_by_character_id(killmail, character_id)

          {
            Map.get(attacker || %{}, "ship_type_id"),
            Map.get(attacker || %{}, "ship_type_name")
          }
      end

    # Ensure killmail_id is properly parsed
    parsed_killmail_id = parse_integer(killmail.killmail_id)

    # Build the resource attributes map with explicit killmail_id
    %{
      killmail_id: parsed_killmail_id,
      kill_time: kill_time,
      solar_system_id: parse_integer(solar_system_id),
      solar_system_name: solar_system_name,
      region_id: parse_integer(region_id),
      region_name: region_name,
      total_value: parse_decimal(total_value),
      character_role: role,
      related_character_id: parse_integer(character_id),
      related_character_name: character_name,
      ship_type_id: parse_integer(ship_type_id),
      ship_type_name: ship_type_name,
      zkb_data: zkb_data,
      victim_data: victim,
      attacker_data:
        (role == :attacker && find_attacker_by_character_id(killmail, character_id)) || nil
    }
  end

  # Helper functions for data parsing
  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp parse_decimal(nil), do: nil
  defp parse_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp parse_decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp parse_decimal(_), do: nil

  # Helper functions for database operations
  defp create_killmail_record(attrs) do
    case Api.create(Killmail, attrs) do
      {:ok, record} ->
        {:ok, record}

      {:error, error} ->
        AppLogger.persistence_error("Create killmail error", error: inspect(error))
        {:error, error}
    end
  end

  # Helper functions for time handling
  defp get_kill_time(%KillmailStruct{} = killmail) do
    case KillmailStruct.get(killmail, "killmail_time") do
      nil ->
        DateTime.utc_now()

      time when is_binary(time) ->
        case DateTime.from_iso8601(time) do
          {:ok, datetime, _} -> datetime
          _ -> DateTime.utc_now()
        end

      _ ->
        DateTime.utc_now()
    end
  end

  # Helper functions for finding attackers
  defp find_attacker_by_character_id(%KillmailStruct{} = killmail, character_id) do
    attackers = KillmailStruct.get_attacker(killmail) || []

    Enum.find(attackers, fn attacker ->
      Map.get(attacker, "character_id") == character_id
    end)
  end

  # Cache update functions
  defp update_character_killmails_cache(character_id) do
    require Ash.Query
    cache_key = "character:#{character_id}:recent_kills"

    # Function to get recent killmails from database
    db_read_fun = fn ->
      # Get last 10 killmails for this character from the database
      result =
        Killmail
        |> Ash.Query.filter(related_character_id: character_id)
        |> Ash.Query.sort(kill_time: :desc)
        |> Ash.Query.limit(10)
        |> Api.read()

      # Extract the actual list from the read result
      case result do
        {:ok, records} when is_list(records) ->
          {:ok, records}

        {:ok, _non_list} ->
          AppLogger.persistence_warning("Got non-list result for character killmails")
          {:ok, []}

        {:error, reason} ->
          AppLogger.persistence_error("Error fetching character killmails",
            error: inspect(reason),
            character_id: character_id
          )

          {:ok, []}

        error ->
          AppLogger.persistence_error("Unexpected error fetching character killmails",
            error: inspect(error),
            character_id: character_id
          )

          {:ok, []}
      end
    end

    # Synchronize cache with database - use 30 minute TTL for recent killmails
    CacheRepo.sync_with_db(cache_key, db_read_fun, 1800)
  end

  defp update_recent_killmails_cache(%KillmailStruct{} = killmail) do
    cache_key = "zkill:recent_kills"

    # Update the cache of recent killmail IDs
    CacheRepo.get_and_update(
      cache_key,
      fn current_ids ->
        current_ids = current_ids || []

        # Add the new killmail ID to the front of the list
        updated_ids =
          [killmail.killmail_id | current_ids]
          |> Enum.uniq()
          # Keep only the 10 most recent
          |> Enum.take(10)

        {current_ids, updated_ids}
      end,
      # 1 hour TTL
      3600
    )

    # Also store the individual killmail
    individual_key = "#{cache_key}:#{killmail.killmail_id}"
    CacheRepo.update_after_db_write(individual_key, killmail, 3600)
  end

  # Public API functions
  @doc """
  Gets all killmails for a specific character.
  Returns an empty list if kill charts are not enabled.
  """
  def get_killmails_for_character(character_id) do
    enabled = Features.kill_charts_enabled?()

    if enabled do
      case Api.read(
             Killmail
             |> Ash.Query.filter(related_character_id: character_id)
             |> Ash.Query.sort(kill_time: :desc)
           ) do
        {:ok, records} when is_list(records) -> records
        _ -> []
      end
    else
      []
    end
  end

  @doc """
  Gets all killmails for a specific system.
  Returns an empty list if kill charts are not enabled.
  """
  def get_killmails_for_system(system_id) do
    enabled = Features.kill_charts_enabled?()

    if enabled do
      case Api.read(
             Killmail
             |> Ash.Query.filter(solar_system_id: system_id)
             |> Ash.Query.sort(kill_time: :desc)
           ) do
        {:ok, records} when is_list(records) -> records
        _ -> []
      end
    else
      []
    end
  end

  @doc """
  Gets recent kills for a character.
  """
  def get_recent_kills_for_character(character_id) when is_integer(character_id) do
    # Use a cache key based on character ID
    cache_key = CacheKeys.character_recent_kills(character_id)

    # Function to read from the database if not in cache
    db_read_fun = fn ->
      # Use direct Ash query instead of KillmailQueries
      import Ash.Query

      query =
        Killmail
        |> filter(character_id == ^character_id)
        |> sort(desc: :kill_time)
        |> limit(10)

      case Api.read(query) do
        {:ok, kills} -> kills
        _ -> []
      end
    end

    # Sync with the database and update cache
    CacheRepo.sync_with_db(cache_key, db_read_fun, 1800)
  end

  @doc """
  Gets recent kills from zKillboard.
  """
  def get_recent_zkillboard_kills do
    # Use a standard cache key for zkillboard recent kills
    cache_key = CacheKeys.zkill_recent_kills()

    # Function to read from the database if not in cache
    db_read_fun = fn ->
      # Stub implementation until ZKillboardAdapter is available
      AppLogger.processor_info("ZKillboard adapter not available, returning empty list")
      []
    end

    # Sync with the database and update cache
    CacheRepo.sync_with_db(
      cache_key,
      db_read_fun,
      @zkillboard_cache_ttl_seconds
    )

    # Store individual killmails separately for quicker access
    cache_individual_killmails(cache_key)
  end

  # Helper function for caching individual killmails
  defp cache_individual_killmails(cache_key) do
    case CacheRepo.get(cache_key) do
      kills when is_list(kills) ->
        for killmail <- kills do
          individual_key = "#{cache_key}:#{killmail.killmail_id}"
          CacheRepo.set(individual_key, killmail, @zkillboard_cache_ttl_seconds)
        end

        :ok

      _ ->
        :error
    end
  end

  @doc """
  Gets killmails for a specific character within a date range.

  ## Parameters
    - character_id: The character ID to get killmails for
    - from_date: Start date for the query (DateTime)
    - to_date: End date for the query (DateTime)
    - limit: Maximum number of results to return

  ## Returns
    - List of killmail records
  """
  def get_character_killmails(character_id, from_date, to_date, limit \\ 100) do
    Api.read(Killmail,
      action: :list_for_character,
      args: [character_id: character_id, from_date: from_date, to_date: to_date, limit: limit]
    )
  rescue
    e ->
      AppLogger.persistence_error("Error fetching killmails", error: Exception.message(e))
      []
  end

  @doc """
  Checks if a killmail already exists in the database for the specified character and role.
  Uses both cache and database checks.

  ## Parameters
    - killmail_id: The killmail ID to check
    - character_id: The character ID to check
    - role: The role (attacker/victim) to check

  ## Returns
    - true if the killmail exists
    - false if it doesn't exist
  """
  def exists?(killmail_id, character_id, role) when is_integer(killmail_id) and is_binary(role) do
    # First check the cache to avoid database queries if possible
    cache_key = CacheKeys.killmail_exists(killmail_id, character_id, role)

    case CacheRepo.get(cache_key) do
      nil ->
        # Not in cache, check the database
        exists = check_killmail_exists_in_database(killmail_id, character_id, role)
        # Cache the result to avoid future database lookups
        CacheRepo.set(cache_key, exists, @processed_kills_ttl_seconds)
        exists

      exists ->
        # Return the cached result
        exists
    end
  end

  @doc """
  Gets a killmail by its ID.
  """
  def get_killmail(killmail_id) do
    case Api.read(Killmail |> Ash.Query.filter(killmail_id: killmail_id)) do
      {:ok, [killmail]} -> killmail
      _ -> nil
    end
  end

  # Helper to get type of value for logs
  defp typeof(value) when is_binary(value), do: "string"
  defp typeof(value) when is_boolean(value), do: "boolean"
  defp typeof(value) when is_integer(value), do: "integer"
  defp typeof(value) when is_float(value), do: "float"
  defp typeof(value) when is_list(value), do: "list"
  defp typeof(value) when is_map(value), do: "map"
  defp typeof(value) when is_tuple(value), do: "tuple"
  defp typeof(value) when is_atom(value), do: "atom"
  defp typeof(value) when is_function(value), do: "function"
  defp typeof(value) when is_pid(value), do: "pid"
  defp typeof(value) when is_reference(value), do: "reference"
  defp typeof(value) when is_port(value), do: "port"
  defp typeof(_value), do: "unknown"
end
