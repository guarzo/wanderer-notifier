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

    # Now we can safely use Enum functions
    result =
      Enum.any?(characters_list, fn tracked ->
        tracked_id = tracked["character_id"]
        # Handle both direct matches and string conversion
        tracked_id == character_id ||
          to_string(tracked_id) == to_string(character_id)
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

  defp process_provided_character_id(killmail, character_id) do
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
    kill_id = killmail.killmail_id
    system_id = KillmailStruct.get_system_id(killmail)
    system_name = KillmailStruct.get(killmail, "solar_system_name") || "Unknown System"

    case get_killmail(kill_id) do
      nil ->
        process_new_killmail(killmail, character_id, kill_id, system_id, system_name)

      _ ->
        AppLogger.kill_debug("Killmail already exists", %{
          kill_id: kill_id,
          system_id: system_id,
          system_name: system_name
        })

        {:ok, :already_exists}
    end
  end

  defp process_new_killmail(killmail, character_id, kill_id, system_id, system_name) do
    tracked_character_id = get_tracked_character_id(killmail, character_id)

    case tracked_character_id do
      nil ->
        AppLogger.kill_debug("No tracked character found in killmail",
          kill_id: kill_id,
          system_id: system_id,
          system_name: system_name
        )

        :ignored

      id ->
        process_tracked_character_killmail(killmail, id, kill_id, system_id, system_name)
    end
  end

  defp get_tracked_character_id(killmail, character_id) do
    if character_id do
      character_id
    else
      case find_tracked_character_in_killmail(killmail) do
        {id, _name, _role} -> id
        nil -> nil
      end
    end
  end

  defp process_tracked_character_killmail(killmail, character_id, kill_id, system_id, system_name) do
    case determine_character_role(killmail, character_id) do
      {:ok, role} ->
        AppLogger.kill_debug("Processing killmail", %{
          kill_id: kill_id,
          character_id: character_id,
          role: role,
          system_id: system_id,
          system_name: system_name
        })

        persist_killmail(killmail, character_id)

      {:error, reason} ->
        AppLogger.kill_error("❌ Failed to determine character role", %{
          kill_id: kill_id,
          character_id: character_id,
          error: inspect(reason),
          system_id: system_id,
          system_name: system_name
        })

        :ignored
    end
  end

  # Helper functions for finding tracked characters in killmails
  defp find_tracked_character_in_killmail(%KillmailStruct{} = killmail) do
    victim = KillmailStruct.get_victim(killmail)
    victim_character_id = victim && Map.get(victim, "character_id")

    if victim_character_id && tracked_character?(victim_character_id, get_tracked_characters()) do
      {victim_character_id, Map.get(victim, "character_name"), :victim}
    else
      find_tracked_attacker_in_killmail(killmail)
    end
  end

  defp find_tracked_attacker_in_killmail(%KillmailStruct{} = killmail) do
    # Get attackers list
    attackers = KillmailStruct.get_attacker(killmail) || []

    # Get tracked characters once
    tracked_characters = get_tracked_characters()
    tracked_ids = MapSet.new(tracked_characters, & &1.character_id)

    # Check if any attacker is tracked
    Enum.find_value(attackers, fn attacker ->
      character_id = Map.get(attacker, "character_id")

      if character_id && MapSet.member?(tracked_ids, character_id) do
        character_id
      end
    end)
  end

  # Helper functions for character role determination
  defp determine_character_role(killmail, character_id) do
    # Get victim and attacker data
    victim = KillmailStruct.get_victim(killmail)
    attackers = KillmailStruct.get_attacker(killmail) || []

    # Check victim first
    victim_id = get_in(victim, ["character_id"])

    if victim_id == character_id do
      {:ok, :victim}
    else
      # Then check attackers
      case Enum.find(attackers, &(Map.get(&1, "character_id") == character_id)) do
        nil -> {:error, :character_not_found}
        _ -> {:ok, :attacker}
      end
    end
  end

  defp get_character_name(killmail, character_id, {:ok, role}) do
    get_character_name(killmail, character_id, role)
  end

  defp get_character_name(killmail, character_id, role) do
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
      AppLogger.kill_debug("Killmail already exists", %{
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
          AppLogger.kill_debug("✅ Successfully persisted killmail", %{
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
end
