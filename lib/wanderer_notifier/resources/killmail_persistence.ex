defmodule WandererNotifier.Resources.KillmailPersistence do
  @moduledoc """
  Service for persisting killmail information related to tracked characters.
  Only killmails involving tracked characters are stored in the database.
  """

  require Logger
  alias WandererNotifier.Data.Killmail, as: KillmailStruct
  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

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
    if kill_charts_enabled?() do
      # First check if the killmail involves any tracked characters
      with tracked_characters <- get_tracked_characters(),
           {character_id, character_name, role} <-
             find_tracked_character_in_killmail(killmail, tracked_characters),
           true <- not is_nil(character_id) do
        # We found a tracked character in the killmail, persist it
        Logger.debug(
          "[KillmailPersistence] Persisting killmail #{killmail.killmail_id} for character #{character_id}"
        )

        # Transform the killmail struct to the Ash resource format
        killmail_attrs =
          transform_killmail_to_resource(killmail, character_id, character_name, role)

        # Insert into database via Ash framework
        case create_killmail_record(killmail_attrs) do
          {:ok, record} ->
            Logger.info(
              "[KillmailPersistence] Successfully persisted killmail #{killmail.killmail_id}"
            )

            {:ok, record}

          {:error, error} ->
            Logger.error(
              "[KillmailPersistence] Failed to persist killmail #{killmail.killmail_id}: #{inspect(error)}"
            )

            {:error, error}
        end
      else
        _ ->
          # Killmail doesn't involve a tracked character, ignore it
          :ignored
      end
    else
      # Persistence disabled, skip
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
      Killmail.list_for_character(character_id, from_date, to_date, limit)
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

    # Build the resource attributes map
    %{
      killmail_id: parse_integer(killmail.killmail_id),
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
    # Use the Ash API for creation to ensure proper handling
    attrs
    |> Killmail.create!()
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
end
