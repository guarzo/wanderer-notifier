defmodule WandererNotifier.Resources.KillmailPersistence do
  use Ash.Resource,
    domain: WandererNotifier.Resources.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  @moduledoc """
  Handles persistence of killmails to database for historical analysis and reporting.
  """

  @behaviour WandererNotifier.Resources.KillmailPersistenceBehaviour

  require Ash.Query
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Core.Logger, as: AppLogger
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Killmail, as: KillmailStruct
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail

  # Cache TTL for processed kill IDs - 24 hours
  @processed_kills_ttl_seconds 86_400

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

      # Mark as logged to avoid future log messages
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
  def persist_killmail(%KillmailStruct{} = killmail) do
    # Check if kill charts feature is enabled
    if kill_charts_enabled?() do
      try do
        # Find tracked characters in killmail and process them
        killmail_id_str = to_string(killmail.killmail_id)

        AppLogger.persistence_debug("Checking killmail for tracked characters",
          killmail_id: killmail_id_str
        )

        case find_tracked_character_in_killmail(killmail) do
          {character_id, character_name, role} when is_integer(character_id) ->
            # We found a tracked character, handle persistence
            handle_tracked_character_found(
              killmail,
              killmail_id_str,
              character_id,
              character_name,
              role
            )

          nil ->
            AppLogger.persistence_debug("No tracked character found in killmail",
              killmail_id: killmail_id_str
            )

            :ignored
        end
      rescue
        e ->
          stacktrace = Exception.format_stacktrace(__STACKTRACE__)

          AppLogger.persistence_error("Failed to persist killmail",
            error: Exception.message(e),
            stacktrace: stacktrace
          )

          {:error, Exception.message(e)}
      end
    else
      AppLogger.persistence_debug("Kill charts feature disabled, skipping persistence")
      :ignored
    end
  end

  @impl true
  def maybe_persist_killmail(killmail) do
    # Skip if the killmail is nil
    if is_nil(killmail) do
      AppLogger.persistence_debug("Skipping nil killmail")
      :ignored
    else
      # Check if we should persist this killmail based on feature flags, tracked characters, etc.
      persist_killmail(killmail)
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

    AppLogger.persistence_info("Found tracked character in killmail",
      killmail_id: killmail_id_str,
      character_id: str_character_id,
      character_name: character_name,
      role: role
    )

    # Check if this specific character-killmail combination already exists
    already_exists = check_killmail_exists_in_database(killmail.killmail_id, character_id, role)

    if already_exists do
      AppLogger.persistence_debug("Killmail already exists for character",
        killmail_id: killmail_id_str,
        character_id: str_character_id,
        role: role
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
    AppLogger.persistence_info("Persisting killmail", killmail_id: killmail_id_str)

    # Transform and persist the killmail
    killmail_attrs = transform_killmail_to_resource(killmail, character_id, character_name, role)

    AppLogger.persistence_debug("Transformed killmail to: #{inspect(killmail_attrs)}")

    case create_killmail_record(killmail_attrs) do
      {:ok, record} ->
        AppLogger.persistence_info("Successfully persisted killmail")

        # Update cache with recent killmails for this character
        update_character_killmails_cache(str_character_id)

        # Also update recent killmails cache
        update_recent_killmails_cache(killmail)

        {:ok, record}

      {:error, error} ->
        AppLogger.persistence_error("Failed to persist killmail", error: inspect(error))
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

  # Helper function to ensure a list of characters
  defp ensure_list(nil), do: []
  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list({:ok, list}) when is_list(list), do: list
  defp ensure_list({:error, _}), do: []

  # Gets list of tracked characters from the cache
  defp get_tracked_characters do
    # Get characters from cache and ensure we return a proper list
    characters = CacheRepo.get("map:characters")
    ensure_list(characters)
  end

  # Looks for tracked characters in the killmail
  # Returns {character_id, character_name, role} if found, nil otherwise
  defp find_tracked_character_in_killmail(%KillmailStruct{} = killmail) do
    find_tracked_victim(killmail) ||
      find_tracked_attacker(killmail)
  end

  # Looks for a tracked character as the victim
  defp find_tracked_victim(%KillmailStruct{} = killmail) do
    victim = KillmailStruct.get_victim(killmail)
    victim_character_id = victim && Map.get(victim, "character_id")

    if victim_character_id && tracked_character?(victim_character_id, get_tracked_characters()) do
      {victim_character_id, Map.get(victim, "character_name"), :victim}
    end
  end

  # Looks for a tracked character among the attackers
  defp find_tracked_attacker(%KillmailStruct{} = killmail) do
    attackers = KillmailStruct.get(killmail, "attackers") || []

    Enum.find_value(attackers, fn attacker ->
      attacker_character_id = Map.get(attacker, "character_id")

      if attacker_character_id &&
           tracked_character?(attacker_character_id, get_tracked_characters()) do
        {attacker_character_id, Map.get(attacker, "character_name"), :attacker}
      end
    end)
  end

  # Checks if a character ID is in the list of tracked characters
  defp tracked_character?(character_id, tracked_characters) do
    # Ensure we're working with a proper list
    characters_list = ensure_list(tracked_characters)

    # Now we can safely use Enum functions
    Enum.any?(characters_list, fn tracked ->
      # Handle both direct matches and string conversion
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
    case Api.create(Killmail, attrs) do
      {:ok, record} ->
        {:ok, record}

      {:error, error} ->
        # Log the error details and return error
        AppLogger.persistence_error("Create killmail error", error: inspect(error))
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

  # Updates the character's recent killmails cache after a new killmail is persisted
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
          # Return empty list for non-list results
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

  # Updates the global recent killmails cache
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
end
