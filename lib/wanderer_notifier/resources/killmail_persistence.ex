defmodule WandererNotifier.Resources.KillmailPersistence do
  @moduledoc """
  Service for persisting killmail information related to tracked characters.
  Only killmails involving tracked characters are stored in the database.
  """

  require Logger
  alias WandererNotifier.Data.Killmail, as: KillmailStruct
  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

  # Cache TTL for processed kill IDs - 24 hours
  @processed_kills_ttl_seconds 86_400

  @doc """
  Persists killmail data if it's related to a tracked character.

  ## Parameters
    - killmail: The killmail struct to persist

  ## Returns
    - {:ok, persisted_killmail} if successful
    - {:error, reason} if persistence fails
    - :ignored if the killmail is not related to a tracked character
  """
  def maybe_persist_killmail(%KillmailStruct{} = killmail) do
    # Check if kill charts feature is enabled
    enabled = kill_charts_enabled?()
    Logger.info("[KillmailPersistence] Kill charts feature enabled: #{enabled}")

    if enabled do
      persist_if_not_already_processed(killmail)
    else
      Logger.debug("[KillmailPersistence] Kill charts feature disabled, skipping persistence")
      :ignored
    end
  rescue
    exception ->
      Logger.error(
        "[KillmailPersistence] Exception persisting killmail: #{Exception.message(exception)}"
      )

      Logger.error(Exception.format_stacktrace())
      {:error, exception}
  end

  # Checks if a killmail has already been processed and persists it if not
  defp persist_if_not_already_processed(killmail) do
    killmail_id_str = to_string(killmail.killmail_id)
    cache_key = "processed:killmail:#{killmail_id_str}"

    if CacheRepo.exists?(cache_key) do
      Logger.debug(
        "[KillmailPersistence] Killmail #{killmail_id_str} already processed, skipping"
      )

      {:ok, :already_processed}
    else
      # Mark killmail as being processed to prevent concurrent processing
      CacheRepo.set(cache_key, true, @processed_kills_ttl_seconds)
      process_killmail_with_tracked_characters(killmail, killmail_id_str)
    end
  end

  # Processes a killmail against tracked characters
  defp process_killmail_with_tracked_characters(killmail, killmail_id_str) do
    tracked_characters = get_tracked_characters()

    Logger.info(
      "[KillmailPersistence] Found #{length(tracked_characters)} tracked characters to check against killmail #{killmail_id_str}"
    )

    case find_tracked_character_in_killmail(killmail, tracked_characters) do
      {character_id, character_name, role} ->
        handle_tracked_character_found(
          killmail,
          killmail_id_str,
          character_id,
          character_name,
          role
        )

      nil ->
        Logger.debug(
          "[KillmailPersistence] No tracked character found in killmail #{killmail_id_str}, ignoring"
        )

        :ignored
    end
  end

  # Handles the case when a tracked character is found in a killmail
  defp handle_tracked_character_found(
         killmail,
         killmail_id_str,
         character_id,
         character_name,
         role
       ) do
    str_character_id = to_string(character_id)

    Logger.info(
      "[KillmailPersistence] Found tracked character #{character_name} (#{str_character_id}) in killmail #{killmail_id_str} as #{role}"
    )

    # Check if this specific character-killmail combination already exists
    already_exists = check_killmail_exists_in_database(killmail.killmail_id, character_id, role)

    if already_exists do
      Logger.debug(
        "[KillmailPersistence] Killmail #{killmail_id_str} already exists for character #{str_character_id} as #{role}, skipping"
      )

      {:ok, :already_exists}
    else
      persist_new_killmail(
        killmail,
        killmail_id_str,
        character_id,
        character_name,
        role,
        str_character_id
      )
    end
  end

  # Persists a new killmail record
  defp persist_new_killmail(
         killmail,
         killmail_id_str,
         character_id,
         character_name,
         role,
         str_character_id
       ) do
    Logger.info(
      "[KillmailPersistence] Persisting killmail #{killmail_id_str} for character #{str_character_id}"
    )

    # Transform and persist the killmail
    killmail_attrs = transform_killmail_to_resource(killmail, character_id, character_name, role)

    Logger.debug(
      "[KillmailPersistence] Transformed killmail #{killmail_id_str} to: #{inspect(killmail_attrs)}"
    )

    case create_killmail_record(killmail_attrs) do
      {:ok, record} ->
        Logger.info("[KillmailPersistence] Successfully persisted killmail #{killmail_id_str}")
        {:ok, record}

      {:error, error} ->
        Logger.error(
          "[KillmailPersistence] Failed to persist killmail #{killmail_id_str}: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  @doc """
  Checks directly in the database if a killmail exists for a specific character and role.
  Bypasses caching for accuracy.

  ## Parameters
    - killmail_id: The killmail ID to check
    - character_id: The character ID to check
    - role: The role (attacker/victim) to check

  ## Returns
    - true if the killmail exists
    - false if it doesn't exist
  """
  def check_killmail_exists_in_database(killmail_id, character_id, role) do
    case Killmail.exists_with_character(killmail_id, character_id, role) do
      {:ok, []} -> false
      {:ok, _} -> true
      {:error, _} -> false
    end
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
  def killmail_exists_for_character?(killmail_id, character_id, role) do
    # First check in-memory cache
    cache_key = "exists:killmail:#{killmail_id}:#{character_id}:#{role}"

    case CacheRepo.get(cache_key) do
      true ->
        # Found in cache - already exists
        true

      _ ->
        # Not in cache, check database
        exists = check_killmail_exists_in_database(killmail_id, character_id, role)

        # Cache the result
        CacheRepo.set(cache_key, exists, @processed_kills_ttl_seconds)

        exists
    end
  end

  @doc """
  Gets all killmails for a specific character within a date range.

  ## Parameters
    - character_id: The character ID to get killmails for
    - from_date: Start date for the query (DateTime)
    - to_date: End date for the query (DateTime)
    - limit: Maximum number of results to return

  ## Returns
    - List of killmail records
  """
  def get_character_killmails(character_id, from_date, to_date, limit \\ 100) do
    try do
      WandererNotifier.Resources.Api.read(Killmail,
        action: :list_for_character,
        args: [character_id: character_id, from_date: from_date, to_date: to_date, limit: limit]
      )
    rescue
      e ->
        Logger.error("[KillmailPersistence] Error fetching killmails: #{Exception.message(e)}")
        []
    end
  end

  # Gets list of tracked characters from the cache
  defp get_tracked_characters do
    CacheRepo.get("map:characters") || []
  end

  # Looks for tracked characters in the killmail
  # Returns {character_id, character_name, role} if found, nil otherwise
  defp find_tracked_character_in_killmail(%KillmailStruct{} = killmail, tracked_characters) do
    find_tracked_victim(killmail, tracked_characters) ||
      find_tracked_attacker(killmail, tracked_characters)
  end

  # Looks for a tracked character as the victim
  defp find_tracked_victim(%KillmailStruct{} = killmail, tracked_characters) do
    victim = KillmailStruct.get_victim(killmail)
    victim_character_id = victim && Map.get(victim, "character_id")

    if victim_character_id && tracked_character?(victim_character_id, tracked_characters) do
      {victim_character_id, Map.get(victim, "character_name"), :victim}
    end
  end

  # Looks for a tracked character among the attackers
  defp find_tracked_attacker(%KillmailStruct{} = killmail, tracked_characters) do
    attackers = KillmailStruct.get(killmail, "attackers") || []

    Enum.find_value(attackers, fn attacker ->
      attacker_character_id = Map.get(attacker, "character_id")

      if attacker_character_id && tracked_character?(attacker_character_id, tracked_characters) do
        {attacker_character_id, Map.get(attacker, "character_name"), :attacker}
      end
    end)
  end

  # Checks if a character ID is in the list of tracked characters
  defp tracked_character?(character_id, tracked_characters) do
    Enum.any?(tracked_characters, fn tracked ->
      tracked["character_id"] == character_id ||
        to_string(tracked["character_id"]) == to_string(character_id)
    end)
  end

  # Transforms a killmail struct to the format needed for the Ash resource
  defp transform_killmail_to_resource(
         %KillmailStruct{} = killmail,
         character_id,
         character_name,
         role
       ) do
    # Extract killmail data
    kill_time = get_kill_time(killmail)
    solar_system_id = KillmailStruct.get_system_id(killmail)
    solar_system_name = KillmailStruct.get(killmail, "solar_system_name")

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

  # Helper function to parse integer values, handling string inputs
  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_integer(_), do: nil

  # Helper function to parse decimal values
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

  # Creates a new killmail record using Ash
  defp create_killmail_record(attrs) do
    # Create the record with proper error handling
    case WandererNotifier.Resources.Api.create(Killmail, attrs) do
      {:ok, record} ->
        {:ok, record}

      {:error, error} ->
        # Log the error details and return error
        Logger.error("[KillmailPersistence] Create killmail error: #{inspect(error)}")
        {:error, error}
    end
  end

  # Extracts kill time from the killmail
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

  # Finds an attacker in the killmail by character ID
  defp find_attacker_by_character_id(%KillmailStruct{} = killmail, character_id) do
    attackers = KillmailStruct.get(killmail, "attackers") || []

    Enum.find(attackers, fn attacker ->
      attacker_id = Map.get(attacker, "character_id")
      to_string(attacker_id) == to_string(character_id)
    end)
  end

  # Check if kill charts feature is enabled
  defp kill_charts_enabled? do
    WandererNotifier.Core.Config.kill_charts_enabled?()
  end

  @doc """
  Gets statistics about tracked characters and their killmails.

  ## Returns
    - Map containing tracked_characters (count), total_kills (count)
  """
  def get_tracked_kills_stats do
    try do
      # Get the number of tracked characters from the cache
      tracked_characters = get_tracked_characters()
      character_count = length(tracked_characters)

      # Count the total number of killmails in the database
      case count_total_killmails() do
        {:ok, total_kills} ->
          %{
            tracked_characters: character_count,
            total_kills: total_kills
          }

        {:error, _} ->
          %{
            tracked_characters: character_count,
            total_kills: 0
          }
      end
    rescue
      e ->
        Logger.error("[KillmailPersistence] Error getting stats: #{Exception.message(e)}")
        %{tracked_characters: 0, total_kills: 0}
    end
  end

  # Count total number of killmails in the database
  defp count_total_killmails do
    # Use a query that will return records and then count them
    query = Ash.Query.new(Killmail)

    case WandererNotifier.Resources.Api.read(query) do
      {:ok, records} ->
        {:ok, length(records)}

      error ->
        Logger.error("[KillmailPersistence] Error counting killmails: #{inspect(error)}")
        {:error, "Failed to count killmails"}
    end
  end
end
