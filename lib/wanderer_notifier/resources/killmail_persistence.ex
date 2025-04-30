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

  # Cache TTL for processed kill IDs - 24 hours
  @processed_kills_ttl_seconds 86_400
  # TTL for zkillboard data - 1 hour

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

  @impl true
  def maybe_persist_killmail(%KillmailStruct{} = killmail, character_id \\ nil) do
    if Killmail.database_enabled?() do
      process_killmail_persistence(killmail, character_id)
    else
      AppLogger.persistence_debug("Database operations disabled, skipping killmail persistence")
      {:ok, :not_persisted}
    end
  end

  @impl true
  def persist_killmail(%KillmailStruct{} = killmail) do
    if Killmail.database_enabled?() do
      process_killmail_persistence(killmail, nil)
    else
      AppLogger.persistence_debug("Database operations disabled, skipping killmail persistence")
      :ignored
    end
  end

  @impl true
  def persist_killmail(%KillmailStruct{} = killmail, character_id) do
    if Killmail.database_enabled?() do
      process_killmail_persistence(killmail, character_id)
    else
      AppLogger.persistence_debug("Database operations disabled, skipping killmail persistence")
      :ignored
    end
  end

  @doc """
  Gets tracked kills stats.
  """
  def get_tracked_kills_stats do
    if Killmail.database_enabled?() do
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
    else
      AppLogger.persistence_debug("Database operations disabled, returning empty stats")
      %{tracked_characters: 0, total_kills: 0}
    end
  rescue
    e ->
      AppLogger.persistence_error("Error getting stats", error: Exception.message(e))
      %{tracked_characters: 0, total_kills: 0}
  end

  @doc """
  Gets killmails for a character.
  """
  def get_killmails_for_character(character_id) do
    if Killmail.database_enabled?() do
      case Killmail
           |> Ash.Query.filter(related_character_id == ^character_id)
           |> Api.read() do
        {:ok, killmails} -> killmails
        _ -> []
      end
    else
      AppLogger.persistence_debug("Database operations disabled, returning empty killmail list")
      []
    end
  end

  @doc """
  Gets killmails for a system.
  """
  def get_killmails_for_system(system_id) do
    if Killmail.database_enabled?() do
      case Killmail
           |> Ash.Query.filter(solar_system_id == ^system_id)
           |> Api.read() do
        {:ok, killmails} -> killmails
        _ -> []
      end
    else
      AppLogger.persistence_debug("Database operations disabled, returning empty killmail list")
      []
    end
  end

  @doc """
  Gets character killmails for a specific time period.
  """
  def get_character_killmails(character_id, from_date, to_date, limit \\ 100) do
    if Killmail.database_enabled?() do
      Killmail.read_safely(
        Killmail
        |> Ash.Query.filter(related_character_id == ^character_id)
        |> Ash.Query.filter(kill_time >= ^from_date)
        |> Ash.Query.filter(kill_time <= ^to_date)
        |> Ash.Query.sort(kill_time: :desc)
        |> Ash.Query.limit(limit)
      )
    else
      AppLogger.persistence_debug("Database operations disabled, returning empty killmail list")
      {:ok, []}
    end
  rescue
    e ->
      AppLogger.persistence_error("Error fetching killmails", error: Exception.message(e))
      {:ok, []}
  end

  @doc """
  Checks if a killmail exists.
  """
  def exists?(killmail_id, character_id, role) when is_integer(killmail_id) and is_binary(role) do
    if Killmail.database_enabled?() do
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
    else
      AppLogger.persistence_debug(
        "Database operations disabled, returning false for exists check"
      )

      false
    end
  end

  @doc """
  Checks if a killmail exists in the database.
  """
  def check_killmail_exists_in_database(killmail_id, character_id, role) do
    if Killmail.database_enabled?() do
      case Killmail.read_safely(
             Killmail
             |> Ash.Query.filter(killmail_id == ^killmail_id)
             |> Ash.Query.filter(related_character_id == ^character_id)
             |> Ash.Query.filter(character_role == ^role)
             |> Ash.Query.select([:id])
             |> Ash.Query.limit(1)
           ) do
        {:ok, [_record | _]} -> true
        _ -> false
      end
    else
      AppLogger.persistence_debug(
        "Database operations disabled, returning false for exists check"
      )

      false
    end
  end

  @doc """
  Counts total killmails.
  """
  def count_total_killmails do
    if Killmail.database_enabled?() do
      case Killmail.read_safely(
             Killmail
             |> Ash.Query.new()
             |> Ash.Query.aggregate(:count, :id, :total)
           ) do
        {:ok, [%{total: count}]} -> count
        _ -> 0
      end
    else
      AppLogger.persistence_debug("Database operations disabled, returning 0 for total killmails")
      0
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

  # Private helper functions

  defp process_killmail_persistence(%KillmailStruct{} = killmail, character_id) do
    # Check if we have a character ID
    if character_id do
      # Process with character ID
      process_killmail_with_character_id(killmail, character_id)
    else
      # Process without character ID
      process_killmail_without_character_id(killmail)
    end
  end

  defp process_killmail_with_character_id(%KillmailStruct{} = killmail, character_id) do
    # Get character name from cache
    character_name = get_character_name(character_id)

    # Determine character's role in the kill
    case determine_character_role(killmail, character_id) do
      {:ok, role} ->
        # Transform killmail data into resource attributes
        attrs = transform_killmail_to_resource(killmail, character_id, character_name, role)

        # Create the killmail record
        case create_killmail_record(attrs) do
          {:ok, _record} ->
            # Update caches
            update_recent_killmails_cache(character_id)
            update_character_killmails_cache(character_id)
            {:ok, :persisted}

          {:error, reason} ->
            AppLogger.persistence_error("Failed to create killmail record",
              error: inspect(reason)
            )

            {:error, reason}
        end

      {:error, reason} ->
        AppLogger.persistence_error("Failed to determine character role", error: inspect(reason))
        {:error, reason}
    end
  end

  defp process_killmail_without_character_id(%KillmailStruct{} = killmail) do
    # Get tracked characters from cache
    tracked_characters = get_tracked_characters()

    # Process for each tracked character
    results =
      tracked_characters
      |> Enum.map(fn char ->
        character_id = Map.get(char, "character_id")
        character_name = Map.get(char, "name")

        case determine_character_role(killmail, character_id) do
          {:ok, role} ->
            # Transform killmail data into resource attributes
            attrs = transform_killmail_to_resource(killmail, character_id, character_name, role)

            # Create the killmail record
            case create_killmail_record(attrs) do
              {:ok, _record} ->
                # Update caches
                update_recent_killmails_cache(character_id)
                update_character_killmails_cache(character_id)
                {:ok, :persisted}

              {:error, reason} ->
                AppLogger.persistence_error("Failed to create killmail record",
                  error: inspect(reason)
                )

                {:error, reason}
            end

          {:error, reason} ->
            AppLogger.persistence_error("Failed to determine character role",
              error: inspect(reason)
            )

            {:error, reason}
        end
      end)

    # Check if any persistence was successful
    if Enum.any?(results, &match?({:ok, :persisted}, &1)) do
      {:ok, :persisted}
    else
      :ignored
    end
  end

  # Helper functions for data transformation and validation

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

  # Helper functions for character data
  defp get_character_name(character_id) do
    case CacheRepo.get(CacheKeys.character(character_id)) do
      nil -> nil
      char -> Map.get(char, "name")
    end
  end

  defp get_tracked_characters do
    CacheRepo.get("map:characters") || []
  end

  # Helper functions for role determination
  defp determine_character_role(killmail, character_id) do
    cond do
      is_victim?(killmail, character_id) ->
        {:ok, :victim}

      is_attacker?(killmail, character_id) ->
        {:ok, :attacker}

      true ->
        {:error, :character_not_involved}
    end
  end

  defp is_victim?(killmail, character_id) do
    victim = KillmailStruct.get_victim(killmail) || %{}
    Map.get(victim, "character_id") == character_id
  end

  defp is_attacker?(killmail, character_id) do
    attackers = KillmailStruct.get_attacker(killmail) || []
    Enum.any?(attackers, &(Map.get(&1, "character_id") == character_id))
  end

  defp update_recent_killmails_cache(character_id) do
    cache_key = "zkill:recent_kills"

    # Update the cache of recent killmail IDs
    CacheRepo.get_and_update(
      cache_key,
      fn current_ids ->
        current_ids = current_ids || []

        # Add the new killmail ID to the front of the list
        updated_ids =
          [character_id | current_ids]
          |> Enum.uniq()
          # Keep only the 10 most recent
          |> Enum.take(10)

        {current_ids, updated_ids}
      end,
      # 1 hour TTL
      3600
    )

    # Also store the individual killmail
    individual_key = "#{cache_key}:#{character_id}"
    CacheRepo.update_after_db_write(individual_key, character_id, 3600)
  end
end
