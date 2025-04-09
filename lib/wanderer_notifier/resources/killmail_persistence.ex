defmodule WandererNotifier.Resources.KillmailPersistence do
  use Ash.Resource,
    domain: WandererNotifier.Resources.Api,
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
  alias WandererNotifier.Api.ESI.Service, as: EsiService
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Killmail, as: KillmailUtil
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail, as: KillmailResource
  alias WandererNotifier.Resources.KillmailCharacterInvolvement
  alias WandererNotifier.Utils.ListUtils

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

    AppLogger.persistence_debug("Retrieved tracked characters from cache",
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
    AppLogger.persistence_debug("Checking if character is tracked", %{
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
    case KillmailResource
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
  def persist_killmail(%KillmailResource{} = killmail, nil) do
    process_killmail_without_character_id(killmail)
  end

  @impl true
  def persist_killmail(%KillmailResource{} = killmail, character_id) do
    process_provided_character_id(killmail, character_id)
  end

  @impl true
  def persist_killmail(%KillmailResource{} = killmail) do
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

        # Validate character data quality before proceeding
        case validate_character_data_quality(character_id, character_name) do
          {:ok, _, validated_name} ->
            # Validate killmail structure completeness
            case validate_killmail_structure(killmail, character_id, validated_name, role) do
              {:ok, _} ->
                handle_tracked_character_found(
                  killmail,
                  to_string(killmail.killmail_id),
                  character_id,
                  validated_name,
                  role
                )

              {:error, reason} ->
                AppLogger.kill_error("Killmail structure validation failed",
                  killmail_id: killmail.killmail_id,
                  character_id: character_id,
                  reason: reason
                )

                :ignored
            end

          {:error, reason} ->
            AppLogger.kill_error("Character data quality validation failed",
              killmail_id: killmail.killmail_id,
              character_id: character_id,
              character_name: character_name,
              reason: reason
            )

            :ignored
        end

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
        AppLogger.kill_debug("No tracked character found in killmail",
          killmail_id: killmail.killmail_id
        )

        :ignored
    end
  end

  @impl true
  def maybe_persist_killmail(%KillmailResource{} = killmail, character_id \\ nil) do
    kill_id = killmail.killmail_id
    system_id = KillmailUtil.get_system_id(killmail)
    system_name = KillmailUtil.get(killmail, "solar_system_name") || "Unknown System"

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
        AppLogger.kill_debug("Killmail already exists", %{
          kill_id: kill_id,
          system_id: system_id,
          system_name: system_name
        })

        {:ok, :already_exists}
    end
  end

  defp process_character_result({id, name, role}, killmail, kill_id, system_id, system_name) do
    AppLogger.kill_debug("Processing killmail with identified character", %{
      kill_id: kill_id,
      character_id: id,
      character_name: name,
      role: role,
      system_id: system_id,
      system_name: system_name
    })

    handle_tracked_character_found(killmail, to_string(kill_id), id, name, role)
  end

  defp process_character_result(nil, _killmail, kill_id, system_id, system_name) do
    AppLogger.kill_debug("No tracked character found in killmail - ignoring", %{
      kill_id: kill_id,
      system_id: system_id,
      system_name: system_name
    })

    :ignored
  end

  defp validate_and_process_character({id, name, role}, killmail, kill_id) do
    with {:ok, validated_id, validated_name} <- validate_character_data_quality(id, name),
         {:ok, _} <- validate_killmail_structure(killmail, validated_id, validated_name, role) do
      {validated_id, validated_name, role}
    else
      {:error, reason} ->
        AppLogger.kill_error("Character validation failed", %{
          killmail_id: kill_id,
          character_id: id,
          character_name: name,
          reason: reason
        })

        nil
    end
  end

  defp validate_and_process_character(nil, _killmail, _kill_id), do: nil

  defp process_new_killmail(killmail, character_id_validated, kill_id, system_id, system_name) do
    AppLogger.kill_debug("Processing new killmail", %{
      kill_id: kill_id,
      character_id: character_id_validated,
      system_id: system_id,
      system_name: system_name
    })

    # Use find_tracked_character_in_killmail directly to get both ID and role
    character_result =
      if character_id_validated do
        # If character_id is provided, still need to determine role
        case determine_character_role(killmail, character_id_validated) do
          {:ok, role} ->
            # Get character name
            character_name = get_character_name(killmail, character_id_validated, role)

            validate_and_process_character(
              {character_id_validated, character_name, role},
              killmail,
              kill_id
            )

          _ ->
            nil
        end
      else
        # Find both the character and role at once
        killmail
        |> find_tracked_character_in_killmail()
        |> validate_and_process_character(killmail, kill_id)
      end

    process_character_result(character_result, killmail, kill_id, system_id, system_name)
  end

  # Find tracked character information in the killmail
  defp find_tracked_character_in_killmail(%KillmailResource{} = killmail) do
    with victim_data <- extract_victim_data(killmail),
         tracked_characters when not is_nil(tracked_characters) <- get_tracked_characters(),
         tracked_ids <- extract_and_log_tracked_ids(tracked_characters),
         nil <- check_victim_tracking(killmail, victim_data, tracked_ids) do
      # If victim isn't tracked, check attackers
      find_tracked_attacker_in_killmail(killmail, tracked_ids)
    else
      nil ->
        log_no_tracked_characters(killmail.killmail_id)
        nil

      {:tracked_victim, result} ->
        result
    end
  end

  defp extract_victim_data(killmail) do
    victim = KillmailUtil.get_victim(killmail)
    victim_character_id = victim && Map.get(victim, "character_id")
    victim_id_str = victim_character_id && to_string(victim_character_id)
    attackers = KillmailUtil.get_attacker(killmail) || []

    log_killmail_characters(killmail.killmail_id, victim, victim_id_str, length(attackers))

    %{
      victim: victim,
      victim_character_id: victim_character_id,
      victim_id_str: victim_id_str
    }
  end

  defp check_victim_tracking(killmail, victim_data, tracked_ids) do
    if victim_data.victim_id_str && MapSet.member?(tracked_ids, victim_data.victim_id_str) do
      character_name = Map.get(victim_data.victim, "character_name")

      resolved_name =
        resolve_character_name_for_persistence(victim_data.victim_character_id, character_name)

      log_found_tracked_victim(
        victim_data.victim_character_id,
        Map.put(victim_data.victim, "character_name", resolved_name),
        killmail.killmail_id
      )

      {:tracked_victim, {victim_data.victim_character_id, resolved_name, :victim}}
    else
      nil
    end
  end

  # Helper function to validate a character's data quality
  defp validate_character_data_quality(character_id, character_name) do
    # Check if the name is a known placeholder value
    invalid_names = ["Unknown Character", "Unknown", "Unknown pilot", "Unknown Pilot"]

    cond do
      # Check if character id is nil
      is_nil(character_id) ->
        {:error, "Missing character ID"}

      # Check if character name is one of the known placeholder values
      character_name in invalid_names ->
        {:error, "Invalid character name: #{character_name}"}

      # Check if there's a name pattern that suggests placeholder (starts with "Unknown")
      is_binary(character_name) && String.starts_with?(character_name, "Unknown") ->
        {:error, "Suspicious character name: #{character_name}"}

      # Check if the character ID is tracked (critical validation)
      !tracked_character?(character_id, get_tracked_characters()) ->
        {:error, "Character ID #{character_id} is not tracked"}

      # All validations passed
      true ->
        {:ok, character_id, character_name}
    end
  end

  # Helper function to validate killmail structure completeness
  defp validate_killmail_structure(killmail, character_id, character_name, role) do
    kill_id = killmail.killmail_id
    debug_data = KillmailUtil.debug_data(killmail)

    validations =
      [
        validate_essential_fields(killmail),
        validate_victim_data(killmail, role, kill_id),
        validate_ship_data(killmail, character_id, character_name, role)
      ]
      |> List.flatten()

    case find_first_validation_error(validations) do
      nil ->
        {:ok, killmail}

      {_, _, reason} ->
        log_validation_failure(kill_id, character_id, character_name, role, reason, debug_data)
        {:error, reason}
    end
  end

  defp validate_essential_fields(killmail) do
    [
      {:kill_id, killmail.killmail_id, "Kill ID missing or invalid"},
      {:kill_time, KillmailUtil.get(killmail, "killmail_time"), "Kill time missing"},
      {:solar_system_id, KillmailUtil.get_system_id(killmail), "Solar system ID missing"},
      {:solar_system_name, KillmailUtil.get(killmail, "solar_system_name"),
       "Solar system name missing"},
      {KillmailUtil.get(killmail, "solar_system_name") != "Unknown System",
       "Solar system name is unknown (system data lookup failed)"}
    ]
  end

  defp validate_victim_data(killmail, role, kill_id) do
    victim = KillmailUtil.get_victim(killmail)

    cond do
      role == :victim and is_nil(victim) ->
        [{:victim_data, false, "Victim data is missing (required for victim role)"}]

      is_nil(victim) ->
        AppLogger.kill_warning("Killmail is missing victim data - unusual for valid killmail",
          killmail_id: kill_id
        )

        []

      true ->
        []
    end
  end

  defp validate_ship_data(killmail, character_id, character_name, role) do
    [
      {:ship_type_id, KillmailUtil.find_field(killmail, "ship_type_id", character_id, role),
       "Ship type ID missing for #{character_name} (role: #{role})"},
      {:ship_type_name, KillmailUtil.find_field(killmail, "ship_type_name", character_id, role),
       "Ship type name missing for #{character_name} (role: #{role})"}
    ]
  end

  defp find_first_validation_error(validations) do
    Enum.find(validations, fn
      {key, false, _} when is_atom(key) -> true
      {false, _} -> true
      {_, nil, _} -> true
      _ -> false
    end)
  end

  defp log_validation_failure(kill_id, character_id, character_name, role, reason, debug_data) do
    AppLogger.kill_error("Killmail structure validation failed", %{
      killmail_id: kill_id,
      character_id: character_id,
      character_name: character_name,
      role: role,
      reason: reason,
      debug_data: debug_data
    })
  end

  # Helper function to log victim and attacker information
  defp log_killmail_characters(killmail_id, victim, victim_id_str, attacker_count) do
    AppLogger.kill_debug(
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

  # Helper function to log when a tracked victim is found
  defp log_found_tracked_victim(victim_character_id, victim, killmail_id) do
    character_name = Map.get(victim, "character_name")

    resolved_name =
      if character_name == "Unknown Pilot" || character_name == "Unknown" ||
           is_nil(character_name) do
        # Try to get a better name - this only affects logging
        case EsiService.get_character(victim_character_id) do
          {:ok, %{"name" => name}} when is_binary(name) and name != "" -> name
          _ -> character_name || "Unknown Victim"
        end
      else
        character_name
      end

    AppLogger.kill_info("Found tracked character as victim", %{
      character_id: victim_character_id,
      character_name: resolved_name,
      killmail_id: killmail_id
    })
  end

  # Find tracked attacker in killmail
  defp find_tracked_attacker_in_killmail(killmail, tracked_ids) do
    attackers = KillmailUtil.get_attacker(killmail) || []

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
          # Resolve the character name properly
          resolved_name = resolve_character_name_for_persistence(character_id, character_name)
          log_found_tracked_attacker(character_id, resolved_name, killmail_id)
          {character_id, resolved_name, :attacker}
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
    resolved_name =
      if character_name == "Unknown Pilot" || character_name == "Unknown" ||
           is_nil(character_name) do
        # Try to get a better name - this only affects logging
        case EsiService.get_character(character_id) do
          {:ok, %{"name" => name}} when is_binary(name) and name != "" -> name
          _ -> character_name || "Unknown Attacker"
        end
      else
        character_name
      end

    AppLogger.kill_info("Found tracked character as attacker", %{
      character_id: character_id,
      character_name: resolved_name,
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
    victim = KillmailUtil.get_victim(killmail)
    attackers = KillmailUtil.get_attacker(killmail) || []

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

  defp get_character_name(killmail, character_id, role) do
    # First try to get name from the killmail structure
    name_from_killmail = get_name_from_killmail(killmail, character_id, role)

    # If we have a valid name from the killmail, use it
    if is_valid_name?(name_from_killmail) do
      name_from_killmail
    else
      # Otherwise, try to fetch from ESI or cache
      resolve_character_name(character_id)
    end
  end

  defp get_name_from_killmail(killmail, character_id, :victim) do
    victim = KillmailUtil.get_victim(killmail)
    victim && Map.get(victim, "character_name")
  end

  defp get_name_from_killmail(killmail, character_id, :attacker) do
    attackers = KillmailUtil.get_attacker(killmail) || []

    attacker =
      Enum.find(attackers, fn a ->
        a_id = Map.get(a, "character_id")
        a_id && to_string(a_id) == to_string(character_id)
      end)

    attacker && Map.get(attacker, "character_name")
  end

  defp get_name_from_killmail(_killmail, _character_id, _role), do: nil

  defp is_valid_name?(name) when is_binary(name),
    do: name != "" && name != "Unknown Pilot"

  defp is_valid_name?(_), do: false

  # Helper to resolve character name from cache/ESI
  defp resolve_character_name(character_id)
       when is_integer(character_id) or is_binary(character_id) do
    # Convert to integer if it's a string
    char_id =
      if is_binary(character_id) do
        {id, _} = Integer.parse(character_id)
        id
      else
        character_id
      end

    # Try to get from repository cache first
    case WandererNotifier.Data.Repository.get_character_name(char_id) do
      {:ok, name} when name != nil and name != "" ->
        AppLogger.kill_debug("Resolved character name from cache", %{
          character_id: char_id,
          character_name: name
        })

        name

      _ ->
        # Fall back to ESI API
        case EsiService.get_character(char_id) do
          {:ok, character_data} when is_map(character_data) ->
            name = Map.get(character_data, "name")

            if name && name != "" do
              AppLogger.kill_debug("Resolved character name from ESI", %{
                character_id: char_id,
                character_name: name
              })

              name
            else
              "Unknown Pilot"
            end

          _ ->
            AppLogger.kill_debug("Could not resolve character name", %{
              character_id: char_id
            })

            "Unknown Pilot"
        end
    end
  end

  defp resolve_character_name(_), do: "Unknown Pilot"

  # Helper functions for persistence
  defp handle_tracked_character_found(
         killmail,
         killmail_id_str,
         character_id,
         character_name,
         role
       ) do
    str_character_id = to_string(character_id)

    with {:ok, _, validated_name} <-
           validate_character_data_quality(character_id, character_name),
         resolved_name <- resolve_character_name_for_persistence(character_id, validated_name),
         false <- check_killmail_exists_in_database(killmail_id_str, str_character_id, role),
         killmail_attrs <-
           transform_killmail_to_resource(killmail, character_id, resolved_name, role),
         {:ok, record} <- create_killmail_record(killmail_attrs) do
      # Log success and update caches
      AppLogger.kill_info("✅ Successfully persisted killmail", %{
        kill_id: killmail_id_str,
        character_id: str_character_id,
        role: role
      })

      update_character_killmails_cache(str_character_id)
      update_recent_killmails_cache(killmail)

      {:ok, record}
    else
      true ->
        AppLogger.kill_info("Killmail already exists", %{
          kill_id: killmail_id_str,
          character_id: str_character_id
        })

        {:ok, :already_exists}

      {:error, reason} = error ->
        AppLogger.kill_error("❌ Failed to persist killmail", %{
          kill_id: killmail_id_str,
          character_id: str_character_id,
          error: inspect(reason)
        })

        error
    end
  end

  # Helper function to properly resolve character name
  defp resolve_character_name_for_persistence(character_id, character_name) do
    # First validate the character data
    case validate_character_data_quality(character_id, character_name) do
      # If validation succeeds, continue with normal processing
      {:ok, _, validated_name} ->
        validated_name

      # If validation specifically found "Unknown Pilot" name, try to resolve it
      {:error, "Invalid character name: Unknown Pilot"} ->
        # Use ESI to get the real name
        case EsiService.get_character(character_id) do
          {:ok, character_data} when is_map(character_data) ->
            name = Map.get(character_data, "name")

            if is_binary(name) && name != "" do
              # Cache the correct character name for future use
              CacheHelpers.cache_character_info(%{
                "character_id" => character_id,
                "name" => name
              })

              AppLogger.kill_info("Resolved character name from ESI for persistence", %{
                character_id: character_id,
                character_name: name
              })

              name
            else
              # Rejected - don't save with invalid name
              AppLogger.kill_error("Character validation failed - ESI returned invalid name", %{
                character_id: character_id,
                esi_name: inspect(name)
              })

              # Return the original problematic name to ensure proper error handling upstream
              character_name
            end

          _ ->
            # ESI call failed, validation has failed
            AppLogger.kill_error("Character validation failed - ESI call unsuccessful", %{
              character_id: character_id
            })

            # Return the original problematic name to ensure proper error handling upstream
            character_name
        end

      # For any other validation errors, log and return the original name
      # (this will still be rejected upstream based on the validation results)
      {:error, reason} ->
        AppLogger.kill_error("Character validation failed in name resolution", %{
          character_id: character_id,
          character_name: character_name,
          reason: reason
        })

        # Return the original name so upstream handling can proceed with rejection
        character_name
    end
  end

  # Helper functions for database operations
  @doc """
  Checks directly in the database if a killmail exists for a specific character and role.
  Bypasses caching for accuracy.
  """
  def check_killmail_exists_in_database(killmail_id, character_id, role) do
    # Use the KillmailCharacterInvolvement exists_for_character action instead
    result =
      WandererNotifier.Resources.KillmailCharacterInvolvement.exists_for_character(
        killmail_id,
        character_id,
        String.to_atom(role)
      )

    case result do
      {:ok, []} ->
        AppLogger.persistence_debug("Killmail does not exist in database", %{
          killmail_id: killmail_id,
          character_id: character_id,
          role: role
        })

        false

      {:ok, _records} ->
        AppLogger.persistence_debug("Killmail exists in database", %{
          killmail_id: killmail_id,
          character_id: character_id,
          role: role
        })

        true

      {:error, error} ->
        AppLogger.persistence_error("Error checking if killmail exists in database", %{
          killmail_id: killmail_id,
          character_id: character_id,
          role: role,
          error: inspect(error)
        })

        false
    end
  end

  # Helper functions for data transformation
  defp transform_killmail_to_resource(killmail, character_id, character_name, {:ok, role}) do
    transform_killmail_to_resource(killmail, character_id, character_name, role)
  end

  defp transform_killmail_to_resource(killmail, character_id, character_name, role)
       when role in [:victim, :attacker] do
    # Extract basic killmail data
    basic_data = extract_basic_killmail_data(killmail)

    # Get ship information
    ship_data = extract_ship_data(killmail, character_id, role)

    # Build the complete resource attributes
    build_killmail_attributes(basic_data, ship_data, character_id, character_name, role)
  end

  defp extract_basic_killmail_data(killmail) do
    kill_time = get_kill_time(killmail)
    solar_system_id = KillmailUtil.get_system_id(killmail)
    solar_system_name = KillmailUtil.get(killmail, "solar_system_name") || "Unknown System"
    zkb_data = killmail.zkb || %{}
    total_value = Map.get(zkb_data, "totalValue")

    %{
      kill_time: kill_time,
      solar_system_id: parse_integer(solar_system_id),
      solar_system_name: solar_system_name,
      total_value: parse_decimal(total_value),
      killmail_id: parse_integer(killmail.killmail_id)
    }
  end

  defp extract_ship_data(killmail, character_id, role) do
    case role do
      :victim ->
        victim = KillmailUtil.get_victim(killmail) || %{}

        %{
          ship_type_id: Map.get(victim, "ship_type_id"),
          ship_type_name: Map.get(victim, "ship_type_name") || "Unknown Ship"
        }

      :attacker ->
        attacker = find_attacker_by_character_id(killmail, character_id)

        %{
          ship_type_id: Map.get(attacker || %{}, "ship_type_id"),
          ship_type_name: Map.get(attacker || %{}, "ship_type_name") || "Unknown Ship"
        }
    end
  end

  defp build_killmail_attributes(basic_data, ship_data, character_id, character_name, role) do
    # Log ship information
    AppLogger.kill_debug("[Persistence] Ship information",
      ship_type_id: ship_data.ship_type_id,
      ship_type_name: ship_data.ship_type_name
    )

    # Build the complete attributes map
    attrs =
      Map.merge(basic_data, ship_data)
      |> Map.merge(%{
        character_role: role,
        related_character_id: parse_integer(character_id),
        related_character_name: character_name || "Unknown Pilot"
      })

    # Log the final attributes for debugging
    AppLogger.kill_debug("[Persistence] Final killmail attributes",
      killmail_id: attrs.killmail_id,
      solar_system_name: attrs.solar_system_name,
      ship_type_name: attrs.ship_type_name
    )

    attrs
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
  defp get_kill_time(killmail) do
    if is_struct(killmail, KillmailResource) && killmail.kill_time do
      killmail.kill_time
    else
      DateTime.utc_now()
    end
  end

  # Helper functions for finding attackers
  defp find_attacker_by_character_id(killmail, character_id) do
    if is_struct(killmail, KillmailResource) && Map.has_key?(killmail, :full_attacker_data) do
      attackers = killmail.full_attacker_data || []

      Enum.find(attackers, fn attacker ->
        to_string(Map.get(attacker, "character_id")) == to_string(character_id)
      end)
    else
      nil
    end
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

  defp update_recent_killmails_cache(%KillmailResource{} = killmail) do
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

  @doc """
  Gets a set of kill IDs already processed for a character.
  Used to avoid re-processing the same killmails during batch operations.

  ## Parameters
    - character_id: The character ID to check for

  ## Returns
    - MapSet of killmail IDs that have already been processed
  """
  def get_already_processed_kill_ids(character_id) when is_integer(character_id) do
    # Cache key for storing processed kill IDs
    cache_key = CacheKeys.character_processed_kills(character_id)

    # Try to get from cache first
    case CacheRepo.get(cache_key) do
      nil ->
        # Not in cache, fetch from database
        fetch_and_cache_processed_kill_ids(character_id, cache_key)

      kill_ids when is_list(kill_ids) ->
        # Convert list to MapSet for efficient lookups
        MapSet.new(kill_ids)

      mapset = %MapSet{} ->
        # Already a MapSet, return as is
        mapset
    end
  end

  def get_already_processed_kill_ids(_), do: MapSet.new()

  defp fetch_and_cache_processed_kill_ids(character_id, cache_key) do
    # Query the database for all killmail IDs associated with this character
    processed_kills =
      case Killmail
           |> Ash.Query.filter(esi_data["character_id"] == ^character_id)
           |> Ash.Query.select([:killmail_id])
           |> Api.read() do
        {:ok, records} ->
          # Extract killmail_ids from the records
          Enum.map(records, & &1.killmail_id)

        _ ->
          []
      end

    # Log the number of processed kills found
    AppLogger.kill_debug("Fetched processed kills from database", %{
      character_id: character_id,
      processed_count: length(processed_kills)
    })

    # Create a MapSet for efficient lookups
    kill_ids_set = MapSet.new(processed_kills)

    # Cache the result for future use
    CacheRepo.set(cache_key, kill_ids_set, @processed_kills_ttl_seconds)

    # Return the MapSet
    kill_ids_set
  end

  @doc """
  Persist a killmail using the new normalized data model.
  This function handles the transition to the normalized model.

  ## Parameters
  - killmail: The old Data.Killmail struct
  - character_id: Optional character ID for direct tracking

  ## Returns
  - {:ok, :persisted} - Successfully persisted a new killmail
  - {:ok, :already_exists} - Killmail already exists in the database
  - {:ok, record} - Successfully persisted and returned the record
  - :ignored - Killmail was ignored (not tracked by any character)
  - {:error, reason} - Failed to persist killmail
  """
  def maybe_persist_normalized_killmail(%KillmailResource{} = killmail, character_id \\ nil) do
    # First check if killmail already exists in the new normalized model
    kill_id = killmail.killmail_id

    case check_normalized_killmail_exists(kill_id) do
      true ->
        # Killmail already exists in the normalized database
        AppLogger.kill_debug("Normalized killmail already exists", %{kill_id: kill_id})
        {:ok, :already_exists}

      false ->
        # Check if this killmail involves any tracked character
        if has_any_tracked_character?(killmail) do
          # Need to persist the killmail in the normalized format
          process_new_normalized_killmail(killmail, character_id, kill_id)
        else
          # No tracked character involved, don't persist
          AppLogger.kill_info("Skipping persistence for killmail with no tracked characters", %{
            kill_id: kill_id
          })

          :ignored
        end
    end
  end

  # Check if a killmail exists in the normalized database
  defp check_normalized_killmail_exists(killmail_id) do
    import Ash.Query

    # Query the new normalized Killmail resource
    case WandererNotifier.Resources.Api.read(
           WandererNotifier.Resources.Killmail
           |> filter(killmail_id == ^killmail_id)
           |> select([:id])
           |> limit(1)
         ) do
      {:ok, [_record]} -> true
      _ -> false
    end
  end

  # Process a new killmail using the normalized model
  defp process_new_normalized_killmail(killmail, character_id, kill_id) do
    AppLogger.kill_debug("Processing new normalized killmail", %{
      kill_id: kill_id,
      character_id: character_id
    })

    # Step 1: Convert the old killmail struct to normalized format
    with {:ok, normalized_data} <- convert_to_normalized_format(killmail),
         # Step 2: Get character involvement information if a character ID is provided
         character_info <- get_character_involvement(killmail, character_id),
         # Step 3: Persist the normalized killmail
         {:ok, killmail_record} <- persist_normalized_killmail(normalized_data) do
      # Step 4: If we have character involvement information, persist that too
      case character_info do
        {char_id, role, involvement_data} when is_map(involvement_data) ->
          # Persist the character involvement
          case persist_character_involvement(killmail_record.id, char_id, role, involvement_data) do
            {:ok, _} ->
              AppLogger.kill_info(
                "Successfully persisted normalized killmail and character involvement",
                %{
                  kill_id: kill_id,
                  character_id: char_id,
                  role: role
                }
              )

              {:ok, :persisted}

            error ->
              AppLogger.kill_error("Failed to persist character involvement", %{
                kill_id: kill_id,
                character_id: char_id,
                error: inspect(error)
              })

              # Still return success as the killmail was persisted
              {:ok, killmail_record}
          end

        nil ->
          # No character involvement to persist
          AppLogger.kill_debug("Persisted normalized killmail without character involvement", %{
            kill_id: kill_id
          })

          {:ok, killmail_record}
      end
    else
      error ->
        AppLogger.kill_error("Failed to persist normalized killmail", %{
          kill_id: kill_id,
          error: inspect(error)
        })

        error
    end
  end

  # Convert the old killmail struct to the normalized format
  defp convert_to_normalized_format(%KillmailResource{} = killmail) do
    # Use the Validation module to convert the killmail to normalized format
    normalized_data = WandererNotifier.Killmail.Validation.normalize_killmail(killmail)
    {:ok, normalized_data}
  rescue
    error ->
      AppLogger.kill_error("Failed to convert killmail to normalized format", %{
        kill_id: killmail.killmail_id,
        error: Exception.message(error)
      })

      {:error, :conversion_failed}
  end

  # Get character involvement information from a killmail
  defp get_character_involvement(%KillmailResource{} = killmail, nil) do
    # No character ID provided, try to find a tracked character in the killmail
    case find_tracked_character_in_killmail(killmail) do
      {character_id, _character_name, role} ->
        # Convert string role to atom for consistency
        atom_role = String.to_atom(to_string(role))

        # Extract involvement data for this character
        involvement_data =
          WandererNotifier.Killmail.Validation.extract_character_involvement(
            killmail,
            character_id,
            atom_role
          )

        {character_id, atom_role, involvement_data}

      nil ->
        # No tracked character found
        nil
    end
  end

  defp get_character_involvement(%KillmailResource{} = killmail, character_id) do
    # Character ID provided, determine the role
    case determine_character_role(killmail, character_id) do
      {:ok, role} ->
        # Convert role to atom for consistency with resource
        atom_role = String.to_atom(to_string(role))

        # Extract involvement data for this character
        involvement_data =
          WandererNotifier.Killmail.Validation.extract_character_involvement(
            killmail,
            character_id,
            atom_role
          )

        {character_id, atom_role, involvement_data}

      _ ->
        # Couldn't determine role for this character
        nil
    end
  end

  # Persist a normalized killmail to the database
  defp persist_normalized_killmail(normalized_data) when is_map(normalized_data) do
    # Sanitize data to ensure it's JSON-serializable
    sanitized_data = sanitize_for_json(normalized_data)

    # Create a new Killmail record using Ash
    result =
      WandererNotifier.Resources.Api.create(
        WandererNotifier.Resources.Killmail,
        sanitized_data
      )

    # If persisted successfully, increment the persisted count statistic
    case result do
      {:ok, _} ->
        # Increment the persisted count in stats
        Stats.increment(:kill_persisted)

      _ ->
        :ok
    end

    result
  end

  # Helper to ensure all values in a nested map structure are JSON-serializable
  defp sanitize_for_json(data) when is_map(data) do
    # Check if it's a Decimal struct first
    if is_struct(data) && data.__struct__ == Decimal do
      Decimal.to_string(data)
    else
      # Regular map - process each key-value pair
      data
      |> Enum.map(fn {k, v} -> {k, sanitize_for_json(v)} end)
      |> Map.new()
    end
  end

  defp sanitize_for_json(data) when is_list(data) do
    Enum.map(data, &sanitize_for_json/1)
  end

  defp sanitize_for_json(%DateTime{} = dt), do: dt

  defp sanitize_for_json(%Decimal{} = decimal) do
    Decimal.to_string(decimal)
  end

  defp sanitize_for_json(value) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      # Convert binary to string representation for inspection
      inspect(value)
    end
  end

  defp sanitize_for_json(value) when is_atom(value) do
    Atom.to_string(value)
  end

  defp sanitize_for_json(value) do
    # Pass through other primitive values
    value
  end

  # Persist character involvement to the database
  defp persist_character_involvement(killmail_id, character_id, character_role, involvement_data) do
    # Check if this involvement already exists
    case check_involvement_exists(killmail_id, character_id, character_role) do
      true ->
        # Already exists, nothing to do
        {:ok, :already_exists}

      false ->
        # Create a new involvement record using the function signature from KillmailCharacterInvolvement.create
        # Arguments: (attrs, %{killmail_id: value})
        result =
          WandererNotifier.Resources.Api.create(
            WandererNotifier.Resources.KillmailCharacterInvolvement,
            involvement_data,
            %{killmail_id: killmail_id}
          )

        # Track successful character involvement persistence
        case result do
          {:ok, _} ->
            # Increment the character involvement stats
            Stats.increment(:character_involvement_persisted)

          _ ->
            :ok
        end

        result
    end
  end

  # Check if a character involvement already exists
  defp check_involvement_exists(killmail_id, character_id, character_role) do
    # Ensure character_role is an atom
    atom_role = String.to_atom(to_string(character_role))

    import Ash.Query

    case Api.read(
           KillmailCharacterInvolvement
           |> filter(
             killmail_id == ^killmail_id and
               character_id == ^character_id and
               character_role == ^atom_role
           )
           |> select([:id])
           |> limit(1)
         ) do
      {:ok, [_record]} -> true
      _ -> false
    end
  end

  # Helper to check if a killmail involves any tracked character
  defp has_any_tracked_character?(%KillmailResource{} = killmail) do
    case find_tracked_character_in_killmail(killmail) do
      {_character_id, _character_name, _role} -> true
      nil -> false
    end
  end
end
